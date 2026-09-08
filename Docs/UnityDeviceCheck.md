# Orchard / family-server verification — 2026-09-07

- Unity Editor: the full **21-activity** playthrough passed after correcting the Orchard entrance camera. It exercised navigation, visible world taps, Luma dialogue, moon-harp chimes, collecting the moon seed and restoring the nest. Screenshots were inspected from the actual renderer.
- Local C#: all **20** core checks passed. Go's race/integration checks passed, including a long pre-speech pause, authentication, memory isolation, cancellation and stale world revisions.
- Server: source pushed to GitHub, pulled in `/home/suruat/Projects/Aspire`, and the separate `lantern-companion` Docker service deployed using the existing rootless Docker installation. Existing Whisper was restarted; Piper and Conduit's port 443 route retained. Ollama uses the installed `gemma4:12b` on RTX 3090.
- Live synthetic pipeline: Piper generated an authored question, Whisper transcribed it, the model answered using the Orchard objective, and streamed Piper WAVs arrived with a contextual follow-up. After matching warm-up to the conversation context, the final run transcribed in **0.18 s**, with first audio **0.70 s** later and follow-up audio in **0.60 s**. No physical microphone input was used for this probe.
- Unity client against the private HTTPS/WebSocket endpoint: an authored open-ended question returned in **2.23 s**, three Piper sentences played to completion, and cancelling the next question prevented a stale reply. This was the Editor client, not a phone playback result.
- Signed iOS build **0.1.0 (9)** compiled and installed on Orange iPhone after one interrupted wireless attempt. The normal save remained **byte-identical** after installation. Launch was rejected by iOS because the phone was locked. The iPad was unavailable to CoreDevice.
- Final build **0.1.0 (10)** passed Unity export, native Xcode build and strict signature verification, and installed successfully on Orange. CoreDevice readback confirms bundle version 10. It includes the corrected development probe, accurate song activity context and clearer offline settings wording. The iPad remained unavailable on the final retry.

Evidence: `.artifacts/unity/expansion-editor-build9-pass2.log`, `server-voice-probe-warmup.log`, `server-editor-build9.log`, `iphone-install-build9-retry.json`, `iphone-server-build9.log`, and before/after vault copies. Local artifact logs are excluded from Git. The initial Editor server probe accidentally chose a deterministic local-command phrase; the corrected open-ended phrase passed. This test correction did not reveal a speech transport failure.

Remaining physical acceptance: unlock the phone, connect Tailscale, verify live microphone permission/capture, speech recognition, Piper playback, interruption, echo behavior and comfortable pacing. Install/check the iPad when reachable. Automated handler tests do not substitute for the child's actual touch/voice experience.

## Prior device milestones

### Lantern Meadow device check

Use **Lantern Unity**, bundle `com.bolenton.Lantern.UnitySlice`. The current adventure is a vertical slice. Speech supports local guidance commands; open-ended conversational AI is not connected yet.

## Touch and adventure

1. Begin an adventure in landscape. Touch any clear part of the scene, slide gently, then lift. The control appears under the finger and the explorer walks in the drag direction. Lifting must stop immediately.
2. Repeat from several positions and with a second finger on the screen. The second finger must not move the joystick origin or release the first finger. The control should disappear after release.
3. Tap Ember. If necessary, the explorer walks closer. Tap again to say hello and choose a reply. Ember then follows beside the explorer.
4. Tap the oak, or use the small compass icon for guided travel. Touch the scene or pause to stop guided travel. Tap the oak nearby to play its song. Notes have no time limit; an incorrect note invites a gentle retry.
5. Play the marked touch chimes in order. The round arrow repeats the song; there is no time limit and wrong notes retain correct progress. Tap the floating acorn and confirm the next chapter begins.
6. Visit the brass river bell, play its song, cross the bridge through the sunflower arch and visit the tall lantern flower. Ember should cross single-file and leave the current destination visible. Neither character should pass through the raised planting border, benches or nearby tree trunks. The camera should move clear of the arch.
7. Wake the flower with its song, collect the floating garden star, return over the bridge to the oak, and choose a wish for the shared light. Confirm the garden grows and warms, the wish saves, and Keep exploring returns to movement.
8. Restart a save completed in build 4 and verify it continues into the river/garden chapter without repeating the oak quest. Restart a fully completed new adventure and keep exploring.
9. Use Pause → Comfort settings → Show movement control. The control stays visible while idle, and a new touch still places it at the finger. Toggle it off again. Captions are independently optional.

10. Use Pause → Comfort settings → Travel pace. Comfortable is 2.8 m/s walking and 3.22 m/s guided travel. Brisk is 3.5/4.025 m/s; Gentle is 1.85/2.1275 m/s. Confirm the choice survives a restart and lifting a finger still stops immediately.

## Visibility and accessibility

- Gameplay must not show a permanent text-button bar. The three icons are Pause, guided travel and voice.
- The explorer, Ember, path, oak, brass bell and lantern flower must remain easy to distinguish. Tap the visible flower head, star and oak door; their full shapes are interactive, not only a small ground point. Check both landscape orientations and the camera cutout/home indicator.
- Check all contrast themes. Light/dark text themes preserve original world materials; yellow/black reduces scenery detail while preserving character faces.
- Turn captions on and off. Change word size in the menus and verify scrolling and back navigation. Full narration remains available through Pause → Read Ember's words.
- With VoiceOver, verify the icon labels, guidance, dialogue choices, song and menu focus scrolling. Pause → Interact here is the screen-reader alternative to tapping a world object.

## New audio and speech

- Listen for the new piano/strings score, real bird and river ambience, grass footsteps and recorded bell cues. No previous placeholder loop or old music should play.
- Use the microphone icon and say help, where is the oak, guide me, or stop. Narration must remain clear over the automatically lowered world audio.
- Deny microphone permission and verify a readable/spoken recovery path; movement and world interactions remain usable.
- With headphones, verify river and oak/acorn sounds follow their correct locations. Check head tracking and Center headphone sounds where supported.
- Background the app while walking, return, and confirm it resumes stopped.

Record device, OS, build, contrast/caption preferences, VoiceOver/headphone status and any failures. A successful build or automated pointer check does not establish comfort for the intended child. Measure frame times and thermal behavior in an optimized build before treating 60 fps as achieved.

## Automated expansion check

Use `LANTERN_VERIFY_EXPANSION=1` and `LANTERN_START_ADVENTURE=1` in a development build. The check starts a separate verification save, walks all 13 activities, taps world-object bounds through the touch handlers, plays the chime UI, traverses the bridge both ways and returns to free exploration. It must end with `Lantern playthrough: PASS`. The player’s regular `vault.json` is not used for this run. Restore a normal launch afterward.


## Conversation phase — build 8

1. Tap the microphone or Ember and allow microphone/speech permission if prompted. The microphone ring indicates activity; it does not add a text bar.
2. Ask “Tell me a little story,” then a follow-up about that story. In Comfort settings → Ember's voice and conversation, verify the device reports whether on-device generation is ready.
3. Ask “Take me to the tree,” “Where is the river bell?” and “Stop.” These run through local route checks. An unknown destination such as “Take me to the moon” must leave the player stationary.
4. During listening/thinking, tap the microphone again, start dragging to walk, or pause. An old answer must not resume speech or movement. Background the app and return; the prior conversation window must be gone.
5. Select built-in conversation only and request a story/joke. Switch back to enable on-device conversation; the choice survives a restart. Try Forget this conversation.
6. With VoiceOver, verify the microphone's listening/thinking/speaking labels and the accessibility of the conversation options. Generated reply latency and recognition pauses need evaluation with the intended player.

The automated model check on the iPad supplied an authored text prompt through the real controller/native bridge. It generated a reply in 5.97 seconds and passed cancellation, but microphone recognition, physical fingers and subjective listening comfort remain manual checks.
