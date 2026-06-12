# Lantern Polish Pass — Implementation Document

This is the canonical spec for the post-playtest polish pass. It is written so that
**independent agents can each execute one workstream** with no other context. Read
"Ground rules" and your workstream section fully before writing code; respect the
sequencing table at the end (some workstreams edit the same files and must be
serialized).

## Why this pass exists

Her first playtest surfaced five issues, each traced to a root cause:

| # | Complaint | Root cause |
|---|-----------|-----------|
| 1 | Tapping "Walk" over and over to move | One tap = one 1.5 u step (`GameViewModel.walk()`); ±45° turn taps; three small fixed buttons she must find by feel; no continuous input anywhere |
| 2 | World hard to recognize (low vision) | Emissive-only procedural voxels, no bloom, no outlines; interactables differ from scenery only by glow intensity |
| 3 | Unclear what to do next | Hints exist but the game never takes initiative (no idle prompts); the quest beacon is **visual-only** in an audio-first game |
| 4 | Voice clarity ceiling | AVSpeechSynthesizer only; no neural-TTS option |
| 5 | Forest ambience drowns the voice at start | Ambience loops are PHASE **spatial sources at the origin — exactly where she spawns** (gains 0.6 + 0.45 stacked, `nearRadius: 1`); no ducking when the narrator speaks (narration is a separate audio path) |

Five workstreams: **WS1 controls**, **WS2 audio mix**, **WS3 premium voice**,
**WS4 graphics**, **WS5 guidance**.

## Ground rules (every agent)

- **Build system**: iOS 18.0 target, **XcodeGen** project. Any new file under `App/`
  requires `xcodegen generate` before `xcodebuild`. Build check:
  `xcodegen generate && xcodebuild -project Lantern.xcodeproj -scheme Lantern -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build`
- **Engine package**: platform-independent logic goes in `Packages/StoryEngine`
  (Linux CI; `swift test --package-path Packages/StoryEngine`; Foundation-only
  networking via the `#if canImport(FoundationNetworking)` shim — see
  `Packages/StoryEngine/Sources/StoryEngine/Companion/OpenAICompatibleBrain.swift`
  for the established pattern). iOS frameworks (PHASE, RealityKit, AVFoundation,
  UIKit) stay in `App/`.
- **Design pillars are sacred**:
  - *Offline-first*: every cloud feature is a silent upgrade with a seamless local
    fallback. No key configured → byte-identical behavior to today.
  - *Audio-first*: sound carries the meaning; visuals confirm. Every haptic pairs
    with an earcon (iPads have **no Taptic Engine** — verified).
  - *No punishment*: no failure states, no nagging, generous cooldowns.
  - *Deterministic rules decide help* (DifficultyDirector); AI may only phrase it.
- **⚠️ Save-file integrity (highest-severity risk in this pass)**: `PlayerVault.load`
  silently returns a **fresh vault** if decoding fails
  (`Packages/StoryEngine/Sources/StoryEngine/SaveSlot.swift:101–106`) — that wipes her
  calibration and saves. Every new persisted field on `CalibrationProfile` /
  `PlayerVault` MUST be decoded via a custom `init(from:)` using `decodeIfPresent`
  with a default, and C1 adds an old-fixture decode test that locks this in.
- **Audio assets**: `SoundBank`/`SpatialAudioEngine` skip missing files gracefully —
  code may land before assets. Every new cue gets a row in `Assets/Audio/MANIFEST.md`
  and a placeholder synthesis function in `Tools/generate_placeholder_audio.py`.

## Verified API facts (planning-time research — trust these, with the noted hedges)

- **PHASE runtime gain**: `PHASEMixer.gain` is **read-only at runtime**. The only
  sanctioned path is a gain metaparameter: set
  `mixer.gainMetaParameterDefinition = PHASENumberMetaParameterDefinition(...)` at
  creation, then after `event.start()` retrieve
  `event.metaParameters[id] as? PHASENumberMetaParameter` and call
  `fade(value:duration:)` / set `.value`. Replace-vs-multiply semantics vs
  `mixer.gain` are undocumented → leave `mixer.gain` at 1.0 and drive the absolute
  gain entirely through the metaparameter (correct under either semantics).
  `PHASEChannelMixerDefinition` = non-spatial, routes straight to output (use for the
  ambience bed). `PHASEAmbientMixerDefinition` exists too (non-spatial but
  orientation-aware) — not needed here.
- **RealityKit post-processing**: `ARView.renderCallbacks.postProcess` (iOS 15+);
  `PostProcessContext` provides `sourceColorTexture`, `sourceDepthTexture`,
  `targetColorTexture`, `commandBuffer`, `device`. Apple's sample "Implementing
  special rendering effects with RealityKit postprocessing" shows the MPS bloom
  recipe. Two hard rules: once registered, the callback **must write
  `targetColorTexture` every frame** or nothing renders; pixel formats vary per
  device — always read them from the context. **nonAR-mode support is not documented
  either way** → bloom is feature-flagged and the first hour of that task verifies it
  on device.
- **ElevenLabs**: `POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}/with-timestamps`,
  header `xi-api-key`, body `{text, model_id, output_format: "mp3_44100_128",
  voice_settings: {speed}}` → `{audio_base64, alignment: {characters[],
  character_start_times_seconds[], character_end_times_seconds[]}}`. Voice list:
  `GET https://api.elevenlabs.io/v2/voices?page_size=100`. Default model
  **`eleven_flash_v2_5`** (fast/cheap; parent-overridable string).
- **OpenAI-compatible speech**: `POST {base}/v1/audio/speech`, Bearer auth,
  `{model, input, voice, response_format: "mp3"}` → raw audio bytes. **No
  timestamps** (estimate word timings instead). Default model `gpt-4o-mini-tts`;
  built-in voices `alloy, ash, ballad, coral, echo, fable, nova, onyx, sage,
  shimmer, verse`; local servers (LocalAI, AllTalk…) speak the same shape and may
  accept arbitrary voice names → settings allow free-text voice entry.
- **Haptics**: no iPad has a Taptic Engine; iPhone 8+ does. Gate via
  `CHHapticEngine.capabilitiesForHardware().supportsHaptics`;
  `UIImpactFeedbackGenerator` is sufficient (keep `prepare()`d during movement);
  no CoreHaptics pattern authoring this pass.

---

# WS1 — Controls: touch-anywhere joystick + sound autopilot

**Goal**: replace tap-tap-tap movement with: hold a thumb anywhere over the world →
that point becomes a virtual stick (push up = walk continuously, slide sideways =
smooth steering, release = stop). Double-tap anywhere = autopilot toward the current
quest target. The three existing buttons remain as fallback and the VoiceOver path.

**Architectural decision**: the game tick lives in `GameViewModel` via
**CADisplayLink** — NOT in `WorldView.Coordinator.tick()` (that render callback is
presentation-only interpolation, can be torn down by SwiftUI, and isn't
MainActor-guaranteed). Throttling, because `pose` is `@Published` and 120 Hz
publishing would re-evaluate `GameView.body` every frame:
- integrate movement every display frame into a private working pose;
- publish `pose` at ~20 Hz while moving + once on stop (WorldView's existing
  `deltaTime * 6.0` blend smooths between published poses);
- `pushListener()` at the same 20 Hz;
- `checkArrival()` + nearby-entity scan + WS5 checks at 5 Hz.

### New files

**`App/Game/GameLoop.swift`**
```swift
/// CADisplayLink wrapper driving the per-frame game simulation.
@MainActor final class GameLoop {
    var onTick: ((TimeInterval) -> Void)?   // deltaTime since last tick
    func start(); func stop()
    private(set) var isRunning: Bool
}
```

**`App/Game/MovementController.swift`**
```swift
/// Continuous-movement state machine. Emits events; never plays sounds itself.
@MainActor final class MovementController {
    enum Mode: Equatable { case idle, joystick, autopilot(targetEntityID: String) }
    private(set) var mode: Mode

    // Tuning constants: deadzone 0.15 (normalized), maxWalkSpeed 3.0 u/s
    // (quadratic response near center for fine control), backward at half speed
    // on pull-down, maxTurnRate 120°/s joystick / 180°/s autopilot-align,
    // autopilotSpeed 2.2 u/s, stepStride 1.5 u.

    func setJoystick(vector: CGVector?)        // nil = released → idle
    func startAutopilot(toward targetID: String, position: Vec3)
    func cancelAutopilot()

    enum MovementEvent {
        case step            // every 1.5 u traveled → footstep + haptic
        case turnSnap        // heading crossed a 45° sector boundary (see note)
        case boundaryBump    // clamped against ±40 while pushing (2 s cooldown)
        case autopilotArrived
    }
    func integrate(pose: PlayerPose, deltaTime: TimeInterval)
        -> (pose: PlayerPose, events: [MovementEvent])
}
```
Steering is **smooth** (no 45° snapping), but `turnSnap` fires when the heading
crosses an 8-sector boundary so a tick/haptic preserves her existing 8-direction
mental model. Autopilot: rotate toward bearing first (until within 10°), then walk a
straight line (the world has no obstacles), clamp to ±40; arrival = within
`arrivalDistance` (2.5) of target → `autopilotArrived`.

**`App/Views/TouchControlView.swift`**
```swift
/// Transparent full-world-area touch layer: hold = joystick (touch point becomes
/// stick center), double-tap = autopilot. Single-touch only.
struct TouchControlView: UIViewRepresentable {
    var enabled: Bool                          // false while overlays open / VO on
    var onStickChanged: (CGVector?) -> Void    // normalized; nil on release
    var onDoubleTap: () -> Void
    var onAnyTouch: () -> Void                 // cancels autopilot, resets idle timer
}
```
Implementation rules (custom `touchesBegan/Moved/Ended/Cancelled` on a UIView —
**no gesture recognizers**, so nothing delays or fights the window-level two-finger
freeze recognizer, which uses `cancelsTouchesInView = false`, `App/Views/Components.swift:111`):
- Track ONE touch. If a second touch lands (freeze gesture incoming), call
  `onStickChanged(nil)` immediately and ignore everything until all touches end.
- Lift within 0.25 s having moved < 12 pt = "tap"; two taps within 0.35 s and
  60 pt = `onDoubleTap`.
- A held/moved touch becomes the stick: center = initial point,
  vector = (current − center) / 110 pt radius, clamped to unit length, deadzone 0.15.
  Engage earcon + soft haptic on stick activation.
- VoiceOver: observe `UIAccessibility.isVoiceOverRunning` (+
  `voiceOverStatusDidChangeNotification`); when running, set
  `isUserInteractionEnabled = false` — the three buttons remain the VO movement path.

**`App/Game/HapticsDirector.swift`**
```swift
/// Thin haptics facade. No-ops where unsupported (all iPads) — checked once via
/// CHHapticEngine.capabilitiesForHardware().supportsHaptics.
@MainActor final class HapticsDirector {
    static let shared = HapticsDirector()
    func stepTick()         // UIImpactFeedbackGenerator(.light), kept prepared while moving
    func turnSnap()         // .rigid
    func boundaryBump()     // .heavy
    func interactionRange() // soft success-style
    func engage()           // .soft — stick engaged
    func setActive(_ active: Bool)  // prepare()/release around movement
}
```

### Modified files

**`App/Game/GameViewModel.swift`**
- New stored: `let loop = GameLoop()`, `let movement = MovementController()`,
  `@Published private(set) var isAutopiloting = false`,
  `@Published var stickVisual: (center: CGPoint, thumb: CGPoint)?`,
  `private var lastNearbyID: String?`, `var lastInteractionAt = Date()` (WS5 reads).
- `begin()`: `loop.onTick = { [weak self] dt in self?.gameTick(dt) }; loop.start()`.
  `end()`: `loop.stop()`.
- New `private func gameTick(_ dt: TimeInterval)`: returns immediately when frozen
  or an overlay is open (`currentDialogue != nil || activeSongSpell != nil`);
  integrates movement; dispatches `MovementEvent`s → biome-mapped footstep SFX +
  `HapticsDirector`; runs the 5 Hz sub-tick: `checkArrival()` (today it is only
  called inside `walk()` — make it callable from the tick), nearby-entity
  transition earcons (WS5), idle-nudge check (WS5), compass facing tick (WS5).
- New input API:
  - `func stickChanged(_ vector: CGVector?)` — cancels autopilot if active,
    forwards to `movement`, updates `lastInteractionAt`.
  - `func requestAutopilot()` — guard `currentStep` and resolve the target entity
    position from `resolvedEntities`; companion announces: *"Hold on tight — I'll
    lead the way to the ⟨target name⟩! Touch the screen any time to stop."* +
    `earcon_autopilot_start.wav`; `movement.startAutopilot(...)`. If there is no
    current target: a friendly line ("We can go anywhere you like — there's
    nothing we have to find right now."), no autopilot.
  - `func cancelAutopilot(announce: Bool)` — touch-cancel plays a soft earcon only
    (touch means she wants control; no speech).
- Autopilot arrival: stop movement, then the existing `checkArrival()` resolves
  reach/collect steps; for talk/song targets the context button + WS5 near-chime
  take over.
- `walk()` / `turn(degrees:)` stay for the fallback buttons but route their effects
  through the same event handling (footstep/turn earcons) for consistency.
- Freeze integration: `AppModel.freezeBegan()` (`App/Models/AppModel.swift:109`)
  additionally calls `activeGame?.movementFreeze()` — new method: release stick,
  cancel autopilot, pause `loop`; `freezeEnded()` resumes.

**`App/Views/GameView.swift`**
- Insert `TouchControlView` in the ZStack directly above `WorldView` (line 23) and
  below the UI `VStack` — SwiftUI controls rendered later sit above it and receive
  their touches first. `enabled: model.currentDialogue == nil &&
  model.activeSongSpell == nil && !listener.isListening && !frozen`.
- Stick visual: 110 pt `Circle().stroke` ring + filled thumb dot in
  `theme.highlight`, opacity ~0.85, driven by `model.stickVisual` — vision confirms,
  sound is primary.
- While `model.isAutopiloting`: a non-interactive "Walking with ⟨companion⟩… touch
  to stop" pill (GiantButtonStyle visuals).
- The three buttons (lines 167–177) stay exactly as today.

### Content changes
- New cues → `Assets/Audio/MANIFEST.md` + `Tools/generate_placeholder_audio.py`:
  `footstep_grass.wav`, `footstep_grass_b.wav`, `footstep_stone.wav`,
  `footstep_stone_b.wav`, `footstep_cave.wav`, `footstep_cave_b.wav` (alternate
  a/b per step to avoid machine-gun feel; filtered noise bursts),
  `earcon_autopilot_start.wav`, `earcon_autopilot_stop.wav`, `earcon_boundary.wav`,
  `earcon_stick_engage.wav`. Biome → footstep mapping: forest→grass, cave→cave,
  castle→stone, default grass.
- `CalibrationProfile.touchControlsEnabled: Bool = true` (parent can disable the
  layer). **Follow the save-migration rule** (Ground rules; consolidated in C1).

### Acceptance
Hold-push walks smoothly; slide steers; release stops dead; footstep + tick cadence
≈ one per 1.5 u; two-finger freeze works *while* the stick is held; double-tap
auto-walks to the quest target and the arrival celebration fires; buttons still
work; VoiceOver on → touch layer inert, buttons navigate.

---

# WS2 — Audio mix: ambience bed + ducking (the loud-forest fix)

**Goal**: ambience no longer overpowers the voice — structurally (no more spatial
source at the spawn point), by authored level (lower volumes), by entrance (2.5 s
fade-in), and dynamically (duck under voice/listening).

### `App/Audio/SpatialAudioEngine.swift`

**Runtime gain wiring** in `addLoopingSource` (line 52):
```swift
let baseGain = Double(max(0, min(1, Float(sound.volume) * worldVolume)))
let gainDef = PHASENumberMetaParameterDefinition(
    value: baseGain, minimum: 0.0, maximum: 2.0, identifier: "\(id)_gain")
mixer.gainMetaParameterDefinition = gainDef     // mixer.gain stays 1.0 (see hedge)
// ... after event.start():
gainParams[id] = event.metaParameters["\(id)_gain"] as? PHASENumberMetaParameter
baseGains[id] = baseGain
```
This replaces the current `mixer.gain = ...` line (line 70). Clean both dictionaries
up in `removeSource`.

**New API**:
```swift
enum SourceCategory { case ambience, entity }   // ambience = id prefix "ambience_"
func setGroupGain(category: SourceCategory, multiplier: Double, fade: TimeInterval)
// → for each matching id: gainParams[id]?.fade(value: baseGains[id]! * multiplier,
//                                              duration: fade)
func setSourceGain(id: String, multiplier: Double, fade: TimeInterval)
```
Store `duckFactors: [SourceCategory: Double]` so sources created **mid-duck** (scene
entry during the opening narration) start at the ducked level — this delivers
"ambience starts ducked under the opening line" for free.

**Ambience becomes a non-spatial bed**: in `loadScene` (line 40), route ambience
entries through a new `addAmbienceSource(id:sound:)` that uses
`PHASEChannelMixerDefinition` — no spatial pipeline, no distance model, no position.
This structurally kills the source-at-spawn-point bug. The ambience gain
metaparameter starts at **0.0**, then immediately
`fade(value: baseGain * duckFactor(.ambience), duration: 2.5)` — the fade-in.
Entity loops keep instant base gain (they are positional navigation information).

**First task — 5-minute on-device check**: (a) the metaparameter default value
actually applies as gain at event start; (b) `fade(value:duration:)` is audible
mid-loop. **Fallback if PHASE misbehaves** (not expected): move only the ambience
bed to AVAudioPlayer in SoundBank (`setVolume(_:fadeDuration:)`), leave entity loops
un-ducked. **Never** rebuild sources to change gain — mid-loop pops are unacceptable.

### New file `App/Audio/AudioMixCoordinator.swift`
```swift
/// Single owner of duck state. Deterministic: voice always wins.
@MainActor final class AudioMixCoordinator {
    // Duck targets: ambience ×0.35, entity loops ×0.40, music ×0.5.
    // Attack 0.25 s, release 1.0 s.
    func attach(narrator: Narrator, audio: SpatialAudioEngine) // sinks narrator.$isSpeaking
    func setListening(_ listening: Bool)                       // pushed from GameView
    private(set) var isDucked: Bool                            // WS5 reads this
}
```
Owned by `GameViewModel` (`let audioMix = AudioMixCoordinator()`), attached in
`begin()`. `GameView` adds `.onChange(of: listener.isListening) {
model.audioMix.setListening($1) }`. (Note: `SpeechListener`'s `.duckOthers` session
option only ducks *other apps* — in-app ducking is genuinely needed.)

### `App/Audio/SoundBank.swift`
Track `musicBaseVolume` (set in `playMusic`); add
`func setMusicDuck(_ factor: Float, fade: TimeInterval)` →
`musicPlayer?.setVolume(musicBaseVolume * factor, fadeDuration: fade)`.

### `StoryPacks/ForestJourney/pack.json` — authored ambience volumes
| Scene | Asset | Old → New |
|---|---|---|
| Fox Hollow | wind_leaves_loop | 0.6 → **0.35** |
| Fox Hollow | crickets_loop | 0.45 → **0.25** |
| Echo Chamber | cave_hum_loop | 0.5 → 0.3 |
| Echo Chamber | cave_drips_loop | 0.45 → 0.25 |
| Lantern Courtyard | castle_wind_loop | 0.5 → 0.3 |
| Lantern Courtyard | banners_flap_loop | 0.4 → 0.25 |

Entity (positional) volumes are untouched — they carry navigation information.

### Acceptance
Scene entry → ambience fades in *under* the opening narration, clearly behind the
voice; tap-to-talk → world drops within ~0.25 s, swells back ~1 s after; collecting
an item still silences its loop; freeze still pauses everything.

---

# WS3 — Premium voice: TTSProvider + ElevenLabs + OpenAI-compatible

**Goal**: optional neural TTS for the companions and narrator, configured behind the
parent gate, with on-disk caching and prefetching. AVSpeech remains the always-on
fallback; the word-by-word reading highlight (literacy loop) keeps working on both
paths.

**Placement**: protocol + providers + timing math in
`Packages/StoryEngine/Sources/StoryEngine/Speech/` (Linux-tested; Foundation-only
networking like `OpenAICompatibleBrain`). Playback, disk cache, Keychain, and the
Narrator refactor are iOS concerns in `App/`.

### StoryEngine new files

**`Speech/TTSProvider.swift`**
```swift
public struct TTSVoice: Codable, Equatable, Sendable, Identifiable {
    public var id: String; public var name: String; public var detail: String?
}
public struct TTSWordTiming: Codable, Equatable, Sendable {
    /// UTF-16 offsets into the synthesized text (maps 1:1 to NSRange).
    public var location: Int; public var length: Int
    public var start: TimeInterval; public var duration: TimeInterval
}
public struct TTSAudio: Sendable {
    public var data: Data
    public var fileExtension: String          // "mp3"
    public var wordTimings: [TTSWordTiming]?  // nil → caller estimates
}
public protocol TTSProvider: Sendable {
    var providerID: String { get }            // cache-key component
    func synthesize(text: String, voiceID: String) async throws -> TTSAudio
    func listVoices() async throws -> [TTSVoice]
}
```

**`Speech/ElevenLabsTTSProvider.swift`** —
`init(apiKey:, modelID: String = "eleven_flash_v2_5", baseURL: URL = api.elevenlabs.io)`.
`synthesize`: with-timestamps endpoint (see Verified API facts); `voice_settings.speed`
mapped from a settable `rate` property (app sets it from `profile.speechRate`,
clamped 0.8…1.2); decode `{audio_base64, alignment}`; map alignment →
`TTSTimingMapper.wordTimings`. `timeoutInterval` 15 s (callers enforce tighter
budgets). Errors include a response-body excerpt — same diagnosability philosophy as
`OpenAICompatibleBrain.directReply`. `listVoices`: `GET /v2/voices?page_size=100`,
`detail` from labels.

**`Speech/OpenAISpeechTTSProvider.swift`** —
`init(baseURL:, apiKey: String?, model: String = "gpt-4o-mini-tts")`. `synthesize`:
`POST {base}/v1/audio/speech` → raw bytes, `wordTimings: nil`. `listVoices`: static
built-in list; the settings UI additionally allows free-text voice names for local
servers.

**`Speech/TTSTimingMapper.swift`** (pure; fully unit-tested)
```swift
public enum TTSTimingMapper {
    /// ElevenLabs character alignment → word timings over the ORIGINAL text.
    /// Defensive: if joined alignment characters ≠ original text → estimate().
    public static func wordTimings(text: String, characters: [String],
                                   starts: [Double], ends: [Double]) -> [TTSWordTiming]
    /// No-timestamp fallback: proportional to word UTF-16 length, per-word floor,
    /// extra weight after sentence punctuation.
    public static func estimate(text: String, totalDuration: TimeInterval) -> [TTSWordTiming]
}
```
Word-boundary rule mirrors `NarrationTextView`'s split-on-space
(`App/Views/Components.swift`) so highlight ranges align exactly with the tappable
word buttons.

### App new files

- **`App/Speech/SpeechCache.swift`** — `Application Support/SpeechCache/`
  (`isExcludedFromBackup = true`; we *want* lines to survive for offline replay,
  Caches/ can be purged). Key = SHA-256 of `"\(providerID)|\(voiceID)|\(model)+\(speedBucket)|\(text)"`
  where `speedBucket = round(speechRate*10)` (speed is baked into ElevenLabs audio).
  Stores `<hash>.mp3` + `<hash>.json` timings. API: synchronous `lookup` (hot path),
  `store`, `totalSize`, `clear`, LRU prune at 200 MB (mtime; touch on read).
- **`App/Speech/KeychainStore.swift`** — ~60-line `kSecClassGenericPassword`
  `get/set/delete`, service `"com.bolenton.lantern"`. TTS keys live here
  (`tts.elevenlabs.key`, `tts.openai.key`); migrate `brain.apiKey` read-through
  (Keychain → UserDefaults fallback → write Keychain + clear default). Non-secret
  prefs stay `@AppStorage`.
- **`App/Speech/SpeechPrefetcher.swift`** — serial, low-priority cache warmer, skips
  hits. On scene entry: scene description, current step intro/celebration/**all**
  hint rungs, quest summary, WS5 nudge/boundary one-liners. On step advance: next
  step's lines. On dialogue open: node line + each choice's next node (one level
  ahead). AI brain replies synthesize on demand (the existing "thinking" cue covers
  latency). `cancelAll()` on scene exit.

### `App/Speech/Narrator.swift` refactor

**The published surface is frozen** — `currentText`, `highlightRange`, `isSpeaking`,
`speak(_:voice:onFinish:)`, `stop()`, `speakWord(_:voice:)`, `profile` — every call
site (GameViewModel ×12, GameView, AppModel, settings, wizard) keeps working
untouched. Internals:

- Injected by AppModel: `var cloudProvider: (any TTSProvider)?`; cache instance.
- `speak()` flow:
  1. Set `currentText`/`isSpeaking` immediately — captions never wait on network.
  2. No provider, or no `cloudVoiceID` on the spec → existing AVSpeech path
     verbatim (**zero-regression guarantee**).
  3. Cache hit → play from disk immediately.
  4. Miss → synthesis task with a **latency budget**: 1.5 s default, 6 s for `ask()`
     replies (new `speak(_:voice:latencyBudget:onFinish:)` overload; default value
     preserves the existing signature). Budget expiry or any error → AVSpeech speaks
     this line; the fetch continues in background to warm the cache. Silent —
     no transition earcon.
- Cloud playback: `AVAudioPlayer(contentsOf: cachedURL)`,
  `volume = spec.volume * profile.narrationVolume`; highlight driven by a 30 Hz
  timer reading `player.currentTime` against `[TTSWordTiming]` (estimated via
  `TTSTimingMapper.estimate(text, player.duration)` when nil) → publishes
  `highlightRange` as `NSRange`; `audioPlayerDidFinishPlaying` mirrors the existing
  AVSpeech delegate bookkeeping (`isSpeaking=false`, fire `onFinish`).
- `stop()` cancels the synthesis task, stops synthesizer + player, invalidates the
  timer.
- `speakWord` stays AVSpeech-only (single words are poor cloud value; literacy loop
  works everywhere).

### Cloud voice mapping

Extend `VoiceSpec` (StoryEngine) with `public var cloudVoiceID: String?` —
synthesized Codable decodes a missing key as nil, so roster JSON is unaffected.
`VoiceDirector.spec(for:)` / `narratorSpec()` populate it from a new UserDefaults
column: `cloudVoiceID(for companionID:)` / `setCloudVoiceID(_:for:)` with keys
`"cloudvoice.<companionID>"` (narrator uses `VoiceDirector.narratorID`). Narrator
reads `spec.cloudVoiceID`. One resolution authority, no signature changes.

### `App/Models/AppModel.swift` + `App/Views/ParentGateView.swift`

- `@AppStorage("tts.provider")` (`system | elevenLabs | openAICompatible`),
  `@AppStorage("tts.elevenlabs.model")`, `@AppStorage("tts.openai.endpoint")`,
  `@AppStorage("tts.openai.model")`; keys in Keychain.
- `func makeTTSProvider() -> (any TTSProvider)?` mirrors `makeBrain()`
  (AppModel.swift:152); installed into `narrator.cloudProvider` at init and when
  settings close.
- `func testVoice() async -> String` mirrors `testBrain()` (AppModel.swift:198):
  direct `synthesize("Hello ⟨childName⟩! This is my real voice.")` + play, **no
  fallback**, surfaces real HTTP errors with hint text ("check the API key", "is a
  voice chosen for this companion?").
- Settings section "Premium voices (optional)", mirroring the brain section:
  explainer ("Works fully offline without this…"), provider segments, SecureFields
  for keys, per-companion + narrator voice `Menu` pickers fed by `listVoices()`
  (fetch on appear when a key exists; refresh button; honest error text; free-text
  voice field for OpenAI-compatible), test button, cache size display + "Clear
  voice cache".

### Acceptance
No key → identical to today (regression-check this FIRST). Key + voices set → the
fox speaks ElevenLabs with the highlight tracking words. Airplane mode mid-quest →
next line falls back to AVSpeech within the budget, no dead air, captions fine.
Cache survives relaunch; clear-cache works. `swift test` passes on the timing
mapper (UTF-16 surrogates, punctuation, mismatched alignment → estimate fallback,
full-coverage invariants) + provider request-encoding golden tests (no live network).

---

# WS4 — Graphics recognizability overhaul (procedural)

**Goal**: everything readable at a glance for low vision — interactables
unmistakable, landmarks recognizable silhouettes, glow that actually glows. No
external art assets. Order matters: batching first (its headroom pays for bloom).

1. **Terrain batching** — `VoxelWorld.terrain()` emits ~729 tile ModelEntities.
   Bucket tiles by color (≤5 buckets — 3 ground variants + hill + path), iterating
   in the **identical `xi/zi` order with the same `SeededRandom` sequence** so
   worlds look exactly as today. Per bucket: one `MeshDescriptor` accumulating
   5-face boxes (skip bottoms) → `MeshResource.generate(from:)` → one ModelEntity
   per bucket with the existing material helper. 729 → ≤5 draw-call entities +
   base plane. Scatter (trees/flowers) stays as-is.
2. **Contrast by construction** (also the no-bloom fallback): ground emissive ×0.6
   in all biomes; interactable body emissive 2.0 → 3.0 in `WorldBuilder.shape`.
3. **Bloom** — new `App/World/PostEffects.swift`:
   ```swift
   /// MPS bloom: threshold → ½-res downsample → gaussian blur → add. ~1–2 ms.
   final class BloomPostProcess {
       init?(device: MTLDevice)          // nil → caller skips registration
       func register(on arView: ARView)  // arView.renderCallbacks.postProcess = ...
       func unregister(from arView: ARView)
   }
   ```
   `MPSImageThresholdToZero` (0.85) → bilinear scale to a cached ½-res texture
   (rebuilt on size change; **pixel formats read from the context, never
   hardcoded**) → `MPSImageGaussianBlur` (sigma 14) → `MPSImageAdd` into
   `targetColorTexture`. If any kernel init fails → don't register (rendering
   untouched); if registered, must write the target every frame (blit-copy
   fallback path). Registered in `WorldView.Coordinator.attach()` behind
   `CalibrationProfile.bloomEnabled = true` (+ auto-off when
   `ProcessInfo.processInfo.isLowPowerModeEnabled`). **Hour one: verify postProcess
   fires in nonAR mode on a real device** (print-once in the callback). If it
   doesn't: drop bloom entirely — contrast + markers carry the workstream.
4. **Billboarded icon markers** — new `App/World/MarkerBuilder.swift`:
   ```swift
   enum MarkerBuilder {
       /// SF Symbol → UIGraphicsImageRenderer 256² chip (white symbol on dark
       /// rounded chip, theme tint ring) → TextureResource → UnlitMaterial on a
       /// 0.9 m plane. Cached per (symbol, tint). Unlit = ignores scene light,
       /// maximum contrast, reads through bloom.
       static func marker(kind: EntityKind, isQuestTarget: Bool,
                          highContrast: Bool) -> ModelEntity
   }
   ```
   Symbols: item `sparkles`, companion/character `bubble.left.fill`, portal
   `arrow.right.circle.fill`, landmark `star.fill`; quest target gets the
   accent-gold chip regardless of kind. Integration: `WorldBuilder.build` gains
   `isQuestTarget`/`highContrast` parameters; `shape()` returns `(entity, topY)`;
   marker child named `"marker"` at `y = topY + 1.1`; **skipped for anonymous
   teases** (they stay mysterious). In `WorldView.Coordinator.tick`: yaw-only
   billboard (`atan2` toward camera, upright — steadier than full look-at) +
   distance scale `clamp(d * 0.085, 0.7, 2.4) * (1 + 0.4 * (glowBoost - 1))` so
   far markers stay legible and support level enlarges them.
5. **Shape library** (`WorldBuilder.swift` + `VoxelWorld.swift`, zero content
   changes): oak tree with 3 angled branches + 3-tier canopy (distinct from
   scatter trees); door with jambs/recessed panel/knob (unmistakably enterable vs
   the open arch); new shapes `"character"` (body, head, **two dark eye boxes** —
   the single biggest recognizability win — stub arms) and `"chest"`; default
   stays the spinning cube. Critters ×1.3 with eyes (fox +4 leg boxes, bunny nose,
   butterfly two-tone wing panels) — `WorldView.tick` animation targeting is
   name-based (`"body"`, `"wing"`) and keeps working.
6. **High-contrast world mode** — thread the contrast theme into `GameViewModel`
   (from `vault.calibration` via `makeGameViewModel`, AppModel.swift:80) →
   `WorldView.sync`/`setScene`/`rebuildEntities`. When `highContrastYellow`:
   ground/sky near-black (0.06 gray, emissive 0.05), interactables forced
   `#FFE000` emissive 3.5, halos + markers white-on-black. Rides the existing
   theme — no new setting.
7. **`Docs/ArtPipeline.md`** — write the future-art-pass doc (design-level, no
   build work):
   - Pipeline: Meshy / Tripo3D / Rodin text-to-3D → GLB → Apple Reality Converter
     (or `usdzconvert`) → USDZ in `Assets/Art/Models/`.
   - Conventions: ≤15 k triangles, ≤2048² textures, 1 unit = 1 m, pivot at
     ground-center, face −Z (RealityKit forward), authored emissive map matching
     the game's glow language.
   - Slotting: `VisualSpec` gains optional `assetName: String?` (decodes missing
     as nil); `WorldBuilder.shape()` tries `ModelEntity.loadModel(named:)` first,
     procedural shape remains the fallback — same graceful-degradation contract as
     audio. The shape key stays the semantic identity.
   - Companions: Meshy/Tripo auto-rig → USDZ with skeletal clips (idle/hop/flap)
     played via `availableAnimations`; the procedural hop remains the fallback.
   - Licensing: record tool/tier/prompt/date per asset in the `ASSETS.md` ledger;
     paid tiers of these services grant commercial use of outputs; AI-generated
     geometry is likely uncopyrightable (US Copyright Office guidance) — the
     ledger discipline is the protection.
   - LOD: not needed at current scale; revisit past ~150 k visible tris.

### Acceptance
60 fps on the target iPad with bloom on (Xcode FPS gauge); markers readable from
spawn across the meadow; `highContrastYellow` world is black-with-yellow
interactables; worlds still deterministic per scene (same look as before batching).

---

# WS5 — Guidance: audio compass, idle nudges, earcons, tutorial

**Goal**: the game takes initiative and the quest target is audible, not just
visible.

### GuidanceMath (StoryEngine, testable)
**`Packages/StoryEngine/Sources/StoryEngine/GuidanceMath.swift`** +
`GuidanceMathTests.swift`:
```swift
public enum GuidanceMath {
    /// Relative bearing in degrees (-180…180, 0 = dead ahead). Same math as
    /// SnapshotBuilder.direction — refactor that to delegate to this
    /// (golden SnapshotTests must stay green).
    public static func relativeBearing(from pose: PlayerPose, to target: Vec3) -> Double
    public static func isFacing(_ bearing: Double, tolerance: Double = 15) -> Bool
    /// Facing-tick interval: 1.6 s at ≥24 u shrinking to 0.35 s at ≤3 u.
    public static func tickInterval(distance: Double) -> TimeInterval
}
```
Tests: wraparound, tolerance edges, interval monotonicity + bounds.

### Audio compass
- On quest-target change — `enterScene()` and `completeCurrentStep()` (after
  `worldRevision += 1`): `audio.removeSource(id: "compass_target")`; if
  `calibration.audioCompassEnabled` and a target exists,
  `audio.addLoopingSource(id: "compass_target", sound: SoundSpec(asset:
  "compass_chime_loop.wav", loops: true, volume: 0.22 * support.audioCueGain,
  nearRadius: 1, farRadius: 60), position: targetPosition)` — a quiet sparse
  spatial chime PHASE pans/attenuates naturally. Ducks as `.entity`.
- Facing tick (5 Hz sub-tick): bearing from **`perceptionPose`** (her ears lead —
  AirPods head yaw included); if `isFacing(bearing)` && `!audioMix.isDucked` &&
  `now - lastFacingTick > tickInterval(distance)` →
  `SoundBank.play("compass_tick.wav", volume: 0.5 * audioCueGain)`. Suppressed
  while autopiloting and during overlays.
- `CalibrationProfile.audioCompassEnabled: Bool = true` + settings toggle
  "Guiding chime". `audioCueGain` scaling = deterministic rules decide help.

### Idle nudges
- `lastInteractionAt` updated by every input: stick, buttons, interact, choose,
  sing, ask, hint, freeze begin, autopilot start.
- 1 Hz check in `gameTick`: eligible when
  `now - max(lastInteractionAt, narratorLastFinishedAt) > 25` AND
  `!narrator.isSpeaking && !isThinking && currentDialogue == nil &&
  activeSongSpell == nil && !listening && !isAutopiloting && currentStep != nil`.
- On fire: `consecutiveNudges += 1`;
  `tier = min(support.hintTier + consecutiveNudges - 1, ladder.count - 1)`; play a
  soft companion cue (existing "hum"/"sniffing" assets) then speak
  `step.hintLadder[tier]`. **Not** counted in `stepHintsUsed`, **no** telemetry
  sample — nudges are free help, never struggle-evidence against her.
  `consecutiveNudges` resets on any input or step completion.

### Earcons
- Footsteps/boundary: produced by WS1 `MovementEvent`s. Boundary additionally: a
  companion one-liner rotation ("That's the edge of the meadow — everything we
  need is back the other way!"), max every 30 s, only if the narrator is idle.
- Interaction range (5 Hz, vs `lastNearbyID`): nil→some →
  `earcon_near.wav` (rising third) at `0.8 * audioCueGain` +
  `HapticsDirector.interactionRange()`; some→nil → `earcon_leave.wav` soft. The
  chime makes the context button perceivable without vision.
- New assets → MANIFEST "Guidance" table + generator functions:
  `compass_chime_loop.wav` (sparse two-note bell, **MONO** — it's spatialized),
  `compass_tick.wav`, `earcon_near.wav`, `earcon_leave.wav`.

### Onboarding tutorial
**`App/Game/TutorialDirector.swift`** — code, not pack data (it teaches app-layer
controls; story packs stay world canon):
```swift
@MainActor final class TutorialDirector: ObservableObject {
    enum Phase: Int { case welcome, holdToWalk, steer, stopAndGo,
                      facingTick, talkButton, done }
    @Published private(set) var phase: Phase
    var isActive: Bool { phase != .done }
    func begin(narrator: Narrator, companion: Companion, childName: String)
    // Event hooks called by GameViewModel:
    func noteWalked(distance: Double)   // holdToWalk completes after 4 u
    func noteSteered(degrees: Double)   // steer completes after 60° cumulative
    func noteStickReleased()            // stopAndGo: release → praise → hold again
    func noteFacingTickPlayed()         // facingTick: hear one tick while facing
    func noteMicUsed()                  // talkButton completes
    func skip()
}
```
Each phase: a companion line (built-in strings, spoken with the companion voice,
prefetched by WS3 on first run), a completion criterion, and a 15 s phase-specific
re-prompt (replacing generic idle nudges while active). During the tutorial:
autopilot disabled; `enterScene()`'s step-intro append is skipped while
`tutorial.isActive`; `done` triggers the normal step intro.
- Persistence: `PlayerVault.tutorialCompleted: Bool = false` — learned once,
  across slots (**migration rule applies**).
- Skips: parent toggle "She already knows the controls" (sets the flag); auto-skip
  when any slot already has completed steps (second session ⇒ skip + mark done).
- Trigger: `GameViewModel.begin()` consults a `shouldRunTutorial` closure injected
  from AppModel (mirrors the existing `saveSlot` closure pattern).

### Acceptance
Stand still 25 s → companion nudges, again at a higher rung; face the target →
ticks; ticks accelerate on approach; walk into the ±40 edge → thump + one-liner
(once, not spam); fresh vault → full tutorial; second session → skipped;
`GuidanceMathTests` + existing `SnapshotTests` green.

---

# Sequencing for implementation agents

```
Phase A — 4 agents in parallel (no file overlap):
  A1  WS2: SpatialAudioEngine gain/bed + AudioMixCoordinator + SoundBank duck
      + pack.json volumes
  A2  WS1: GameLoop, MovementController, TouchControlView, HapticsDirector
      + GameView/GameViewModel wiring
  A3  WS3 StoryEngine: TTSProvider, ElevenLabs + OpenAI providers,
      TTSTimingMapper + unit tests
  A4  WS4: terrain batching, contrast, shape library, markers, high-contrast mode

Phase B:
  B1 (after A3)      WS3 app layer: SpeechCache, KeychainStore, SpeechPrefetcher,
                     Narrator refactor, VoiceSpec/VoiceDirector cloud column,
                     AppModel/Settings UI
  B2 (after A1+A2)   WS5: GuidanceMath, compass, nudges, earcons
                     (heavy GameViewModel edits — must follow A2)
  B3 (after A4)      WS4 bloom: PostEffects.swift
                     (task one: on-device nonAR postProcess check)

Phase C:
  C1 (after B2)      TutorialDirector + consolidated Codable migrations
                     (CalibrationProfile/PlayerVault custom init(from:) with
                     decodeIfPresent for ALL new fields: touchControlsEnabled,
                     bloomEnabled, audioCompassEnabled, tutorialCompleted)
                     + old-fixture decode test + settings toggles
  C2 (anytime)       Docs/ArtPipeline.md + MANIFEST.md additions
                     + generate_placeholder_audio.py functions
```

File-conflict serialization (do NOT parallelize within a row):
- `App/Game/GameViewModel.swift`: A2 → B2 → C1
- `App/Views/ParentGateView.swift`: B1 → C1
- `App/World/WorldView.swift`: A4 → B3

# Verification (whole pass)

- Build after every phase (command in Ground rules).
- `swift test --package-path Packages/StoryEngine` — must stay green throughout;
  new suites: `TTSTimingMapperTests` (A3), provider request-encoding golden tests
  (A3, no live network), `GuidanceMathTests` (B2), old-fixture vault decode test
  (C1 — **the test that protects her save file**).
- On-device checklist (the real gate — tester is dad + daughter): consolidated from
  each workstream's Acceptance section above.

# Risk register

1. **PHASE metaparameter semantics** (replace vs multiply, undocumented) — designed
   correct under either (mixer.gain stays 1.0); 5-min on-device check is WS2 task
   one; AVAudioPlayer ambience fallback designed.
2. **postProcess in nonAR mode** unverifiable from docs — feature-flagged; contrast
   + markers carry WS4's goal regardless.
3. **Gesture conflicts** — single-touch tracking with instant release on a second
   touch; freeze recognizer is window-level with `cancelsTouchesInView = false`;
   SwiftUI controls sit above the touch layer; VoiceOver disables it. A double-tap
   misfire only starts a self-announcing, any-touch-cancelable autopilot — costs
   nothing.
4. **Save-file wipe on Codable changes** — every new persisted field uses
   `decodeIfPresent` defaults; C1's old-fixture test enforces it. Highest-severity
   item in this pass.
5. **TTS latency/cost** — prefetch + 200 MB disk cache + 1.5 s budget with silent
   AVSpeech takeover + flash model default; speech rate baked into the cache key.
6. **iPad has no haptics** — every haptic paired with an earcon that carries the
   meaning alone.
7. **Nudge nagging / chime clutter** — hard suppression gates, quiet authored
   volumes (compass 0.22), `audioCueGain` scaling, parent toggles. Audio-first must
   never become audio-noise.
