import Foundation

public enum MemoryKind: String, Codable, Sendable {
    case choice, favorite, discovery, questCompleted
}

public struct MemoryEvent: Codable, Equatable, Sendable {
    public var date: Date
    public var kind: MemoryKind
    public var key: String
    public var value: String
    /// How the companion phrases it later: "Last time you helped the fisherman."
    public var spokenRecap: String
    /// Which companion the memory was made with — stored now so a later
    /// "the companions know each other" upgrade is phrasing-only.
    public var companionID: String?

    public init(date: Date = Date(), kind: MemoryKind, key: String, value: String,
                spokenRecap: String, companionID: String? = nil) {
        self.date = date
        self.kind = kind
        self.key = key
        self.value = value
        self.spokenRecap = spokenRecap
        self.companionID = companionID
    }
}

/// Everything a companion remembers about her. Slot journals hold playthrough
/// memories; the vault's shared journal holds child-level facts (favorites).
public struct MemoryJournal: Codable, Equatable, Sendable {
    public private(set) var events: [MemoryEvent]

    public init(events: [MemoryEvent] = []) {
        self.events = events
    }

    public mutating func remember(_ event: MemoryEvent) {
        events.append(event)
    }

    /// Latest value for a key — favorites and choices can be updated over time.
    public func recall(_ key: String) -> String? {
        events.last { $0.key == key }?.value
    }

    /// Most recent memories, newest first, for the companion's context window.
    public func recentRecaps(limit: Int = 8) -> [String] {
        events.suffix(limit).reversed().map(\.spokenRecap)
    }

    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) -> MemoryJournal {
        guard let data = try? Data(contentsOf: url),
              let journal = try? JSONDecoder().decode(MemoryJournal.self, from: data) else {
            return MemoryJournal()
        }
        return journal
    }
}
