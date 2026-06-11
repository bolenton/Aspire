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

    public static let standard = HintAggressiveness.standard.baseSupport

    public init(audioCueGain: Double, glowBoost: Double, hintTier: Int, challenge: Int) {
        self.audioCueGain = audioCueGain
        self.glowBoost = glowBoost
        self.hintTier = hintTier
        self.challenge = challenge
    }
}

/// Deterministic adaptive difficulty. Rules are intentionally legible:
/// predictability is itself an accessibility feature. An LLM may *phrase*
/// hints, but never decides how much help she gets. Support adapts relative
/// to the calibrated baseline and never drops below it.
public struct DifficultyDirector: Codable, Equatable, Sendable {
    public private(set) var support: SupportLevel
    public private(set) var baseline: SupportLevel
    private var recent: [TelemetrySample]
    private var windowSize: Int { 5 }

    /// A sample this slow counts as a struggle even when it succeeded.
    public var struggleDuration: TimeInterval

    public init(baseline: SupportLevel = .standard, struggleDuration: TimeInterval = 90) {
        self.baseline = baseline
        self.support = baseline
        self.struggleDuration = struggleDuration
        self.recent = []
    }

    public init(profile: CalibrationProfile) {
        self.init(baseline: profile.hintAggressiveness.baseSupport,
                  struggleDuration: profile.hintAggressiveness.struggleDuration)
    }

    /// Latest struggle-escalation, if record() just raised support — callers
    /// can log a struggleDetected event so the companion offers help.
    public private(set) var lastChangeWasEscalation: Bool = false

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
        let streak = recent.count >= 3 && recent.suffix(3).allSatisfy { !isStruggle($0) }
        lastChangeWasEscalation = false

        if struggles >= 2 {
            support.audioCueGain = min(2.0, support.audioCueGain + 0.2)
            support.glowBoost = min(2.0, support.glowBoost + 0.2)
            support.hintTier = min(2, support.hintTier + 1)
            support.challenge = max(1, support.challenge - 1)
            lastChangeWasEscalation = true
        } else if streak {
            support.audioCueGain = max(baseline.audioCueGain, support.audioCueGain - 0.1)
            support.glowBoost = max(baseline.glowBoost, support.glowBoost - 0.1)
            support.hintTier = max(baseline.hintTier, support.hintTier - 1)
            support.challenge = min(5, support.challenge + 1)
        }
    }

    /// The hint to speak for a step at the current support level, in the
    /// chosen companion's flavor.
    public func hint(for step: QuestStep, companionID: String?) -> String {
        guard !step.hintLadder.isEmpty else { return step.intro.resolved(for: companionID) }
        let index = min(support.hintTier, step.hintLadder.count - 1)
        return step.hintLadder[index].resolved(for: companionID)
    }
}
