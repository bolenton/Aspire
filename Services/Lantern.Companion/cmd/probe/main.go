// Probe uses an authored synthetic utterance; it never records a microphone.
package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/bolenton/Aspire/companion/internal/companion"
	"github.com/coder/websocket"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run() error {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	config, err := companion.LoadConfig()
	if err != nil {
		return err
	}
	engines := companion.NewEngines(config)
	if err = engines.Health(ctx); err != nil {
		return err
	}
	authored := "Ember, what are we doing in the orchard?"
	wav, err := engines.Speak(ctx, authored)
	if err != nil {
		return err
	}
	pcm, err := resample(wav)
	if err != nil {
		return err
	}
	url := os.Getenv("LANTERN_PROBE_URL")
	if url == "" {
		url = "http://127.0.0.1:8486"
	}
	token := os.Getenv("LANTERN_PROBE_TOKEN")
	if token == "" {
		raw, _ := json.Marshal(map[string]string{"code": config.PairCode})
		res, err := http.Post(url+"/v1/pair", "application/json", bytes.NewReader(raw))
		if err != nil {
			return err
		}
		defer res.Body.Close()
		if res.StatusCode != 200 {
			return fmt.Errorf("pair: %d", res.StatusCode)
		}
		var pair struct{ Token string }
		if err = json.NewDecoder(res.Body).Decode(&pair); err != nil {
			return err
		}
		token = pair.Token
		if path := os.Getenv("LANTERN_PROBE_TOKEN_FILE"); path != "" {
			if err = os.WriteFile(path, []byte(token), 0600); err != nil {
				return err
			}
		}
	}
	headers := http.Header{}
	headers.Set("Authorization", "Bearer "+token)
	ws, _, err := websocket.Dial(ctx, strings.Replace(strings.Replace(url, "https://", "wss://", 1), "http://", "ws://", 1)+"/v1/companion", &websocket.DialOptions{HTTPHeader: headers})
	if err != nil {
		return err
	}
	defer ws.CloseNow()
	ws.SetReadLimit(3 << 20)
	send := func(v any) error { raw, _ := json.Marshal(v); return ws.Write(ctx, websocket.MessageText, raw) }
	world := companion.World{Revision: 1, AdventureID: "synthetic-orchard-check", Scene: "Fox Hollow", Region: "Lantern Orchard", Quest: "Luma's Lantern Orchard", Objective: "Play the moon harp to wake the fireflies", TargetID: "moon_harp", Activity: "Exploring", Memories: []string{"We promised Luma the owl to help the fireflies find a home."}, Entities: []companion.Entity{{ID: "luma", Name: "Luma the owl", Available: true}, {ID: "moon_harp", Name: "Moon harp", Available: true, Guidance: "Follow the pale path to the moon harp. You can ask me to guide you."}}}
	if err = send(map[string]any{"type": "world", "world": world}); err != nil {
		return err
	}
	if err = send(map[string]any{"type": "listen", "id": 1}); err != nil {
		return err
	}
	for start := 0; start < len(pcm); start += 6400 {
		end := start + 6400
		if end > len(pcm) {
			end = len(pcm)
		}
		if err = send(map[string]any{"type": "audio", "id": 1, "pcm": base64.StdEncoding.EncodeToString(pcm[start:end])}); err != nil {
			return err
		}
	}
	if err = send(map[string]any{"type": "commit", "id": 1}); err != nil {
		return err
	}
	transcript := ""
	started := time.Now()
	id := int64(1)
	audioCount := 0
	firstAudio := false
	for {
		_, raw, err := ws.Read(ctx)
		if err != nil {
			return err
		}
		var event struct {
			Type, Text, Wav string
			ID              int64
			ElapsedMS       int64 `json:"elapsedMs"`
		}
		if err = json.Unmarshal(raw, &event); err != nil {
			return err
		}
		if event.Type == "error" {
			return fmt.Errorf("server: %s", event.Text)
		}
		if event.Type == "transcript" {
			transcript = event.Text
			fmt.Printf("Whisper authored transcript: %s\n", transcript)
			id = 2
			started = time.Now()
			if err = send(map[string]any{"type": "reply", "id": id, "text": transcript, "revision": 1}); err != nil {
				return err
			}
		}
		if event.Type == "audio" {
			audioCount++
			if !firstAudio {
				fmt.Printf("First spoken sentence: %.2fs\n", time.Since(started).Seconds())
				firstAudio = true
			}
			if path := os.Getenv("LANTERN_PROBE_AUDIO_FILE"); path != "" && audioCount == 1 {
				data, err := base64.StdEncoding.DecodeString(event.Wav)
				if err != nil {
					return err
				}
				if err = os.WriteFile(path, data, 0600); err != nil {
					return err
				}
			}
		}
		if event.Type == "done" && event.ID == id {
			fmt.Printf("Ember: %s\nTotal: %dms; audio sentences: %d\n", event.Text, event.ElapsedMS, audioCount)
			if audioCount == 0 || transcript == "" {
				return fmt.Errorf("missing speech")
			}
			if id == 3 {
				fmt.Println("PASS: synthetic Whisper, contextual Ollama, streamed Piper, follow-up turn.")
				return nil
			}
			id = 3
			audioCount = 0
			firstAudio = false
			started = time.Now()
			if err = send(map[string]any{"type": "reply", "id": id, "text": "Who did we promise to help?", "revision": 1}); err != nil {
				return err
			}
		}
	}
}
func resample(wav []byte) ([]byte, error) {
	var rate, channels int
	var data []byte
	for i := 12; i+8 <= len(wav); {
		size := int(binary.LittleEndian.Uint32(wav[i+4:]))
		start := i + 8
		if size < 0 || start+size > len(wav) {
			return nil, io.ErrUnexpectedEOF
		}
		switch string(wav[i : i+4]) {
		case "fmt ":
			if size < 16 || binary.LittleEndian.Uint16(wav[start:]) != 1 || binary.LittleEndian.Uint16(wav[start+14:]) != 16 {
				return nil, fmt.Errorf("PCM16 required")
			}
			channels = int(binary.LittleEndian.Uint16(wav[start+2:]))
			rate = int(binary.LittleEndian.Uint32(wav[start+4:]))
		case "data":
			data = wav[start : start+size]
		}
		i = start + size + size%2
	}
	if rate < 8000 || channels < 1 || len(data) == 0 {
		return nil, fmt.Errorf("invalid WAV")
	}
	frames := len(data) / (channels * 2)
	count := frames * 16000 / rate
	out := make([]byte, count*2)
	for i := 0; i < count; i++ {
		source := i * rate / 16000
		var sum int
		for ch := 0; ch < channels; ch++ {
			sum += int(int16(binary.LittleEndian.Uint16(data[(source*channels+ch)*2:])))
		}
		binary.LittleEndian.PutUint16(out[i*2:], uint16(int16(sum/channels)))
	}
	return out, nil
}
