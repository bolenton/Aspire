# Ember's family companion server

A separate Go service connects Lantern's Unity client to existing Whisper.cpp, Ollama and Piper services. SQLite migrations run at startup. No cloud inference, microphone recordings or transcript logging. Recent dialogue is retained in the private database (24 messages per device/adventure, 12 sent to the model); the game's saved journal supplies longer-term story memories. The parent menu can forget the server conversation.

## Deploy

Copy `.env.example` to `.env`, set a random pairing code and an installed Ollama model, and set inference URLs reachable from the container. Use `docker compose up -d --build`. The service publishes only `127.0.0.1:8486`; use a private HTTPS reverse proxy for devices. Never expose pairing or inference directly to the public internet.

For Conduit's existing rootless Docker installation use `docker compose -f compose.yml -f compose.conduit.yml up -d --build`. This joins the existing `conduit-speech_default` network, using Whisper and Piper by service name. Point `LANTERN_OLLAMA_URL` at the host's existing tailnet Ollama listener. Do not change Conduit's routes or inference configuration. Tailscale Serve can publish Lantern on an unused HTTPS port, leaving Conduit's port 443 untouched.

Local build input `Clients/Lantern.Unity/Assets/StreamingAssets/CompanionServer.json` contains `url` and `pairingCode`. It is ignored by Git. Pairing is limited to four devices during the first 30 minutes after server startup. Rotate the bootstrap code before a new pairing window. Device bearer tokens are stored hashed on the server and in iOS Keychain on the device. The paired token survives reinstall; ordinary reconnect does not need the bootstrap code.

## Conversation contract

Authenticated WebSocket `/v1/companion`: client sends `world`, then `listen` and base64 mono PCM16 at 16 kHz in `audio` frames. Silence ends a turn, Whisper emits `transcript`, and the game handles local navigation commands before sending `reply`. `reply` includes an increasing request ID and world revision. The service streams `text` and complete sentence WAVs in `audio`, followed by `done`. `cancel`, a changed adventure/progression revision, disconnect or timeout cancel pending inference. `speak` uses Piper for authored game narration. `forget` clears the current adventure's server dialogue.

Listening is automatic between conversational turns, with half-duplex microphone suppression during reply playback. Tapping the microphone can interrupt. This is not simultaneous full-duplex speech. The native on-device companion remains available when the server is unavailable.

The authoritative snapshot includes current region, objective, named inventory, earned achievements, authored landmarks, exact route guidance and recent journal/events. Locked entities are excluded from model context. Only the game can move the player or change progress; generated dialogue has no action-execution authority.

## Verification

`go test -race ./...` checks the audio/reply path with fake engines, memory isolation, authorization, cancellation and stale-world rejection. `go run ./cmd/probe` exercises live engines using a synthetic authored utterance and a follow-up question. It requires the same environment as the service and optionally `LANTERN_PROBE_URL`, `LANTERN_PROBE_TOKEN_FILE` and `LANTERN_PROBE_AUDIO_FILE`. Never confuse this synthetic check with a physical microphone conversation.

`/healthz` is process liveness. Authenticated `/v1/ready` checks all three inference endpoints. The deployment needs a reachable tailnet connection on each iPhone/iPad.
