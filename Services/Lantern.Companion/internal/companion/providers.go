package companion

import (
	"bufio"
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strings"
	"time"
)

type Engines interface {
	Transcribe(context.Context, []byte) (string, error)
	Speak(context.Context, string) ([]byte, error)
	Chat(context.Context, []ChatMessage, func(string) error) error
	Health(context.Context) error
}
type LocalEngines struct {
	Config Config
	Client *http.Client
}

func NewEngines(c Config) *LocalEngines {
	return &LocalEngines{c, &http.Client{Transport: &http.Transport{ResponseHeaderTimeout: 45 * time.Second, IdleConnTimeout: 90 * time.Second}}}
}
func (p *LocalEngines) request(ctx context.Context, url, content string, body io.Reader) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, "POST", url, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", content)
	res, err := p.Client.Do(req)
	if err != nil {
		return nil, err
	}
	if res.StatusCode != 200 {
		res.Body.Close()
		return nil, fmt.Errorf("local inference returned %d", res.StatusCode)
	}
	return res, nil
}
func WAV(pcm []byte) []byte {
	out := make([]byte, 44+len(pcm))
	copy(out, "RIFF")
	binary.LittleEndian.PutUint32(out[4:], uint32(36+len(pcm)))
	copy(out[8:], "WAVEfmt ")
	binary.LittleEndian.PutUint32(out[16:], 16)
	binary.LittleEndian.PutUint16(out[20:], 1)
	binary.LittleEndian.PutUint16(out[22:], 1)
	binary.LittleEndian.PutUint32(out[24:], 16000)
	binary.LittleEndian.PutUint32(out[28:], 32000)
	binary.LittleEndian.PutUint16(out[32:], 2)
	binary.LittleEndian.PutUint16(out[34:], 16)
	copy(out[36:], "data")
	binary.LittleEndian.PutUint32(out[40:], uint32(len(pcm)))
	copy(out[44:], pcm)
	return out
}
func (p *LocalEngines) Transcribe(ctx context.Context, pcm []byte) (string, error) {
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	part, err := mw.CreateFormFile("file", "speech.wav")
	if err != nil {
		return "", err
	}
	if _, err = part.Write(WAV(pcm)); err != nil {
		return "", err
	}
	for k, v := range map[string]string{"temperature": "0.0", "response_format": "json", "language": "en"} {
		if err = mw.WriteField(k, v); err != nil {
			return "", err
		}
	}
	if err = mw.Close(); err != nil {
		return "", err
	}
	res, err := p.request(ctx, strings.TrimRight(p.Config.WhisperURL, "/")+"/inference", mw.FormDataContentType(), &body)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	var out struct {
		Text string `json:"text"`
	}
	err = json.NewDecoder(io.LimitReader(res.Body, 16384)).Decode(&out)
	return strings.TrimSpace(out.Text), err
}
func (p *LocalEngines) Speak(ctx context.Context, text string) ([]byte, error) {
	raw, _ := json.Marshal(map[string]any{"text": text, "length_scale": 1.05})
	res, err := p.request(ctx, strings.TrimRight(p.Config.PiperURL, "/")+"/", "application/json", bytes.NewReader(raw))
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	data, err := io.ReadAll(io.LimitReader(res.Body, 2<<20))
	if err != nil {
		return nil, err
	}
	if len(data) < 44 || string(data[:4]) != "RIFF" {
		return nil, fmt.Errorf("Piper returned invalid audio")
	}
	return data, nil
}
func (p *LocalEngines) Chat(ctx context.Context, messages []ChatMessage, emit func(string) error) error {
	raw, _ := json.Marshal(map[string]any{"model": p.Config.Model, "messages": messages, "stream": true, "think": false, "keep_alive": "10m", "options": map[string]any{"num_ctx": 8192, "num_predict": 160, "temperature": 0.65}})
	res, err := p.request(ctx, strings.TrimRight(p.Config.OllamaURL, "/")+"/api/chat", "application/json", bytes.NewReader(raw))
	if err != nil {
		return err
	}
	defer res.Body.Close()
	scan := bufio.NewScanner(res.Body)
	scan.Buffer(make([]byte, 8192), 256<<10)
	for scan.Scan() {
		var chunk struct {
			Message ChatMessage `json:"message"`
			Done    bool        `json:"done"`
			Error   string      `json:"error"`
		}
		if err = json.Unmarshal(scan.Bytes(), &chunk); err != nil {
			return err
		}
		if chunk.Error != "" {
			return fmt.Errorf("model generation failed")
		}
		if chunk.Message.Content != "" {
			if err = emit(chunk.Message.Content); err != nil {
				return err
			}
		}
		if chunk.Done {
			return nil
		}
	}
	if err = scan.Err(); err != nil {
		return err
	}
	return fmt.Errorf("model stream ended without completion")
}
func (p *LocalEngines) Health(ctx context.Context) error {
	for _, url := range []string{p.Config.WhisperURL + "/", p.Config.PiperURL + "/voices", p.Config.OllamaURL + "/api/tags"} {
		req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
		if err != nil {
			return err
		}
		res, err := p.Client.Do(req)
		if err != nil {
			return err
		}
		res.Body.Close()
		if res.StatusCode != 200 {
			return fmt.Errorf("inference service unavailable")
		}
	}
	return nil
}

// Prepare the model once at service startup, before a child's first spoken turn.
func (p *LocalEngines) Warm(ctx context.Context) error {
	raw, _ := json.Marshal(map[string]any{"model": p.Config.Model, "keep_alive": "30m"})
	res, err := p.request(ctx, strings.TrimRight(p.Config.OllamaURL, "/")+"/api/generate", "application/json", bytes.NewReader(raw))
	if err != nil {
		return err
	}
	defer res.Body.Close()
	_, err = io.Copy(io.Discard, io.LimitReader(res.Body, 16384))
	return err
}
