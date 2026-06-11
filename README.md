# Lantern 🏮

An adaptive, audio-first story adventure for visually impaired kids — built native for iOS, designed so that **sound is the world and vision confirms it**.

Built for one brilliant 9-year-old, and shipped in her honor for every kid like her.

## Design pillars

1. **Sound is the primary sense.** Every object in the world is a spatial sound source (Apple PHASE engine). With AirPods, head tracking keeps sounds anchored in the world as she turns her head. Visuals are big, glowing, high-contrast shapes that *confirm* what her ears already told her.
2. **A living companion, not a narrator.** The fox explains objectives, answers spoken questions, reacts to mistakes, and remembers her choices — powered by a swappable AI brain that is *grounded in authored story canon* and can never invent plot.
3. **The game never requires a model.** A deterministic scripted brain handles core questions offline. Every AI provider is strictly an upgrade.
4. **Adaptive difficulty by legible rules.** Struggle → stronger audio cues, brighter glow, more explicit hints. Success streaks → more independence, harder puzzles. Deterministic rules decide *what* support to give; AI only phrases hints in character.
5. **Memory creates attachment.** Choices, favorites, and outcomes persist. Weeks later: *"Last time you helped the fisherman."*
6. **Reading optional but encouraged.** The narrator speaks everything; giant text displays simultaneously with word-by-word highlighting; tap any word to hear it again.
7. **A safe world.** No deaths, no game overs, no punishment loops. Curiosity and exploration are always rewarded.
8. **Regions, not levels.** Whispering Forest → Crystal Caves → Sky Islands → City of Lanterns. Each region introduces exactly one new mechanic.
9. **Music as magic.** Characters sing short solfège phrases; she sings or taps them back to cast spells. Complexity ramps gently.
10. **One engine, many stories.** All content lives in data-driven story packs (JSON). Forest Journey first; Space Explorer, Pirate Adventure, folktales, and community packs on the same engine.

## Architecture

```
Packages/StoryEngine/        Platform-independent Swift (testable on Linux)
  StoryPack                  Codable content model: regions, scenes, entities,
                             quests, dialogue, song-spells, hint ladders
  GameProgress               Quest state, flags, inventory
  MemoryJournal              Persistent memories the companion recalls
  DifficultyDirector         Telemetry in → support levels out (pure rules)
  Companion/
    CompanionBrain           Protocol + grounded prompt builder (safety contract)
    ScriptedBrain            Offline deterministic fallback
    OpenAICompatibleBrain    Any OpenAI-compatible endpoint: Ollama, LM Studio,
                             llama.cpp server, cloud gateways
App/                         iOS app layer (Apple frameworks only)
  SwiftUI + RealityKit       Big glowing high-contrast world
  PHASE                      3D positional audio, head-tracked with AirPods
  AVSpeechSynthesizer        Narration with per-word text highlighting
  Speech                     On-device recognition — talk to the fox
StoryPacks/ForestJourney/    First story pack (Whispering Forest)
```

Planned app-layer brains (same `CompanionBrain` protocol): Apple's on-device
Foundation Model (iOS 26, Apple Intelligence hardware) as the zero-setup
default, and a bundled small Gemma running locally for older devices.

## Building & installing on the iPad (Mac required)

```sh
brew install xcodegen
xcodegen                     # generates Lantern.xcodeproj from project.yml
open Lantern.xcodeproj       # set your signing team, plug in the iPad, Run ▶
```

Note: with a free Apple ID the install expires after 7 days and needs a re-run
from Xcode. A paid developer account ($99/yr — needed for TestFlight/App Store
anyway) extends that to a year.

## Developing the engine (any OS)

```sh
swift test --package-path Packages/StoryEngine
```

CI runs the engine tests on Linux and compiles the full iOS app on a macOS
runner for every push.

## Roadmap

- [x] Engine core: content model, progress, memory, difficulty, companion brains
- [ ] Chapter 1 playable: Fox Hollow scene, spatial audio, touch movement
- [ ] Narration with word highlighting + tap-to-replay
- [ ] Voice input — ask the fox questions out loud
- [ ] Song-spells (solfège call-and-response)
- [ ] Apple Foundation Model + bundled Gemma brains
- [ ] AirPods head tracking
- [ ] TestFlight beta with the AppleVis / audiogames.net communities
- [ ] Free App Store release, Kids category
