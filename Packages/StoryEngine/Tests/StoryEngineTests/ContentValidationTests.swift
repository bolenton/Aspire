import XCTest
@testable import StoryEngine

/// Validates the real shipped content in StoryPacks/ — referential integrity
/// between quests, entities, dialogues, and song spells, so authoring
/// mistakes fail CI instead of confusing a child.
final class ContentValidationTests: XCTestCase {
    private static var repoRoot: URL {
        // .../Packages/StoryEngine/Tests/StoryEngineTests/ThisFile.swift -> repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func data(at relativePath: String) throws -> Data {
        let url = Self.repoRoot.appendingPathComponent(relativePath)
        return try Data(contentsOf: url)
    }

    func testRosterDecodesWithThreeLaunchCompanions() throws {
        let roster = try CompanionRoster.load(from: data(at: "StoryPacks/Companions/roster.json"))
        XCTAssertEqual(roster.companions.map(\.id), ["ember", "petal", "clover"])
        for companion in roster.companions {
            XCTAssertFalse(companion.introduction.isEmpty)
            XCTAssertFalse(companion.abilities.isEmpty, "\(companion.id) needs a perception ability")
            XCTAssertFalse(companion.personality.isEmpty)
        }
        // Clover's Bunny Ears must boost hearing.
        XCTAssertGreaterThan(roster.companion(id: "clover")!.audibleRangeMultiplier, 1.0)
    }

    func testForestJourneyDecodesAndReferencesResolve() throws {
        let pack = try StoryPack.load(from: data(at: "StoryPacks/ForestJourney/pack.json"))
        let roster = try CompanionRoster.load(from: data(at: "StoryPacks/Companions/roster.json"))

        let companions = pack.availableCompanions(sharedRoster: roster)
        XCTAssertEqual(companions.count, 3)
        XCTAssertFalse(pack.regions.isEmpty)

        let allEntities = pack.regions.flatMap(\.scenes).flatMap(\.entities)
        let entityIDs = Set(allEntities.map(\.id))
        let dialogueIDs = Set(pack.dialogues.map(\.id))
        let spellIDs = Set(pack.songSpells.map(\.id))
        let abilityIDs = Set(roster.companions.flatMap(\.abilities).map(\.id))
        let companionIDs = Set(roster.companions.map(\.id))

        for quest in pack.quests {
            XCTAssertFalse(quest.steps.isEmpty, "quest \(quest.id) has no steps")
            if let required = quest.requiresCompanion {
                XCTAssertTrue(companionIDs.contains(required), "quest \(quest.id): unknown companion \(required)")
            }
            for step in quest.steps {
                XCTAssertTrue(entityIDs.contains(step.targetEntityID),
                              "quest \(quest.id) step \(step.id): unknown target \(step.targetEntityID)")
                XCTAssertFalse(step.hintLadder.isEmpty, "step \(step.id) needs hints")
                if let spell = step.songSpellID {
                    XCTAssertTrue(spellIDs.contains(spell), "step \(step.id): unknown song \(spell)")
                }
            }
        }

        let sceneIDs = Set(pack.regions.flatMap(\.scenes).map(\.id))
        for entity in allEntities {
            if let dialogue = entity.dialogueID {
                XCTAssertTrue(dialogueIDs.contains(dialogue), "entity \(entity.id): unknown dialogue \(dialogue)")
            }
            if let destination = entity.destinationSceneID {
                XCTAssertEqual(entity.kind, .portal, "entity \(entity.id): only portals lead somewhere")
                XCTAssertTrue(sceneIDs.contains(destination),
                              "portal \(entity.id): unknown destination \(destination)")
            }
            if let ability = entity.requiresAbility {
                XCTAssertTrue(abilityIDs.contains(ability), "entity \(entity.id): unknown ability \(ability)")
                XCTAssertNotNil(entity.senseLine, "entity \(entity.id): ability secrets need a senseLine")
            }
            if let required = entity.requiresCompanion {
                XCTAssertTrue(companionIDs.contains(required), "entity \(entity.id): unknown companion \(required)")
            }
            if entity.requiresFlag != nil {
                XCTAssertNotNil(entity.lockedExplanation,
                                "entity \(entity.id): flag-locked entities need a spoken explanation")
            }
        }

        for dialogue in pack.dialogues {
            for choice in dialogue.choices {
                if let next = choice.nextDialogueID {
                    XCTAssertTrue(dialogueIDs.contains(next),
                                  "dialogue \(dialogue.id) choice \(choice.id): unknown next \(next)")
                }
            }
        }
    }

    func testEveryCompanionGetsAnAbilitySecretInEveryScene() throws {
        let pack = try StoryPack.load(from: data(at: "StoryPacks/ForestJourney/pack.json"))
        let roster = try CompanionRoster.load(from: data(at: "StoryPacks/Companions/roster.json"))

        for scene in pack.regions.flatMap(\.scenes) {
            for companion in roster.companions {
                let revealed = scene.activeEntities(companion: companion)
                    .filter { $0.revealedByAbilityID != nil }
                XCTAssertFalse(revealed.isEmpty,
                               "\(companion.name) needs an ability secret in \(scene.id) — that's the replay magic")
            }
        }
    }
}
