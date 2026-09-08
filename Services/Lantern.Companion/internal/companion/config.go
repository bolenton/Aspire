package companion

import (
	"fmt"
	"os"
)

type Config struct{ Address, Database, WhisperURL, PiperURL, OllamaURL, Model, PairCode string }

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
func LoadConfig() (Config, error) {
	c := Config{Address: env("LANTERN_LISTEN", "127.0.0.1:8486"), Database: env("LANTERN_DATABASE", "data/companion.db"), WhisperURL: env("LANTERN_WHISPER_URL", "http://127.0.0.1:8081"), PiperURL: env("LANTERN_PIPER_URL", "http://127.0.0.1:5000"), OllamaURL: env("LANTERN_OLLAMA_URL", "http://127.0.0.1:11434"), Model: os.Getenv("LANTERN_MODEL"), PairCode: os.Getenv("LANTERN_PAIR_CODE")}
	if c.Model == "" {
		return c, fmt.Errorf("LANTERN_MODEL must name an installed local model")
	}
	if len(c.PairCode) < 12 {
		return c, fmt.Errorf("LANTERN_PAIR_CODE must contain at least 12 characters")
	}
	return c, nil
}
