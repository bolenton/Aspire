package companion

import (
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
)

type message struct {
	Type     string `json:"type"`
	ID       int64  `json:"id"`
	Revision int64  `json:"revision"`
	Text     string `json:"text"`
	PCM      string `json:"pcm"`
	World    *World `json:"world"`
}
type connection struct {
	server    *Server
	socket    *websocket.Conn
	ctx       context.Context
	device    string
	writeMu   sync.Mutex
	mu        sync.Mutex
	world     World
	active    int64
	cancel    context.CancelFunc
	turnCtx   context.Context
	audio     []byte
	voiced    int
	silence   int
	listening bool
}

func (c *connection) send(ctx context.Context, value any) error {
	raw, err := json.Marshal(value)
	if err != nil {
		return err
	}
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	if err := ctx.Err(); err != nil {
		return err
	}
	bounded, cancel := context.WithTimeout(c.ctx, 8*time.Second)
	defer cancel()
	return c.socket.Write(bounded, websocket.MessageText, raw)
}
func (c *connection) stop() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cancel != nil {
		c.cancel()
		c.cancel = nil
	}
	c.listening = false
	c.audio = nil
}
func (c *connection) begin(id int64) (context.Context, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if id <= c.active {
		return nil, fmt.Errorf("request id must increase")
	}
	if c.cancel != nil {
		c.cancel()
	}
	ctx, cancel := context.WithTimeout(c.ctx, 45*time.Second)
	c.cancel = cancel
	c.turnCtx = ctx
	c.active = id
	c.audio = nil
	c.voiced = 0
	c.silence = 0
	c.listening = false
	return ctx, nil
}
func (c *connection) receive(m message) error {
	switch m.Type {
	case "world":
		if m.World == nil {
			return fmt.Errorf("missing world")
		}
		if err := m.World.Validate(); err != nil {
			return err
		}
		c.mu.Lock()
		changed := c.world.AdventureID != "" && (c.world.Revision != m.World.Revision || c.world.AdventureID != m.World.AdventureID)
		c.world = *m.World
		if changed && c.cancel != nil {
			c.cancel()
			c.listening = false
			c.audio = nil
		}
		id := c.active
		c.mu.Unlock()
		if changed {
			return c.send(c.ctx, map[string]any{"type": "cancelled", "id": id})
		}
	case "cancel":
		c.mu.Lock()
		if m.ID == c.active {
			if c.cancel != nil {
				c.cancel()
			}
			c.listening = false
			c.audio = nil
		}
		c.mu.Unlock()
	case "listen":
		ctx, err := c.begin(m.ID)
		if err != nil {
			return err
		}
		c.mu.Lock()
		c.listening = true
		c.mu.Unlock()
		go func() {
			select {
			case <-time.After(25 * time.Second):
				c.mu.Lock()
				waiting := c.active == m.ID && c.listening
				c.mu.Unlock()
				if waiting {
					c.stop()
					_ = c.send(c.ctx, map[string]any{"type": "idle", "id": m.ID})
				}
			case <-ctx.Done():
			}
		}()
		return c.send(ctx, map[string]any{"type": "listening", "id": m.ID})
	case "audio":
		return c.audioChunk(m)
	case "commit":
		return c.transcribe(m.ID)
	case "reply", "speak":
		if len(m.Text) == 0 || len(m.Text) > 2500 {
			return fmt.Errorf("invalid text length")
		}
		ctx, err := c.begin(m.ID)
		if err != nil {
			return err
		}
		c.mu.Lock()
		world := c.world
		c.mu.Unlock()
		if world.AdventureID == "" {
			return fmt.Errorf("world not ready")
		}
		if m.Type == "reply" && m.Revision != world.Revision {
			return c.send(ctx, map[string]any{"type": "cancelled", "id": m.ID})
		}
		go c.answer(ctx, m, world)
	case "forget":
		c.stop()
		c.mu.Lock()
		adventure := c.world.AdventureID
		c.mu.Unlock()
		return c.server.store.Forget(c.ctx, c.device, adventure)
	default:
		return fmt.Errorf("unknown message")
	}
	return nil
}
func (c *connection) audioChunk(m message) error {
	data, err := base64.StdEncoding.DecodeString(m.PCM)
	if err != nil || len(data) > 12800 || len(data)%2 != 0 {
		return fmt.Errorf("invalid PCM frame")
	}
	c.mu.Lock()
	if m.ID != c.active || !c.listening {
		c.mu.Unlock()
		return nil
	}
	var energy float64
	for i := 0; i < len(data); i += 2 {
		v := float64(int16(binary.LittleEndian.Uint16(data[i:])))
		energy += v * v
	}
	rms := math.Sqrt(energy / math.Max(1, float64(len(data)/2)))
	c.audio = append(c.audio, data...)
	if rms > 260 {
		c.voiced += len(data)
		c.silence = 0
	} else {
		c.silence += len(data)
	}
	endpoint := c.voiced >= 9600 && c.silence >= 32000
	maxed := len(c.audio) >= 640000
	c.mu.Unlock()
	if endpoint || maxed {
		return c.transcribe(m.ID)
	}
	return nil
}
func (c *connection) transcribe(id int64) error {
	c.mu.Lock()
	if c.active != id || !c.listening {
		c.mu.Unlock()
		return nil
	}
	c.listening = false
	audio := c.audio
	c.audio = nil
	voiced := c.voiced
	turnCtx := c.turnCtx
	c.mu.Unlock()
	if voiced < 6400 {
		return c.send(c.ctx, map[string]any{"type": "idle", "id": id})
	}
	_ = c.send(c.ctx, map[string]any{"type": "transcribing", "id": id})
	go func() {
		ctx, cancel := context.WithTimeout(turnCtx, 20*time.Second)
		defer cancel()
		text, err := c.server.engines.Transcribe(ctx, audio)
		c.mu.Lock()
		valid := c.active == id && turnCtx.Err() == nil
		if c.cancel == nil {
			valid = false
		}
		c.mu.Unlock()
		if !valid {
			return
		}
		if err != nil {
			_ = c.send(c.ctx, map[string]any{"type": "error", "id": id, "text": "I couldn't hear that clearly. Tap my microphone and try again."})
			return
		}
		if text == "" || strings.HasPrefix(text, "[") || len(text) > 1500 {
			_ = c.send(c.ctx, map[string]any{"type": "idle", "id": id})
			return
		}
		_ = c.send(c.ctx, map[string]any{"type": "transcript", "id": id, "text": text})
	}()
	return nil
}
func (c *connection) answer(ctx context.Context, m message, world World) {
	started := time.Now()
	select {
	case c.server.slots <- struct{}{}:
		defer func() { <-c.server.slots }()
	case <-ctx.Done():
		return
	}
	send := func(kind, text string) error {
		return c.send(ctx, map[string]any{"type": kind, "id": m.ID, "revision": world.Revision, "text": text})
	}
	// One bounded synthesis queue overlaps model tokens and sentence synthesis.
	sentences := make(chan string, 8)
	audioDone := make(chan error, 1)
	go func() {
		for sentence := range sentences {
			wav, err := c.server.engines.Speak(ctx, sentence)
			if err != nil {
				audioDone <- err
				return
			}
			if err = c.send(ctx, map[string]any{"type": "audio", "id": m.ID, "wav": base64.StdEncoding.EncodeToString(wav), "text": sentence}); err != nil {
				audioDone <- err
				return
			}
		}
		audioDone <- nil
	}()
	enqueue := func(text string) error {
		if text = strings.TrimSpace(text); text != "" {
			select {
			case sentences <- text:
				return nil
			case err := <-audioDone:
				audioDone <- err
				return err
			case <-ctx.Done():
				return ctx.Err()
			}
		}
		return nil
	}
	var full, buffer strings.Builder
	var generationErr error
	if m.Type == "speak" {
		full.WriteString(m.Text)
		generationErr = enqueue(m.Text)
	} else {
		history, err := c.server.store.History(ctx, c.device, world.AdventureID)
		if err != nil {
			generationErr = err
		} else {
			generationErr = c.server.engines.Chat(ctx, messagesFor(world, history, m.Text), func(delta string) error {
				if full.Len()+len(delta) > 2500 {
					return fmt.Errorf("reply exceeded length limit")
				}
				full.WriteString(delta)
				buffer.WriteString(delta)
				if err := send("text", delta); err != nil {
					return err
				}
				text := buffer.String()
				for {
					cut := sentenceEnd(text)
					if cut < 0 {
						break
					}
					if err := enqueue(text[:cut]); err != nil {
						return err
					}
					text = text[cut:]
				}
				buffer.Reset()
				buffer.WriteString(text)
				return nil
			})
			if generationErr == nil {
				generationErr = enqueue(buffer.String())
			}
		}
	}
	close(sentences)
	audioErr := <-audioDone
	if ctx.Err() != nil {
		return
	}
	if generationErr != nil || audioErr != nil {
		_ = send("error", "My voice needs a moment. We can still explore together.")
		return
	}
	if m.Type == "reply" {
		if err := c.server.store.Remember(ctx, c.device, world.AdventureID, m.Text, full.String()); err != nil {
			_ = send("error", "I couldn't keep our conversation this time.")
			return
		}
	}
	_ = c.send(ctx, map[string]any{"type": "done", "id": m.ID, "text": full.String(), "revision": world.Revision, "elapsedMs": time.Since(started).Milliseconds()})
}
func sentenceEnd(text string) int {
	for i, r := range text {
		if strings.ContainsRune(".!?\n", r) && i+1 < len(text) && strings.ContainsRune(" \n\t", rune(text[i+1])) {
			return i + 1
		}
	}
	return -1
}
