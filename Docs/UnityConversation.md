# Ember conversation — family server

Ember uses the family's Whisper, Ollama and Piper installation on Epyst-intel. The separate Dockerized Lantern service is published privately at `https://epyst-intel.story-tarpon.ts.net:8443`. Conduit retains its existing port 443 route. Devices need Tailscale access; the game and native voice remain usable when the server is unavailable.

## Game experience

Tap the microphone once to turn voice mode on; it stays on until the player taps it again or says “turn off voice mode.” A large blue orb remains visible across gameplay and menus, with a soft breathing halo, sound-reactive bars for listening/speaking and orbiting dots while preparing an answer. VoiceOver announces the actual state. Listening is shown only after native capture is ready. Captions and a visible joystick remain optional.

A natural pause submits each utterance, and listening resumes automatically after Ember finishes. Walking, stopping movement and changing activities preserve voice mode. Tapping Ember during a reply interrupts him and resumes listening. Capture is gated during narration and chime playback so the game does not transcribe itself; this remains automatic turn-taking, not simultaneous full-duplex audio. Backgrounding suspends capture and stops movement; returning resumes the enabled mode. Explicitly switching voice mode off closes the native microphone engine.

Local commands such as “guide me,” “take me to Luma,” “which way,” and “stop” stay deterministic. The model can explain, imagine little stories, remember dialogue, and react to progress. It cannot execute movement, change inventory, unlock content or award progress.

## Maintainable boundaries

- `Lantern.Core/Companion/AdventureWorld` builds the authoritative scene/region/objective snapshot, known landmarks, exact route guidance, inventory, earned achievements and recent game journal/events. It excludes the child-name setting and full save vault.
- `CompanionConnection` owns authenticated WebSocket transport, pairing, reconnect and revision-tagged requests. iOS credentials live in Keychain. Local bootstrap configuration is excluded from Git.
- `CompanionVoice` coordinates native microphone capture, sentence WAV playback, cancellation and the on-device fallback. `SpeechPlayback` owns background WAV decoding, ordered playback and mouth-animation amplitude. The native microphone retains one warm engine across turns, with session setup/teardown on a serial background queue. WebSocket receive/parsing runs off the Unity thread; Unity uploads at most one decoded sentence clip per frame. Unchanged accessibility labels and frames are not sent repeatedly to native APIs.
- `ServerConversation` implements the existing core provider interface. `CompanionCommands` owns all game actions. Apple Foundation Models remain the optional offline provider on supported devices.
- `Services/Lantern.Companion` separates the protocol, world/prompt contract, inference adapters and SQLite storage. Whisper receives 16 kHz mono PCM wrapped in WAV. Ollama streams text; Piper produces one WAV per sentence as generation continues.

The server keeps the latest 24 dialogue messages per device/adventure and sends the latest 12 to the model. Saved game journal entries supply longer-term adventure context. Parent settings can forget the server conversation without resetting game progress. Microphone audio is transient; normal application logs contain no player transcripts. Generated dialogue is constrained by an authored child-friendly persona and current game facts, but remains generated content requiring parent playtesting.

## Verification and operating guide

The server README documents deployment, pairing, protocol and the synthetic live probe. Unit integration checks cover authorization, speech flow, memory isolation, cancellation and stale-world rejection. The real-server probe uses an authored synthetic utterance, not a person's microphone recording. Initial measurements with `gemma4:12b` on the server's RTX 3090: first sentence after a cold model load 11.16 s, warm follow-up 0.48 s; both answers correctly referenced the Orchard objective, Luma and the fireflies. After correcting startup warm-up to use the same conversation context size, the first spoken sentence arrived in 0.65 s and the follow-up in 0.58 s (0.90/0.84 s for complete streamed replies). These timings start after transcription; real microphone capture includes the spoken utterance and silence detection.

Development-only `LANTERN_VERIFY_SERVER=1` exercises device authentication, an authored contextual question, streamed Piper playback completion and cancellation. `LANTERN_VERIFY_CONVERSATION=1` remains the separate Apple provider probe. Neither is a physical microphone acceptance test. Actual spoken input, room echo, interruption and the child's comfort are separate acceptance checks.

Development-only `LANTERN_VERIFY_VOICE_MODE=1` uses a separate save to exercise actual native PCM capture, movement with voice mode active, reply-to-listening continuation and explicit-off capture shutdown. It reports short per-phase main-thread frame samples without logging recorded words. Recognition accuracy and room echo still need a spoken parent check.

See [server deployment](../Services/Lantern.Companion/README.md) and [device evidence](UnityDeviceCheck.md).
