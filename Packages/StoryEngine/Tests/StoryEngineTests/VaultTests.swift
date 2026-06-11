import XCTest
@testable import StoryEngine

final class EventLogTests: XCTestCase {
    func testRingBufferCapsAndOrders() {
        var log = EventLog(capacity: 3)
        for i in 1...5 {
            log.record(GameEvent(tick: TimeInterval(i), kind: .flagSet, spoken: "event \(i)"))
        }
        XCTAssertEqual(log.events.count, 3)
        XCTAssertEqual(log.recent(limit: 2).map(\.spoken), ["event 5", "event 4"])
    }
}

final class MemoryJournalTests: XCTestCase {
    func testRecallReturnsLatestValue() {
        var journal = MemoryJournal()
        journal.remember(MemoryEvent(kind: .favorite, key: "favorite_color", value: "purple",
                                     spokenRecap: "Your favorite color is purple."))
        journal.remember(MemoryEvent(kind: .favorite, key: "favorite_color", value: "gold",
                                     spokenRecap: "Your favorite color is gold now."))
        XCTAssertEqual(journal.recall("favorite_color"), "gold")
        XCTAssertEqual(journal.recentRecaps(limit: 1), ["Your favorite color is gold now."])
    }
}

final class PlayerVaultTests: XCTestCase {
    func testCreateSlotUsesCalibrationBaseline() {
        var vault = PlayerVault(calibration: CalibrationProfile(childName: "Aria",
                                                                hintAggressiveness: .eager))
        let slot = vault.createSlot(pack: Fixtures.pack(), companion: Fixtures.clover,
                                    startSceneID: "fox_hollow")
        XCTAssertEqual(slot.companionID, "clover")
        XCTAssertEqual(slot.progress.chosenCompanionID, "clover")
        XCTAssertEqual(slot.difficulty.support.hintTier, 2)
        XCTAssertEqual(vault.slots.count, 1)
    }

    func testFavoritesAreSharedAcrossPlaythroughs() {
        var vault = PlayerVault(calibration: CalibrationProfile(childName: "Aria"))
        let emberSlot = vault.createSlot(pack: Fixtures.pack(), companion: Fixtures.ember,
                                         startSceneID: "fox_hollow")
        let cloverSlot = vault.createSlot(pack: Fixtures.pack(), companion: Fixtures.clover,
                                          startSceneID: "fox_hollow")

        vault.remember(MemoryEvent(kind: .favorite, key: "favorite_place", value: "river",
                                   spokenRecap: "You once said rivers are your favorite.",
                                   companionID: "ember"),
                       slotID: emberSlot.id)
        vault.remember(MemoryEvent(kind: .choice, key: "adventure_spirit", value: "brave",
                                   spokenRecap: "You bravely said yes to adventure.",
                                   companionID: "ember"),
                       slotID: emberSlot.id)

        // Clover's playthrough shares the favorite, not Ember's choices.
        let cloverMemories = vault.contextMemories(slotID: cloverSlot.id)
        XCTAssertTrue(cloverMemories.contains("You once said rivers are your favorite."))
        XCTAssertFalse(cloverMemories.contains("You bravely said yes to adventure."))

        let emberMemories = vault.contextMemories(slotID: emberSlot.id)
        XCTAssertTrue(emberMemories.contains("You bravely said yes to adventure."))
    }

    func testSaveLoadRoundTrip() throws {
        var vault = PlayerVault(calibration: CalibrationProfile(childName: "Aria", textScale: 3.0))
        vault.createSlot(pack: Fixtures.pack(), companion: Fixtures.petal, startSceneID: "fox_hollow")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try vault.save(to: url)
        let loaded = PlayerVault.load(from: url)
        XCTAssertEqual(loaded.calibration.textScale, 3.0)
        XCTAssertEqual(loaded.slots.first?.companionID, "petal")
    }

    func testLoadMissingFileReturnsFreshVault() {
        let vault = PlayerVault.load(from: URL(fileURLWithPath: "/nonexistent/vault.json"))
        XCTAssertEqual(vault.slots, [])
        XCTAssertEqual(vault.calibration, .standard)
    }
}
