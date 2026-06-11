import Foundation

/// TTS parameters for a companion's voice. The app layer maps these onto
/// AVSpeechUtterance / AVSpeechSynthesisVoice.
public struct VoiceSpec: Codable, Equatable, Sendable {
    public var voiceIdentifier: String?
    public var languageCode: String
    /// 0...1 nominal speaking rate, multiplied by the calibration profile.
    public var rate: Double
    /// 0.5...2.0
    public var pitchMultiplier: Double
    public var volume: Double

    public init(voiceIdentifier: String? = nil, languageCode: String = "en-US",
                rate: Double = 0.5, pitchMultiplier: Double = 1.0, volume: Double = 1.0) {
        self.voiceIdentifier = voiceIdentifier
        self.languageCode = languageCode
        self.rate = rate
        self.pitchMultiplier = pitchMultiplier
        self.volume = volume
    }
}

/// A companion's unique sense. Content gates secrets on `id`; the scripted
/// brain matches questions on `senseVerb` ("what do you smell?").
public struct PerceptionAbility: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var spokenDescription: String
    public var senseVerb: String
    /// When set, multiplies how far this companion can hear sound sources
    /// (Clover's Bunny Ears). Data-driven so new abilities need no engine code.
    public var audibleRangeMultiplier: Double?

    public init(id: String, name: String, spokenDescription: String,
                senseVerb: String, audibleRangeMultiplier: Double? = nil) {
        self.id = id
        self.name = name
        self.spokenDescription = spokenDescription
        self.senseVerb = senseVerb
        self.audibleRangeMultiplier = audibleRangeMultiplier
    }
}

/// How a companion talks: its exclamation, catchphrases, and per-intent
/// phrase templates for the scripted brain. Missing intent keys fall back to
/// built-in defaults, so a minimal companion entry is fully playable.
public struct SpeechStyle: Codable, Equatable, Sendable {
    public var exclamation: String
    public var catchphrases: [String]
    /// Intent key -> phrase templates with {childName}, {companionName},
    /// {exclamation}, {scene}, {quest}, {hint}, {list}, {target},
    /// {direction}, {distance} placeholders.
    public var templates: [String: [String]]

    public init(exclamation: String = "Oh!", catchphrases: [String] = [],
                templates: [String: [String]] = [:]) {
        self.exclamation = exclamation
        self.catchphrases = catchphrases
        self.templates = templates
    }
}

public struct Companion: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var species: String
    public var personality: String
    /// Spoken on the companion-choice screen, in this companion's voice.
    public var introduction: String
    public var quirks: [String]
    public var voice: VoiceSpec
    /// Cue name -> audio asset. Well-known cues: "greeting", "celebrate",
    /// "senseAlert", "ambientLoop", "thinking".
    public var sounds: [String: String]
    public var abilities: [PerceptionAbility]
    public var speechStyle: SpeechStyle

    public init(id: String, name: String, species: String, personality: String,
                introduction: String? = nil, quirks: [String] = [],
                voice: VoiceSpec = VoiceSpec(), sounds: [String: String] = [:],
                abilities: [PerceptionAbility] = [], speechStyle: SpeechStyle = SpeechStyle()) {
        self.id = id
        self.name = name
        self.species = species
        self.personality = personality
        self.introduction = introduction ?? "Hi! I'm \(name) the \(species)."
        self.quirks = quirks
        self.voice = voice
        self.sounds = sounds
        self.abilities = abilities
        self.speechStyle = speechStyle
    }

    public func hasAbility(_ abilityID: String) -> Bool {
        abilities.contains { $0.id == abilityID }
    }

    /// Largest hearing boost any of this companion's abilities grants.
    public var audibleRangeMultiplier: Double {
        abilities.compactMap(\.audibleRangeMultiplier).max() ?? 1.0
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, species, personality, introduction, quirks, voice,
             sounds, abilities, speechStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let name = try c.decode(String.self, forKey: .name)
        let species = try c.decode(String.self, forKey: .species)
        self.id = id
        self.name = name
        self.species = species
        self.personality = try c.decode(String.self, forKey: .personality)
        self.introduction = try c.decodeIfPresent(String.self, forKey: .introduction)
            ?? "Hi! I'm \(name) the \(species)."
        self.quirks = try c.decodeIfPresent([String].self, forKey: .quirks) ?? []
        self.voice = try c.decodeIfPresent(VoiceSpec.self, forKey: .voice) ?? VoiceSpec()
        self.sounds = try c.decodeIfPresent([String: String].self, forKey: .sounds) ?? [:]
        self.abilities = try c.decodeIfPresent([PerceptionAbility].self, forKey: .abilities) ?? []
        self.speechStyle = try c.decodeIfPresent(SpeechStyle.self, forKey: .speechStyle) ?? SpeechStyle()
    }
}

/// The shared companion roster (StoryPacks/Companions/roster.json). Story
/// packs may filter it via `companionIDs` and/or add pack-local companions.
public struct CompanionRoster: Codable, Equatable, Sendable {
    public var version: Int
    public var companions: [Companion]

    public init(version: Int = 1, companions: [Companion]) {
        self.version = version
        self.companions = companions
    }

    public static func load(from data: Data) throws -> CompanionRoster {
        try JSONDecoder().decode(CompanionRoster.self, from: data)
    }

    public func companion(id: String) -> Companion? {
        companions.first { $0.id == id }
    }
}
