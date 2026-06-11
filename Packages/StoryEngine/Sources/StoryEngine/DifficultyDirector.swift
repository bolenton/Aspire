import Foundation

public enum ActivityKind: String, Codable, Sendable {
    case navigation, puzzle, song, dialogue
}

public struct TelemetrySample: Codable, Equatable, Sendable {
    public var kind: ActivityKind
    public var succeeded: Bool
    public var duration: TimeInterval
    public var hintsUsed: Int

    public init(kind: ActivityKind, succeeded: Bool, duration: TimeInterval, hintsUsed: Int = 0) {
        self.kind = kind
        self.succeeded = succeeded
        self.duration = duration
        self.hintsUsed = hintsUsed
    }
}

/// How much help the game gives right now. All values move smoothly and
/// only ever change *support* — there is no punishment in this world.
public struct SupportLevel: Codable, Equatable, Sendable {
    /// Multiplier on guidance-sound volume, 1.0...2.0.
    public var audioCueGain: Double
    /// Multiplier on glow of important objects, 1.0...2.0.
    public var glowBoost: Double
    /// Index into each step's hintLadder: 0 gentle ... 2 fully explicit.
    public var hintTier: Int
    /// 1...5, drives song-spell length and puzzle richness.
    public var challenge: Int

    public static let standard = SupportLevel(audioCueGain: 1.3, glowBoost: 1.3, hintTier: 1, challenge: 1)

    public init(audioCueGain: Double, glowBoost: Double, hintTier: Int, challenge: Int) {
        self.audioCueGain = audioCueGain
        self.glowBoost = glowBoost
        self.hintTier = hintTier
        self.challenge = challenge
    }
}

/// Deterministic adaptive difficulty. Rules are intentionally legible:
/// predictability is itself an accessibility feature. An LLM may *phrase*
/// hints, but never decides how much help she gets.
public struct DifficultyDirector: Codable, Equatable, Sendable {
    public private(set) var support: SupportLevel
    private var recent: [TelemetrySample]
    private let windowSize = 5

    /// A sample this slow counts as a struggle even when it succeeded.
    public var struggleDuration: TimeInterval = 90

    public init(support: SupportLevel = .standard) {
        self.support = support
        self.recent = []
    }

    public mutating func record(_ sample: TelemetrySample) {
        recent.append(sample)
        if recent.count > windowSize { recent.removeFirst(recent.count - windowSize) }
        adjust()
    }

    private func isStruggle(_ s: TelemetrySample) -> Bool {
        !s.succeeded || s.duration > struggleDuration || s.hintsUsed >= 2
    }

    private mutating func adjust() {
        let struggles = recent.suffix(2).filter(isStruggle).count
        let streak = recent.suffix(3).allSatisfy { !isStruggle($0) } && recent.count >= 3

        if struggles >= 2 {
            support.audioCueGain = min(2.0, support.audioCueGain + 0.2)
            support.glowBoost = min(2.0, support.glowBoost + 0.2)
            support.hintTier = min(2, support.hintTier + 1)
            support.challenge = max(1, support.challenge - 1)
        } else if streak {
            support.audioCueGain = max(1.0, support.audioCueGain - 0.1)
            support.glowBoost = max(1.0, support.glowBoost - 0.1)
            support.hintTier = max(0, support.hintTier - 1)
            support.challenge = min(5, support.challenge + 1)
        }
    }

    /// The hint to speak for a step at the current support level.
    public func hint(for step: QuestStep) -> String {
        guard !step.hintLadder.isEmpty else { return step.intro }
        let index = min(support.hintTier, step.hintLadder.count - 1)
        return step.hintLadder[index]
    }
}
