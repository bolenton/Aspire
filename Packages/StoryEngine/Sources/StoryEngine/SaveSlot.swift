import Foundation

/// One playthrough: a story pack experienced with one companion. Replaying
/// with a different companion is a new slot — the old adventure stays intact.
public struct SaveSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var storyPackID: String
    public var companionID: String
    public var progress: GameProgress
    public var difficulty: DifficultyDirector
    /// Playthrough memories: choices, discoveries, quest outcomes.
    public var journal: MemoryJournal
    public var createdAt: Date
    public var lastPlayedAt: Date

    public init(id: String = UUID().uuidString, storyPackID: String,
                companionID: String, progress: GameProgress,
                difficulty: DifficultyDirector, journal: MemoryJournal = MemoryJournal(),
                createdAt: Date = Date(), lastPlayedAt: Date = Date()) {
        self.id = id
        self.storyPackID = storyPackID
        self.companionID = companionID
        self.progress = progress
        self.difficulty = difficulty
        self.journal = journal
        self.createdAt = createdAt
        self.lastPlayedAt = lastPlayedAt
    }
}

/// Everything saved on the device: the child's calibration, child-level
/// memories that cross playthroughs (favorites), and all save slots.
public struct PlayerVault: Codable, Equatable, Sendable {
    public var calibration: CalibrationProfile
    /// Facts about the child herself — favorites — phrased neutrally when a
    /// different companion recalls them.
    public var sharedJournal: MemoryJournal
    public var slots: [SaveSlot]

    public init(calibration: CalibrationProfile = .standard,
                sharedJournal: MemoryJournal = MemoryJournal(),
                slots: [SaveSlot] = []) {
        self.calibration = calibration
        self.sharedJournal = sharedJournal
        self.slots = slots
    }

    public var childName: String { calibration.childName }

    @discardableResult
    public mutating func createSlot(pack: StoryPack, companion: Companion,
                                    startSceneID: String) -> SaveSlot {
        let progress = GameProgress(storyPackID: pack.id, currentSceneID: startSceneID,
                                    chosenCompanionID: companion.id)
        let slot = SaveSlot(storyPackID: pack.id, companionID: companion.id,
                            progress: progress,
                            difficulty: DifficultyDirector(profile: calibration))
        slots.append(slot)
        return slot
    }

    public func slot(id: String) -> SaveSlot? {
        slots.first { $0.id == id }
    }

    public mutating func update(_ slot: SaveSlot) {
        guard let index = slots.firstIndex(where: { $0.id == slot.id }) else {
            slots.append(slot)
            return
        }
        var updated = slot
        updated.lastPlayedAt = Date()
        slots[index] = updated
    }

    /// Remembers an event into the right journal: favorites are about the
    /// child and cross playthroughs; everything else stays with the slot.
    public mutating func remember(_ event: MemoryEvent, slotID: String) {
        if event.kind == .favorite {
            sharedJournal.remember(event)
            return
        }
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        slots[index].journal.remember(event)
    }

    /// Memories for the companion's context: slot recents merged with shared
    /// favorites, newest first, capped.
    public func contextMemories(slotID: String, limit: Int = 8) -> [String] {
        let slotEvents = slot(id: slotID)?.journal.events ?? []
        let merged = (slotEvents + sharedJournal.events).sorted { $0.date > $1.date }
        return merged.prefix(limit).map(\.spokenRecap)
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) -> PlayerVault {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let vault = try? decoder.decode(PlayerVault.self, from: data) else {
            return PlayerVault()
        }
        return vault
    }
}
