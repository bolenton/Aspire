# Ember conversation — family server

Ember uses the family's Whisper, Ollama and Piper installation on Epyst-intel. The separate Dockerized Lantern service is published privately at `https://epyst-intel.story-tarpon.ts.net:8443`. Conduit retains its existing port 443 route. Devices need Tailscale access; the game and native voice remain usable when the server is unavailable.

## Game experience

Tap the microphone to start a conversation. Listening ends after a natural pause, and starts again after Ember finishes replying. Tap again to interrupt/end the conversation. The microphone is suppressed during playback to prevent Ember hearing its own answer; this is automatic turn-taking, not simultaneous full-duplex audio. Movement, pause, backgrounding and changing activities can stop a conversation. Listening, thinking and speaking have distinct small icon states and Ember head/ear/jaw animation. Captions and a visible joystick remain optional.

Local commands such as “guide me,” “take me to Luma,” “which way,” and “stop” stay deterministic. The model can explain, imagine little stories, remember dialogue, and react to progress. It cannot execute movement, change inventory, unlock content or award progress.

## Maintainable boundaries

- `Lantern.Core/Companion/AdventureWorld` builds the authoritative scene/region/objective snapshot, known landmarks, exact route guidance, inventory, earned achievements and recent game journal/events. It excludes the child-name setting and full save vault.
- `CompanionConnection` owns authenticated WebSocket transport, pairing, reconnect and revision-tagged requests. iOS credentials live in Keychain. Local bootstrap configuration is excluded from Git.
- `CompanionVoice` coordinates native microphone capture, sentence WAV playback, cancellation and the on-device fallback. `SpeechPlayback` owns PCM decoding and mouth-animation amplitude.
- `ServerConversation` implements the existing core provider interface. `CompanionCommands` owns all game actions. Apple Foundation Models remain the optional offline provider on supported devices.
- `Services/Lantern.Companion` separates the protocol, world/prompt contract, inference adapters and SQLite storage. Whisper receives 16 kHz mono PCM wrapped in WAV. Ollama streams text; Piper produces one WAV per sentence as generation continues.

The server keeps the latest 24 dialogue messages per device/adventure and sends the latest 12 to the model. Saved game journal entries supply longer-term adventure context. Parent settings can forget the server conversation without resetting game progress. Microphone audio is transient; normal application logs contain no player transcripts. Generated dialogue is constrained by an authored child-friendly persona and current game facts, but remains generated content requiring parent playtesting.

## Verification and operating guide

The server README documents deployment, pairing, protocol and the synthetic live probe. Unit integration checks cover authorization, speech flow, memory isolation, cancellation and stale-world rejection. The real-server probe uses an authored synthetic utterance, not a person's microphone recording. Initial measurements with `gemma4:12b` on the server's RTX 3090: first sentence after a cold model load 11.16 s, warm follow-up 0.48 s; both answers correctly referenced the Orchard objective, Luma and the fireflies. After correcting startup warm-up to use the same conversation context size, the first spoken sentence arrived in 0.65 s and the follow-up in 0.58 s (0.90/0.84 s for complete streamed replies). These timings start after transcription; real microphone capture includes the spoken utterance and silence detection.

Development-only `LANTERN_VERIFY_SERVER=1` exercises device authentication, an authored contextual question, streamed Piper playback completion and cancellation. `LANTERN_VERIFY_CONVERSATION=1` remains the separate Apple provider probe. Neither is a physical microphone acceptance test. Actual spoken input, room echo, interruption and the child's comfort are separate acceptance checks.

See [server deployment](../Services/Lantern.Companion/README.md) and [device evidence](UnityDeviceCheck.md).
