import Foundation
@testable import StoryEngine

enum Fixtures {
    static let ember = Companion(
        id: "ember", name: "Ember", species: "fox",
        personality: "Bold, warm, a little mischievous.",
        quirks: ["ends excited sentences with a soft yip"],
        abilities: [PerceptionAbility(id: "keen_smell", name: "Fox Nose",
                                      spokenDescription: "I can smell things that hide.",
                                      senseVerb: "smell")],
        speechStyle: SpeechStyle(exclamation: "Yip!"))

    static let petal = Companion(
        id: "petal", name: "Petal", species: "butterfly",
        personality: "Dreamy, gentle, notices beauty everywhere.",
        abilities: [PerceptionAbility(id: "high_flight", name: "Sky Wings",
                                      spokenDescription: "I can flutter up high and see what's above.",
                                      senseVerb: "see")],
        speechStyle: SpeechStyle(exclamation: "Ooh!"))

    static let clover = Companion(
        id: "clover", name: "Clover", species: "bunny",
        personality: "Shy, kind, the best listener in the forest.",
        abilities: [PerceptionAbility(id: "super_hearing", name: "Bunny Ears",
                                      spokenDescription: "My big ears hear the quietest sounds, even far away.",
                                      senseVerb: "ears",
                                      audibleRangeMultiplier: 1.6)],
        speechStyle: SpeechStyle(exclamation: "Oh my!"))

    static let roster = CompanionRoster(companions: [ember, petal, clover])

    static func scene() -> Scene {
        Scene(
            id: "fox_hollow", name: "Fox Hollow",
            spokenDescription: FlavoredText(
                "A mossy clearing wrapped in tall whispering trees.",
                byCompanion: ["clover": "A mossy clearing. So many gentle sounds to hear here."]),
            ambience: [
                SoundSpec(asset: "wind_loop.caf", spokenDescription: "wind in the leaves"),
                SoundSpec(asset: "crickets_loop.caf", spokenDescription: "crickets singing"),
            ],
            entities: [
                Entity(id: StoryConventions.companionPlaceholder, kind: .companion,
                       name: "your companion", position: Vec3(x: 1, y: 0, z: -2),
                       sound: SoundSpec(asset: "companion_call.caf", farRadius: 40,
                                        spokenDescription: "your friend's voice")),
                Entity(id: "river", kind: .landmark, name: "river",
                       position: Vec3(x: 12, y: 0, z: 0),
                       sound: SoundSpec(asset: "river_loop.caf", farRadius: 30,
                                        spokenDescription: "flowing water")),
                Entity(id: "old_oak", kind: .landmark, name: "old oak",
                       position: Vec3(x: 0, y: 0, z: -10),
                       sound: SoundSpec(asset: "oak_creak.caf", farRadius: 15,
                                        spokenDescription: "creaking wood")),
                Entity(id: "glowing_acorn", kind: .item, name: "glowing acorn",
                       position: Vec3(x: 1, y: 0, z: -10.5)),
                Entity(id: "castle_gate", kind: .portal, name: "castle gate",
                       position: Vec3(x: -15, y: 0, z: -5),
                       requiresFlag: "bridge_repaired",
                       lockedExplanation: "The bridge to the castle is still broken."),
                Entity(id: "buried_treat", kind: .item, name: "buried treat",
                       position: Vec3(x: 3, y: 0, z: -6),
                       requiresAbility: "keen_smell",
                       senseLine: "My nose found something buried near the big root!",
                       hiddenTease: "Something is hiding near the big root, but I can't tell what."),
                Entity(id: "high_nest", kind: .item, name: "high nest",
                       position: Vec3(x: 5, y: 4, z: -8),
                       requiresAbility: "high_flight",
                       senseLine: "I can see a cozy nest up in the branches!"),
                Entity(id: "hidden_stream", kind: .landmark, name: "hidden stream",
                       position: Vec3(x: -6, y: -1, z: 4),
                       sound: SoundSpec(asset: "stream_quiet.caf", volume: 0.4, farRadius: 8,
                                        spokenDescription: "a tiny trickle of water"),
                       requiresAbility: "super_hearing",
                       senseLine: "My ears hear water murmuring under the ground!",
                       hiddenTease: "I feel like something is murmuring nearby, but it's too quiet for me."),
            ])
    }

    static func pack() -> StoryPack {
        StoryPack(
            id: "forest_journey", title: "Forest Journey", version: 1,
            companionIDs: ["ember", "petal", "clover"],
            regions: [Region(id: "whispering_forest", name: "Whispering Forest",
                             difficultyTier: 1, newMechanic: "walk_and_listen",
                             scenes: [scene()])],
            quests: [
                Quest(id: "glowing_acorn_quest", title: "The Glowing Acorn",
                      spokenSummary: FlavoredText(
                        "We promised the old oak we'd find its glowing acorn.",
                        byCompanion: ["ember": "Yip! We promised the old oak we'd sniff out its glowing acorn."]),
                      steps: [
                        QuestStep(id: "reach_oak", goal: .reach, targetEntityID: "old_oak",
                                  intro: "First, let's find the old oak tree.",
                                  celebration: "You found the old oak! Listen to it creak hello.",
                                  hintLadder: [
                                    "The oak is the creaky sound. Listen for it.",
                                    "Follow the creaking wood — it's the old oak.",
                                    FlavoredText("Walk straight toward the creaking sound ahead. That's the old oak."),
                                  ]),
                        QuestStep(id: "take_acorn", goal: .collect, targetEntityID: "glowing_acorn",
                                  intro: "The glowing acorn is near the oak's roots.",
                                  celebration: "You got the glowing acorn!",
                                  hintLadder: ["It's very close to the oak.",
                                               "Feel around the oak's roots.",
                                               "The acorn is right beside the oak, one step away."],
                                  setsFlag: "acorn_found"),
                      ]),
                Quest(id: "ember_treat_quest", title: "The Buried Treat",
                      spokenSummary: "My nose says there's a treat buried somewhere in the hollow!",
                      steps: [QuestStep(id: "dig_treat", goal: .collect, targetEntityID: "buried_treat",
                                        intro: "Let's dig up what my nose found.",
                                        celebration: "A honey biscuit! Yip!",
                                        hintLadder: ["Follow my sniffing sounds."])],
                      requiresCompanion: "ember",
                      requiresFlag: "acorn_found"),
            ],
            dialogues: [
                DialogueNode(id: "d_intro", speaker: StoryConventions.companionPlaceholder,
                             line: FlavoredText("There you are! Ready for an adventure?"),
                             choices: [
                                DialogueChoice(id: "c_yes", text: "Yes! Let's go!",
                                               memoryKey: "adventure_spirit", memoryValue: "brave"),
                                DialogueChoice(id: "c_shy", text: "I'm a little nervous...",
                                               memoryKey: "adventure_spirit", memoryValue: "careful"),
                             ]),
            ],
            songSpells: [SongSpell(id: "oak_song", name: "The Oak's Waking Song",
                                   notes: [.do, .re, .mi])])
    }

    static func progress(companion: Companion = ember,
                         flags: Set<String> = [],
                         questID: String? = "glowing_acorn_quest") -> GameProgress {
        GameProgress(storyPackID: "forest_journey", currentSceneID: "fox_hollow",
                     chosenCompanionID: companion.id, activeQuestID: questID, flags: flags)
    }

    static func snapshot(companion: Companion = ember,
                         pose: PlayerPose = PlayerPose(),
                         flags: Set<String> = [],
                         support: SupportLevel = .standard,
                         events: EventLog = EventLog()) -> WorldSnapshot {
        SnapshotBuilder.build(pack: pack(), companion: companion, scene: scene(),
                              pose: pose, progress: progress(companion: companion, flags: flags),
                              events: events, support: support, tick: 100)
    }

    static func context(companion: Companion = ember,
                        memories: [String] = []) -> CompanionContext {
        CompanionContext(companion: companion, childName: "Aria",
                         snapshot: snapshot(companion: companion),
                         recentMemories: memories)
    }
}
