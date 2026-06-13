import Foundation

/// How her hero looks: pure data the app's voxel builder interprets.
/// Every option carries a spoken name because the designer is a listening
/// ceremony first — she picks by ear, and vision confirms.
public struct AvatarSpec: Codable, Equatable, Sendable {
    public enum BodyStyle: String, Codable, CaseIterable, Sendable {
        case boy, girl

        public var spokenName: String {
            switch self {
            case .boy: return "a boy"
            case .girl: return "a girl"
            }
        }
    }

    public enum HairStyle: String, Codable, CaseIterable, Sendable {
        case short, long, curly, braids, bald

        public var spokenName: String {
            switch self {
            case .short: return "short hair"
            case .long: return "long hair"
            case .curly: return "curly hair"
            case .braids: return "two braids"
            case .bald: return "no hair at all"
            }
        }
    }

    public var body: BodyStyle
    public var skinToneID: String
    public var hairStyle: HairStyle
    public var hairColorID: String
    public var outfitColorID: String

    public init(body: BodyStyle = .girl,
                skinToneID: String = "warm",
                hairStyle: HairStyle = .short,
                hairColorID: String = "brown",
                outfitColorID: String = "ember") {
        self.body = body
        self.skinToneID = skinToneID
        self.hairStyle = hairStyle
        self.hairColorID = hairColorID
        self.outfitColorID = outfitColorID
    }

    /// Forward-compatible decoding: any field a future version adds (or an
    /// old save lacks) falls back to its default instead of failing the
    /// whole vault load — the same contract that protects every save file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AvatarSpec()
        body = try container.decodeIfPresent(BodyStyle.self, forKey: .body) ?? defaults.body
        skinToneID = try container.decodeIfPresent(String.self, forKey: .skinToneID) ?? defaults.skinToneID
        hairStyle = try container.decodeIfPresent(HairStyle.self, forKey: .hairStyle) ?? defaults.hairStyle
        hairColorID = try container.decodeIfPresent(String.self, forKey: .hairColorID) ?? defaults.hairColorID
        outfitColorID = try container.decodeIfPresent(String.self, forKey: .outfitColorID) ?? defaults.outfitColorID
    }

    /// What the companion (or freeze-and-explain) can say about her hero.
    public var spokenDescription: String {
        let skin = AvatarPalette.skinTone(id: skinToneID).spokenName
        let outfit = AvatarPalette.outfitColor(id: outfitColorID).spokenName
        if hairStyle == .bald {
            return "\(body.spokenName) with \(skin) skin, \(hairStyle.spokenName), and \(outfit) clothes"
        }
        let hair = AvatarPalette.hairColor(id: hairColorID).spokenName
        return "\(body.spokenName) with \(skin) skin, \(hair) \(hairStyle.spokenName), and \(outfit) clothes"
    }
}

/// One pickable color: a stable id, a name the narrator can say, and a hex
/// the renderer interprets. IDs are persisted; names and hexes can be tuned
/// later without touching anyone's save.
public struct AvatarColorOption: Equatable, Sendable, Identifiable {
    public let id: String
    public let spokenName: String
    public let hex: String

    public init(id: String, spokenName: String, hex: String) {
        self.id = id
        self.spokenName = spokenName
        self.hex = hex
    }
}

/// The authored palettes. Unknown ids resolve to the first option so a save
/// from a future version still renders something sensible.
public enum AvatarPalette {
    public static let skinTones: [AvatarColorOption] = [
        AvatarColorOption(id: "fair", spokenName: "fair", hex: "#FFE2C8"),
        AvatarColorOption(id: "peach", spokenName: "peach", hex: "#F8D0A8"),
        AvatarColorOption(id: "warm", spokenName: "warm golden", hex: "#EDB98A"),
        AvatarColorOption(id: "tan", spokenName: "tan", hex: "#C68642"),
        AvatarColorOption(id: "brown", spokenName: "brown", hex: "#8D5524"),
        AvatarColorOption(id: "deep", spokenName: "deep brown", hex: "#5C3A21"),
    ]

    public static let hairColors: [AvatarColorOption] = [
        AvatarColorOption(id: "black", spokenName: "black", hex: "#1F1B18"),
        AvatarColorOption(id: "brown", spokenName: "brown", hex: "#5C4023"),
        AvatarColorOption(id: "chestnut", spokenName: "chestnut", hex: "#8B5A2B"),
        AvatarColorOption(id: "golden", spokenName: "golden", hex: "#E8C04C"),
        AvatarColorOption(id: "red", spokenName: "fiery red", hex: "#C4502B"),
        AvatarColorOption(id: "silver", spokenName: "silver", hex: "#C9CDD1"),
        AvatarColorOption(id: "pink", spokenName: "bubblegum pink", hex: "#E86FA4"),
    ]

    public static let outfitColors: [AvatarColorOption] = [
        AvatarColorOption(id: "ember", spokenName: "ember red", hex: "#D9523F"),
        AvatarColorOption(id: "forest", spokenName: "forest green", hex: "#3E7C4F"),
        AvatarColorOption(id: "sky", spokenName: "sky blue", hex: "#3F7FD9"),
        AvatarColorOption(id: "sunny", spokenName: "sunny yellow", hex: "#E8C04C"),
        AvatarColorOption(id: "royal", spokenName: "royal purple", hex: "#7A4FD9"),
        AvatarColorOption(id: "rose", spokenName: "rose pink", hex: "#D95F9E"),
    ]

    public static func skinTone(id: String) -> AvatarColorOption {
        skinTones.first { $0.id == id } ?? skinTones[0]
    }

    public static func hairColor(id: String) -> AvatarColorOption {
        hairColors.first { $0.id == id } ?? hairColors[0]
    }

    public static func outfitColor(id: String) -> AvatarColorOption {
        outfitColors.first { $0.id == id } ?? outfitColors[0]
    }
}
