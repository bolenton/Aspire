# Lantern 🏮

An adaptive, audio-first story adventure for visually impaired kids — built
native for iOS, designed so that **sound is the world and vision confirms it**.

Built for one brilliant 9-year-old, and shipped in her honor for every kid
like her.

The Unity port is under development in [Clients/Lantern.Unity](Clients/Lantern.Unity/README.md). Lantern Meadow now has newly authored characters and scenery, touch-anywhere movement, optional visible controls/captions, and a new recorded sound set. See [port status](Docs/UnityPortStatus.md) for exact Editor/device verification and remaining work. The instructions below still describe the existing Swift app.

## How it plays

She chooses a companion — **Ember the fox**, **Petal the butterfly**, or
**Clover the bunny** — by listening to each one say hello. Her companion
narrates the world, answers spoken questions (tap-to-talk), remembers her
choices, and guides her through regions of a gentle story where conflict is
resolved with solfège song-spells, never violence.

The companion choice matters, Pokémon-style: every line of dialogue is
flavored per companion, each has exclusive side quests, and each has a unique
**perception ability** that reveals different secrets in the same scenes —
Ember's Fox Nose smells buried things, Petal's Sky Wings spot what's up high,
Clover's Bunny Ears hear the quietest sounds (and genuinely extend how far she
can hear). Finishing the story with one friend leaves two more playthroughs of
new content waiting.

**Freeze and explain**: hold two fingers anywhere, on any screen, and the
world gently pauses while the companion explains exactly where she is and
what's around — deterministic, instant, offline.

**Calibration**: a spoken first-launch wizard sets text size, contrast
polarity, narration speed, and hint aggressiveness per child; adaptive
difficulty then moves relative to that baseline and never drops support
below it. Re-tunable behind a parent gate.

## Design pillars

1. **Sound is the primary sense.** Every object is a spatial audio source
   (Apple PHASE). Visuals are big, glowing, high-contrast shapes that confirm
   what her ears already told her.
2. **A living companion, not a narrator.** The AI brain receives a live
   **WorldSnapshot** — everything she can currently perceive, with directions
   ("the river, to your right, about 12 big steps away"), locked exits and
   why, quest state, recent events — so spoken questions get situationally
   true answers. It is grounded in authored canon and can never invent plot.
3. **The game never requires a model.** A deterministic scripted brain
   answers from the same snapshot, offline. Every AI provider is strictly an
   upgrade, with seamless fallback.
4. **Adaptive difficulty by legible rules.** Struggle → stronger cues,
   brighter glow, more explicit hints. Deterministic rules decide *what* help
   to give; AI may only phrase it.
5. **Memory creates attachment.** Choices and favorites persist per
   playthrough and across them. Weeks later: "Last time you helped the
   fisherman."
6. **Reading optional but encouraged.** Giant text highlights word-by-word as
   the narrator speaks; tap any word to hear it again.
7. **A safe world.** No deaths, no game overs, no punishment loops.
8. **Regions, not levels.** Each region introduces exactly one new mechanic.
9. **One engine, many stories.** All content is data-driven JSON story packs;
   companions are extensible the same way — adding a fourth is a content
   task, not an engine change.

## Architecture

```
Packages/StoryEngine/        Platform-independent Swift (tested on Linux CI)
  StoryPack + FlavoredText   Content model; every spoken line per-companion
  CompanionRoster            Personas, quirks, voices, abilities, templates
  Scene.activeEntities       Companion/ability/flag gating — single source
  WorldSnapshot + Builder    Real-time perception model (directions, kid
                             distances, locked reasons, ability findings)
  SituationReport            Freeze-and-explain deterministic readout
  CompanionBrain             PromptBuilder safety contract + providers:
                             ScriptedBrain (offline) / OpenAICompatibleBrain
                             (Ollama, LM Studio, llama.cpp, gateways)
  DifficultyDirector         Calibrated baseline + legible adaptive rules
  SaveSlot / PlayerVault     Per-companion playthroughs, shared favorites
App/                         iOS app layer (SwiftUI + Apple frameworks)
  PHASE spatial audio        Looping 3D sources, listener follows her pose
  Narrator                   AVSpeech + word-by-word highlight + tap-a-word
  SpeechListener             Tap-to-talk, on-device recognition
  Calibration wizard         Spoken setup; parent gate for re-tuning + AI
  Freeze gesture             Window-level two-finger hold, every screen
StoryPacks/                  roster.json + ForestJourney chapter 1
Assets/Audio/MANIFEST.md     Every audio cue with production status
ASSETS.md                    License ledger — nothing ships unledgered
```

## Building & installing on the iPad (Mac required)

```sh
brew install xcodegen
xcodegen                     # generates Lantern.xcodeproj from project.yml
open Lantern.xcodeproj       # set your signing team, plug in the iPad, Run ▶
```

Notes:
- With a free Apple ID the install expires after 7 days; a paid developer
  account ($99/yr, needed for TestFlight/App Store anyway) extends it to a year.
- Binary assets are committed directly (no Git LFS yet — see .gitattributes
  for when/how to enable it once large final assets arrive).
- The game runs fully without audio assets (sources are skipped until files
  land per `Assets/Audio/MANIFEST.md`) and without any AI configured.

### Connecting the companion AI (optional, parent settings)

Run Ollama or LM Studio on a Mac on the same Wi-Fi, then in
Grown-ups → Companion AI set e.g. endpoint `http://your-mac.local:11434/v1`
and model `gemma3:4b`. Any OpenAI-compatible endpoint works. If it's ever
unreachable, the built-in scripted companion takes over mid-conversation.

## Developing the engine (any OS)

```sh
swift test --package-path Packages/StoryEngine
```

CI runs the engine tests on Linux and compiles the full iOS app on a macOS
runner for every push.

## Roadmap

- [x] Engine: content model, gating, snapshots, brains, difficulty, vault
- [x] Companion roster: Ember / Petal / Clover with abilities + templates
- [x] Forest Journey chapter 1 (Fox Hollow) with per-companion secrets
- [x] App: calibration wizard, picker ceremony, audio-first game loop,
      tap-to-talk, freeze-and-explain, parent gate
- [x] Placeholder audio pass — all 36 cues procedurally synthesized
      (`Tools/generate_placeholder_audio.py`); swap in curated/final sounds
      file-by-file per Assets/Audio/MANIFEST.md
- [x] Solfège notes as real tones; song-spell length scales with challenge
      (listen-first melody, gentle replay on misses)
- [x] RealityKit glowing world: procedural emissive shapes per VisualSpec,
      breathing halo on the quest target (scaled by adaptive glow boost),
      drifting fireflies, first-person camera gliding with her pose —
      commissioned models later swap into the same layout
- [x] AirPods head tracking: head yaw offsets the PHASE listener AND the
      companion's perception (directions match where her head points);
      camera stays on body heading so visuals don't lurch
- [x] Crystal Caves region behind the waterfall: portal travel between
      scenes, longer echo songs, Boulder the sleepy guardian, per-companion
      cave secrets, and the moonstone quest that mends the broken bridge
- [x] Brain providers: Apple Foundation Model behind the same protocol
      (conditionally compiled — activates on Apple Intelligence devices when
      built with the iOS 26 SDK), Auto/On-device/Server/Built-in provider
      policy, and a "test the companion brain" button in parent settings.
      A bundled on-device Gemma stays future work (needs llama.cpp runtime
      + multi-GB weights); a home Ollama server covers that today
- [x] City of Lanterns: the mended bridge leads to the Lantern Courtyard —
      Wick the lantern keeper, the seven-note bell tower song, lighting the
      festival, and per-companion secrets (biscuit stall / flag garland /
      the mice choir). The chapter-3 finale lights a whole city
- [x] Memory fully wired: the companion's live AI context now carries her
      remembered choices; "favorite" choices cross playthroughs
- [x] Graphics definition overhaul: Retina mipmapped icon chips, drawn
      depth-edge outlines around every object (white in high contrast),
      dual-scale bloom (sharp core + soft aura), real cast shadows, gradient
      sky domes per biome — and the `VisualSpec.assetName` USDZ slot with
      procedural fallback (Docs/ArtPipeline.md) so commissioned/generated
      models drop in without engine changes
- [x] Release engineering: PRIVACY.md (collects nothing), Docs/AppStore.md
      (listing draft, Kids checklist, TestFlight guide), a one-click
      TestFlight upload workflow (add 3 secrets to arm it), in-app
      About/credits behind the parent gate, VoiceOver label pass

Remaining steps are human ones:
- [ ] Her first playtest — everything after this is steered by it
- [ ] Curated/recorded sound pass replacing placeholders file-by-file
- [ ] Commission the three companions (rigged + animated) and environment kit
- [ ] Apple Developer account → run the Release workflow → TestFlight beta
      with the AppleVis / audiogames.net communities → free Kids release,
      in her honor
