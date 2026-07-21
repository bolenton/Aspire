import XCTest
@testable import StoryEngine

final class FlavoredTextTests: XCTestCase {
    func testDecodesBareString() throws {
        let text = try JSONDecoder().decode(FlavoredText.self, from: Data(#""Hello there.""#.utf8))
        XCTAssertEqual(text.base, "Hello there.")
        XCTAssertNil(text.byCompanion)
    }

    func testDecodesObjectWithOverrides() throws {
        let json = #"{"base": "Cross the bridge.", "byCompanion": {"ember": "Sniff! Adventure across the bridge!"}}"#
        let text = try JSONDecoder().decode(FlavoredText.self, from: Data(json.utf8))
        XCTAssertEqual(text.resolved(for: "ember"), "Sniff! Adventure across the bridge!")
        XCTAssertEqual(text.resolved(for: "petal"), "Cross the bridge.")
        XCTAssertEqual(text.resolved(for: nil), "Cross the bridge.")
    }

    func testEncodesPlainTextAsBareString() throws {
        let data = try JSONEncoder().encode(FlavoredText("Hi"))
        XCTAssertEqual(String(data: data, encoding: .utf8), #""Hi""#)
    }

    func testRoundTripWithOverrides() throws {
        let original = FlavoredText("base", byCompanion: ["clover": "soft version"])
        let decoded = try JSONDecoder().decode(FlavoredText.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}

final class StoryPackTests: XCTestCase {
    func testRoundTrip() throws {
        let pack = Fixtures.pack()
        let decoded = try JSONDecoder().decode(StoryPack.self, from: JSONEncoder().encode(pack))
        XCTAssertEqual(decoded, pack)
    }

    func testLegacySingularCompanionShim() throws {
        let json = #"""
        {"id": "p", "title": "T", "version": 1,
         "companion": {"id": "ember", "name": "Ember", "species": "fox", "personality": "warm"}}
        """#
        let pack = try StoryPack.load(from: Data(json.utf8))
        XCTAssertEqual(pack.companions?.count, 1)
        XCTAssertEqual(pack.companions?.first?.id, "ember")
        XCTAssertEqual(pack.regions, [])
    }

    func testMinimalCompanionEntryGetsDefaults() throws {
        let json = #"{"id": "momo", "name": "Momo", "species": "owl", "personality": "wise"}"#
        let companion = try JSONDecoder().decode(Companion.self, from: Data(json.utf8))
        XCTAssertEqual(companion.introduction, "Hi! I'm Momo the owl.")
        XCTAssertEqual(companion.abilities, [])
        XCTAssertEqual(companion.audibleRangeMultiplier, 1.0)
        XCTAssertEqual(companion.speechStyle.exclamation, "Oh!")
    }

    func testAvailableCompanionsMergesRosterAndFilters() {
        var pack = Fixtures.pack()
        pack.companionIDs = ["ember", "clover"]
        let available = pack.availableCompanions(sharedRoster: Fixtures.roster)
        XCTAssertEqual(available.map(\.id), ["ember", "clover"])

        pack.companions = [Companion(id: "robo", name: "Robo", species: "robot", personality: "beeps")]
        XCTAssertEqual(pack.availableCompanions(sharedRoster: Fixtures.roster).map(\.id),
                       ["ember", "clover", "robo"])
    }
}

final class SongSpellTests: XCTestCase {
    func testNotesScaleWithChallenge() {
        let spell = SongSpell(id: "s", name: "Song", notes: [.do, .re, .mi, .fa, .sol])
        XCTAssertEqual(spell.notes(forChallenge: 1), [.do, .re, .mi])
        XCTAssertEqual(spell.notes(forChallenge: 2), [.do, .re, .mi, .fa])
        XCTAssertEqual(spell.notes(forChallenge: 3), [.do, .re, .mi, .fa, .sol])
        XCTAssertEqual(spell.notes(forChallenge: 5), [.do, .re, .mi, .fa, .sol],
                       "clamps to the authored melody")
    }

    func testShortSongIsNeverExtended() {
        let spell = SongSpell(id: "s", name: "Tiny", notes: [.do, .re])
        XCTAssertEqual(spell.notes(forChallenge: 4), [.do, .re])
    }
}

final class GatingTests: XCTestCase {
    func testCompanionGatedQuestFiltering() {
        let pack = Fixtures.pack()
        let emberDone = Fixtures.progress(companion: Fixtures.ember, flags: ["acorn_found"])
        XCTAssertTrue(emberDone.availableQuests(in: pack).contains { $0.id == "ember_treat_quest" })

        let emberEarly = Fixtures.progress(companion: Fixtures.ember)
        XCTAssertFalse(emberEarly.availableQuests(in: pack).contains { $0.id == "ember_treat_quest" })

        let cloverDone = Fixtures.progress(companion: Fixtures.clover, flags: ["acorn_found"])
        XCTAssertFalse(cloverDone.availableQuests(in: pack).contains { $0.id == "ember_treat_quest" })
    }

    func testAbilityGatingPerCompanion() {
        let scene = Fixtures.scene()

        let forEmber = scene.activeEntities(companion: Fixtures.ember)
        let treat = forEmber.first { $0.entity.id == "buried_treat" }
        XCTAssertEqual(treat?.revealedByAbilityID, "keen_smell")
        XCTAssertEqual(treat?.isAnonymousTease, false)
        // No tease authored for the nest, so Ember doesn't know it exists.
        XCTAssertNil(forEmber.first { $0.entity.id == "high_nest" })

        let forPetal = scene.activeEntities(companion: Fixtures.petal)
        let teasedTreat = forPetal.first { $0.entity.id == "buried_treat" }
        XCTAssertEqual(teasedTreat?.isAnonymousTease, true)
        XCTAssertEqual(forPetal.first { $0.entity.id == "high_nest" }?.revealedByAbilityID, "high_flight")
    }

    func testFlagLockedAvailability() {
        let progress = Fixtures.progress()
        let gate = Fixtures.scene().entities.first { $0.id == "castle_gate" }!
        let availability = progress.availability(of: gate)
        XCTAssertFalse(availability.available)
        XCTAssertEqual(availability.explanation, "The bridge to the castle is still broken.")

        let repaired = Fixtures.progress(flags: ["bridge_repaired"])
        XCTAssertTrue(repaired.availability(of: gate).available)
    }
}

final class TravelTests: XCTestCase {
    private var gate: Entity {
        Fixtures.scene().entities.first { $0.id == "castle_gate" }!
    }

    func testLockedPortalRefusesTravel() {
        var progress = Fixtures.progress()
        XCTAssertNil(progress.travel(through: gate))
        XCTAssertEqual(progress.currentSceneID, "fox_hollow")
    }

    func testOpenPortalTravels() {
        var progress = Fixtures.progress(flags: ["bridge_repaired"])
        XCTAssertEqual(progress.travel(through: gate), "castle_courtyard")
        XCTAssertEqual(progress.currentSceneID, "castle_courtyard")
    }

    func testNonPortalNeverTravels() {
        var progress = Fixtures.progress()
        let river = Fixtures.scene().entities.first { $0.id == "river" }!
        XCTAssertNil(progress.travel(through: river))
    }
}

final class GameProgressTests: XCTestCase {
    func testQuestStepFlow() {
        let pack = Fixtures.pack()
        var progress = Fixtures.progress()

        XCTAssertEqual(progress.currentStep(in: pack)?.id, "reach_oak")
        XCTAssertNil(progress.completeStepIfTargeted(entityID: "river", in: pack))

        let reached = progress.completeStepIfTargeted(entityID: "old_oak", in: pack)
        XCTAssertEqual(reached?.id, "reach_oak")
        XCTAssertEqual(progress.currentStep(in: pack)?.id, "take_acorn")

        let collected = progress.completeStepIfTargeted(entityID: "glowing_acorn", in: pack)
        XCTAssertEqual(collected?.id, "take_acorn")
        XCTAssertTrue(progress.flags.contains("acorn_found"))
        XCTAssertTrue(progress.inventory.contains("glowing_acorn"))
        XCTAssertTrue(progress.isQuestComplete(pack.quest(id: "glowing_acorn_quest")!))
    }

    func testCompanionResolutionFallsBack() {
        let available = Fixtures.roster.companions
        XCTAssertEqual(Fixtures.progress(companion: Fixtures.clover).companion(in: available)?.id, "clover")

        var unknown = Fixtures.progress()
        unknown.chosenCompanionID = "ghost"
        XCTAssertEqual(unknown.companion(in: available)?.id, "ember")
    }
}

final class DifficultyDirectorTests: XCTestCase {
    private func struggle() -> TelemetrySample {
        TelemetrySample(kind: .navigation, succeeded: false, duration: 30)
    }

    private func win() -> TelemetrySample {
        TelemetrySample(kind: .navigation, succeeded: true, duration: 20)
    }

    func testStrugglesEscalateSupport() {
        var director = DifficultyDirector()
        let before = director.support
        director.record(struggle())
        director.record(struggle())
        XCTAssertGreaterThan(director.support.audioCueGain, before.audioCueGain)
        XCTAssertGreaterThan(director.support.hintTier, before.hintTier)
        XCTAssertTrue(director.lastChangeWasEscalation)
    }

    func testStreakNeverDropsBelowBaseline() {
        var director = DifficultyDirector(profile: CalibrationProfile(hintAggressiveness: .eager))
        XCTAssertEqual(director.support.hintTier, 2)
        XCTAssertEqual(director.struggleDuration, 60)
        for _ in 0..<10 { director.record(win()) }
        XCTAssertGreaterThanOrEqual(director.support.audioCueGain, director.baseline.audioCueGain)
        XCTAssertGreaterThanOrEqual(director.support.glowBoost, director.baseline.glowBoost)
        XCTAssertGreaterThanOrEqual(director.support.hintTier, director.baseline.hintTier)
        XCTAssertGreaterThan(director.support.challenge, 1)
    }

    func testSlowSuccessCountsAsStruggle() {
        var director = DifficultyDirector()
        director.record(TelemetrySample(kind: .puzzle, succeeded: true, duration: 200))
        director.record(TelemetrySample(kind: .puzzle, succeeded: true, duration: 200))
        XCTAssertTrue(director.lastChangeWasEscalation)
    }

    func testHintResolvesLadderAndFlavor() {
        var director = DifficultyDirector(baseline: SupportLevel(audioCueGain: 1, glowBoost: 1, hintTier: 0, challenge: 1))
        let step = QuestStep(id: "s", goal: .reach, targetEntityID: "old_oak",
                             intro: "intro", celebration: "yay",
                             hintLadder: ["gentle",
                                          FlavoredText("middle", byCompanion: ["clover": "soft middle"]),
                                          "explicit"])
        XCTAssertEqual(director.hint(for: step, companionID: "ember"), "gentle")
        director.record(struggle())
        director.record(struggle())
        XCTAssertEqual(director.hint(for: step, companionID: "clover"), "soft middle")
    }
}

final class VisualSpecTests: XCTestCase {
    func testDecodesWithoutAssetNameAsNil() throws {
        // ##-delimited: the color's "# would end a plain #"..."# raw string.
        let json = ##"{"shape": "tree", "colorHex": "#FFD24A", "scale": 1.2, "glow": 1.0}"##
        let spec = try JSONDecoder().decode(VisualSpec.self, from: Data(json.utf8))
        XCTAssertNil(spec.assetName)
        XCTAssertEqual(spec.shape, "tree")
    }

    func testDecodesAssetNameWhenPresent() throws {
        let json = ##"{"shape": "tree", "colorHex": "#FFD24A", "scale": 1.0, "glow": 1.0, "assetName": "old_oak"}"##
        let spec = try JSONDecoder().decode(VisualSpec.self, from: Data(json.utf8))
        XCTAssertEqual(spec.assetName, "old_oak")
    }

    func testRoundTripPreservesAssetName() throws {
        let original = VisualSpec(shape: "chest", colorHex: "#AA5500", assetName: "treasure_chest")
        let decoded = try JSONDecoder().decode(VisualSpec.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}
