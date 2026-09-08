package companion

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"github.com/coder/websocket"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type testEngines struct {
	mu       sync.Mutex
	messages []ChatMessage
}

func (*testEngines) Transcribe(context.Context, []byte) (string, error) {
	return "Tell me about this orchard", nil
}
func (*testEngines) Speak(context.Context, string) ([]byte, error) {
	return WAV(make([]byte, 320)), nil
}
func (e *testEngines) Chat(ctx context.Context, m []ChatMessage, emit func(string) error) error {
	e.mu.Lock()
	e.messages = append([]ChatMessage(nil), m...)
	e.mu.Unlock()
	if m[len(m)-1].Content == "wait for cancellation" {
		<-ctx.Done()
		return ctx.Err()
	}
	if err := emit("The moon harp is ready. "); err != nil {
		return err
	}
	return emit("We can play together.")
}
func (*testEngines) Health(context.Context) error { return nil }
func fixture(t *testing.T) (*httptest.Server, *Store, *testEngines, string) {
	t.Helper()
	s, err := OpenStore(filepath.Join(t.TempDir(), "store.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	engines := &testEngines{}
	app := NewServer(Config{PairCode: "test-pair-code-long", Model: "local-test"}, s, engines)
	httpServer := httptest.NewServer(app.Handler())
	t.Cleanup(httpServer.Close)
	res, err := http.Post(httpServer.URL+"/v1/pair", "application/json", strings.NewReader(`{"code":"test-pair-code-long"}`))
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var paired map[string]string
	json.NewDecoder(res.Body).Decode(&paired)
	return httpServer, s, engines, paired["token"]
}
func dial(t *testing.T, url, token string) (context.Context, *websocket.Conn) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	ws, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(url, "http")+"/v1/companion", &websocket.DialOptions{HTTPHeader: http.Header{"Authorization": []string{"Bearer " + token}}})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ws.CloseNow() })
	readUntil(t, ctx, ws, "connected")
	return ctx, ws
}
func sendTest(t *testing.T, ctx context.Context, ws *websocket.Conn, v any) {
	t.Helper()
	raw, _ := json.Marshal(v)
	if err := ws.Write(ctx, websocket.MessageText, raw); err != nil {
		t.Fatal(err)
	}
}
func readUntil(t *testing.T, ctx context.Context, ws *websocket.Conn, kind string) map[string]any {
	t.Helper()
	for {
		_, data, err := ws.Read(ctx)
		if err != nil {
			t.Fatal(err)
		}
		var m map[string]any
		json.Unmarshal(data, &m)
		if m["type"] == "error" {
			t.Fatalf("server error: %v", m)
		}
		if m["type"] == kind {
			return m
		}
	}
}
func TestVoiceWorldMemoryAndPiperRoundTrip(t *testing.T) {
	host, store, engines, token := fixture(t)
	ctx, ws := dial(t, host.URL, token)
	world := World{AdventureID: "adventure-a", Revision: 1, Region: "Lantern Orchard", Objective: "Play the moon harp", Entities: []Entity{{ID: "harp", Name: "Moon harp", Available: true}, {ID: "hidden", Name: "Hidden dragon", Available: false}}}
	sendTest(t, ctx, ws, message{Type: "world", World: &world})
	sendTest(t, ctx, ws, message{Type: "listen", ID: 1})
	readUntil(t, ctx, ws, "listening")
	pcm := bytes.Repeat([]byte{0x00, 0x10}, 6400)
	sendTest(t, ctx, ws, message{Type: "audio", ID: 1, PCM: base64.StdEncoding.EncodeToString(pcm)})
	sendTest(t, ctx, ws, message{Type: "commit", ID: 1})
	transcript := readUntil(t, ctx, ws, "transcript")
	sendTest(t, ctx, ws, message{Type: "reply", ID: 2, Revision: 1, Text: transcript["text"].(string)})
	audio := readUntil(t, ctx, ws, "audio")
	raw, _ := base64.StdEncoding.DecodeString(audio["wav"].(string))
	if string(raw[:4]) != "RIFF" {
		t.Fatal("missing Piper WAV")
	}
	readUntil(t, ctx, ws, "done")
	engines.mu.Lock()
	prompt := engines.messages[0].Content
	engines.mu.Unlock()
	if strings.Contains(prompt, "Hidden dragon") || !strings.Contains(prompt, "Moon harp") {
		t.Fatal("incorrect world grounding")
	}
	device, _ := store.Authenticate(ctx, token)
	history, _ := store.History(ctx, device, "adventure-a")
	if len(history) != 2 {
		t.Fatal("conversation not remembered")
	}
	other, _ := store.History(ctx, device, "other-adventure")
	if len(other) != 0 {
		t.Fatal("adventure history leaked")
	}
	sendTest(t, ctx, ws, message{Type: "reply", ID: 3, Revision: 1, Text: "What about our song?"})
	readUntil(t, ctx, ws, "done")
	engines.mu.Lock()
	count := len(engines.messages)
	engines.mu.Unlock()
	if count != 4 {
		t.Fatal("follow-up lost context")
	}
}
func TestCancellationKeepsSocketUsableAndStaleWorldCannotReply(t *testing.T) {
	host, _, _, token := fixture(t)
	ctx, ws := dial(t, host.URL, token)
	w := World{AdventureID: "save", Revision: 1}
	sendTest(t, ctx, ws, message{Type: "world", World: &w})
	sendTest(t, ctx, ws, message{Type: "reply", ID: 1, Revision: 1, Text: "wait for cancellation"})
	sendTest(t, ctx, ws, message{Type: "cancel", ID: 1})
	sendTest(t, ctx, ws, message{Type: "speak", ID: 2, Text: "We stopped."})
	readUntil(t, ctx, ws, "done")
	w.Revision = 2
	sendTest(t, ctx, ws, message{Type: "world", World: &w})
	readUntil(t, ctx, ws, "cancelled")
	sendTest(t, ctx, ws, message{Type: "reply", ID: 3, Revision: 1, Text: "stale"})
	readUntil(t, ctx, ws, "cancelled")
	sendTest(t, ctx, ws, message{Type: "speak", ID: 4, Text: "Still here."})
	readUntil(t, ctx, ws, "done")
}
func TestUnauthenticatedClientsAndWrongPairCodeAreRejected(t *testing.T) {
	host, _, _, _ := fixture(t)
	res, err := http.Get(host.URL + "/v1/companion")
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != 401 {
		t.Fatal(res.StatusCode)
	}
	res, err = http.Post(host.URL+"/v1/pair", "application/json", strings.NewReader(`{"code":"wrong"}`))
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != 403 {
		t.Fatal(res.StatusCode)
	}
}
