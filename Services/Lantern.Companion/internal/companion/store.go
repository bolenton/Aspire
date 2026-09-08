package companion

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	_ "modernc.org/sqlite"
	"os"
	"path/filepath"
	"time"
)

type Store struct{ db *sql.DB }

func OpenStore(path string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	// Forward migration 1 is atomic and safe to run on every startup.
	_, err = db.Exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
 BEGIN;
 CREATE TABLE IF NOT EXISTS schema_version(version INTEGER PRIMARY KEY);
 CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY,token_hash TEXT NOT NULL UNIQUE,created_at INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS turns(id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL, adventure_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, created_at INTEGER NOT NULL);
 CREATE INDEX IF NOT EXISTS turns_session ON turns(device_id,adventure_id,id);
 INSERT OR IGNORE INTO schema_version VALUES(1);
 COMMIT;`)
	if err != nil {
		db.Close()
		return nil, err
	}
	_ = os.Chmod(path, 0600)
	return &Store{db}, nil
}
func (s *Store) Close() error { return s.db.Close() }
func hashToken(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:])
}
func (s *Store) Pair(ctx context.Context) (string, string, error) {
	var bytes [32]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", "", err
	}
	token := hex.EncodeToString(bytes[:])
	id := "device-" + token[:16]
	_, err := s.db.ExecContext(ctx, "INSERT INTO devices VALUES(?,?,?)", id, hashToken(token), time.Now().Unix())
	return id, token, err
}
func (s *Store) Authenticate(ctx context.Context, token string) (string, error) {
	if len(token) != 64 {
		return "", fmt.Errorf("invalid token")
	}
	var id string
	err := s.db.QueryRowContext(ctx, "SELECT id FROM devices WHERE token_hash=?", hashToken(token)).Scan(&id)
	return id, err
}
func (s *Store) History(ctx context.Context, device, adventure string) ([]ChatMessage, error) {
	rows, err := s.db.QueryContext(ctx, "SELECT role,content FROM (SELECT id,role,content FROM turns WHERE device_id=? AND adventure_id=? ORDER BY id DESC LIMIT 12) ORDER BY id", device, adventure)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []ChatMessage
	for rows.Next() {
		var m ChatMessage
		if err := rows.Scan(&m.Role, &m.Content); err != nil {
			return nil, err
		}
		result = append(result, m)
	}
	return result, rows.Err()
}
func (s *Store) Remember(ctx context.Context, device, adventure, question, answer string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, m := range []ChatMessage{{"user", question}, {"assistant", answer}} {
		if _, err = tx.ExecContext(ctx, "INSERT INTO turns(device_id,adventure_id,role,content,created_at) VALUES(?,?,?,?,?)", device, adventure, m.Role, m.Content, time.Now().Unix()); err != nil {
			return err
		}
	}
	// Retain only a small recent window; durable game memories come from the player's saved journal.
	_, err = tx.ExecContext(ctx, "DELETE FROM turns WHERE device_id=? AND adventure_id=? AND id NOT IN (SELECT id FROM turns WHERE device_id=? AND adventure_id=? ORDER BY id DESC LIMIT 24)", device, adventure, device, adventure)
	if err != nil {
		return err
	}
	return tx.Commit()
}
func (s *Store) Forget(ctx context.Context, device, adventure string) error {
	_, err := s.db.ExecContext(ctx, "DELETE FROM turns WHERE device_id=? AND adventure_id=?", device, adventure)
	return err
}
