import Foundation

public enum ContrastTheme: String, Codable, Sendable, CaseIterable {
    /// Glowing light shapes on near-black (default).
    case lightOnDark
    /// Dark bold shapes on bright background — some eye conditions prefer
    /// this polarity.
    case darkOnLight
    /// Yellow-on-black maximum contrast.
    case highContrastYellow
}

public enum HintAggressiveness: String, Codable, Sendable, CaseIterable {
    /// Subtle cues, hints only on request, more patience before helping.
    case gentle
    case standard
    /// Strong cues and explicit hints early.
    case eager

    public var baseSupport: SupportLevel {
        switch self {
        case .gentle:   return SupportLevel(audioCueGain: 1.0, glowBoost: 1.0, hintTier: 0, challenge: 1)
        case .standard: return SupportLevel(audioCueGain: 1.3, glowBoost: 1.3, hintTier: 1, challenge: 1)
        case .eager:    return SupportLevel(audioCueGain: 1.6, glowBoost: 1.6, hintTier: 2, challenge: 1)
        }
    }

    public var struggleDuration: TimeInterval {
        switch self {
        case .gentle:   return 120
        case .standard: return 90
        case .eager:    return 60
        }
    }
}

/// Per-child comfort settings, chosen in the spoken first-launch wizard and
/// re-tunable behind the parent gate. Adaptive difficulty moves relative to
/// this baseline and never drops support below it.
public struct CalibrationProfile: Codable, Equatable, Sendable {
    public var childName: String
    /// 1.0...4.0 multiplier on the already-large base text.
    public var textScale: Double
    public var contrastTheme: ContrastTheme
    /// Multipliers applied on top of each companion's VoiceSpec.
    public var speechRate: Double
    public var speechPitch: Double
    public var hintAggressiveness: HintAggressiveness
    public var worldVolume: Double
    public var narrationVolume: Double
    public var musicVolume: Double
    public var tapToTalkEnabled: Bool

    public init(childName: String = "", textScale: Double = 2.0,
                contrastTheme: ContrastTheme = .lightOnDark,
                speechRate: Double = 1.0, speechPitch: Double = 1.0,
                hintAggressiveness: HintAggressiveness = .standard,
                worldVolume: Double = 1.0, narrationVolume: Double = 1.0,
                musicVolume: Double = 0.8, tapToTalkEnabled: Bool = true) {
        self.childName = childName
        self.textScale = textScale
        self.contrastTheme = contrastTheme
        self.speechRate = speechRate
        self.speechPitch = speechPitch
        self.hintAggressiveness = hintAggressiveness
        self.worldVolume = worldVolume
        self.narrationVolume = narrationVolume
        self.musicVolume = musicVolume
        self.tapToTalkEnabled = tapToTalkEnabled
    }

    public static let standard = CalibrationProfile()
}
