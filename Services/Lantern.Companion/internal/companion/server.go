package companion

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
)

// A family setup window accommodates devices that are asleep during deployment.
const pairingWindow = 7 * 24 * time.Hour

type Server struct {
	config      Config
	store       *Store
	engines     Engines
	mu          sync.Mutex
	pairUses    int
	pairExpires time.Time
	connections map[string]context.CancelFunc
	slots       chan struct{}
}

func NewServer(c Config, s *Store, e Engines) *Server {
	return &Server{config: c, store: s, engines: e, pairExpires: time.Now().Add(pairingWindow), connections: make(map[string]context.CancelFunc), slots: make(chan struct{}, 2)}
}
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]any{"status": "ok", "protocol": 1})
	})
	mux.HandleFunc("POST /v1/pair", s.pair)
	mux.HandleFunc("GET /v1/ready", func(w http.ResponseWriter, r *http.Request) {
		if _, err := s.authenticate(r); err != nil {
			http.Error(w, "unauthorized", 401)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		if err := s.engines.Health(ctx); err != nil {
			http.Error(w, "local inference unavailable", 503)
			return
		}
		writeJSON(w, map[string]any{"ready": true, "model": s.config.Model, "speech": "Piper", "recognition": "Whisper"})
	})
	mux.HandleFunc("GET /v1/companion", s.connect)
	return mux
}
func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(v)
}
func (s *Server) pair(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Code string `json:"code"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048)).Decode(&input); err != nil {
		http.Error(w, "invalid request", 400)
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.pairUses >= 4 || time.Now().After(s.pairExpires) || subtle.ConstantTimeCompare([]byte(input.Code), []byte(s.config.PairCode)) != 1 {
		http.Error(w, "pairing unavailable", 403)
		return
	}
	id, token, err := s.store.Pair(r.Context())
	if err != nil {
		http.Error(w, "pairing failed", 500)
		return
	}
	s.pairUses++
	writeJSON(w, map[string]string{"deviceId": id, "token": token})
}
func (s *Server) authenticate(r *http.Request) (string, error) {
	return s.store.Authenticate(r.Context(), strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
}
func (s *Server) connect(w http.ResponseWriter, r *http.Request) {
	device, err := s.authenticate(r)
	if err != nil {
		http.Error(w, "unauthorized", 401)
		return
	}
	ws, err := websocket.Accept(w, r, nil)
	if err != nil {
		return
	}
	defer ws.CloseNow()
	ws.SetReadLimit(128 << 10)
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	s.mu.Lock()
	if old := s.connections[device]; old != nil {
		old()
	}
	s.connections[device] = cancel
	s.mu.Unlock()
	c := &connection{server: s, socket: ws, ctx: ctx, device: device}
	defer c.stop()
	_ = c.send(ctx, map[string]any{"type": "connected", "protocol": 1})
	for {
		kind, data, err := ws.Read(ctx)
		if err != nil {
			return
		}
		if kind != websocket.MessageText {
			continue
		}
		var m message
		if err = json.Unmarshal(data, &m); err != nil {
			continue
		}
		if err = c.receive(m); err != nil {
			slog.Warn("companion protocol request rejected", "reason", err.Error())
			_ = c.send(ctx, map[string]any{"type": "error", "id": m.ID, "text": "Let's pause for a moment and try again."})
		}
	}
}
