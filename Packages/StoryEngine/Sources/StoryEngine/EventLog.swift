import Foundation

public enum GameEventKind: String, Codable, Sendable {
    case sceneEntered, stepCompleted, itemCollected, flagSet, dialogueFinished,
         songCast, abilityRevealed, struggleDetected
}

public struct GameEvent: Codable, Equatable, Sendable {
    /// Seconds since session start — not wall-clock, so tests are
    /// deterministic.
    public var tick: TimeInterval
    public var kind: GameEventKind
    /// Pre-phrased for speech: "You just fixed the bridge!"
    public var spoken: String

    public init(tick: TimeInterval, kind: GameEventKind, spoken: String) {
        self.tick = tick
        self.kind = kind
        self.spoken = spoken
    }
}

/// Ring buffer of what just happened, feeding "WORLD RIGHT NOW" context and
/// "what happened?" answers.
public struct EventLog: Codable, Equatable, Sendable {
    public private(set) var events: [GameEvent]
    public let capacity: Int

    public init(capacity: Int = 12) {
        self.capacity = capacity
        self.events = []
    }

    public mutating func record(_ event: GameEvent) {
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    /// Newest first.
    public func recent(limit: Int = 5) -> [GameEvent] {
        Array(events.suffix(limit).reversed())
    }

    private enum CodingKeys: String, CodingKey {
        case events, capacity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        capacity = try c.decodeIfPresent(Int.self, forKey: .capacity) ?? 12
        events = try c.decodeIfPresent([GameEvent].self, forKey: .events) ?? []
    }
}
