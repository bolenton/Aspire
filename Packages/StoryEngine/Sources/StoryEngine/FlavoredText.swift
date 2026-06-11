import Foundation

/// The universal per-companion variation primitive. Every spoken string in
/// the content model can be either a bare JSON string (same for everyone)
/// or an object with per-companion overrides:
///
///     "Cross the old bridge."
///     {"base": "Cross the old bridge.",
///      "byCompanion": {"ember": "I smell adventure across that bridge!"}}
public struct FlavoredText: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    public var base: String
    public var byCompanion: [String: String]?

    public init(_ base: String, byCompanion: [String: String]? = nil) {
        self.base = base
        self.byCompanion = byCompanion
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public func resolved(for companionID: String?) -> String {
        guard let companionID, let override = byCompanion?[companionID] else { return base }
        return override
    }

    private enum CodingKeys: String, CodingKey {
        case base, byCompanion
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let plain = try? single.decode(String.self) {
            self.base = plain
            self.byCompanion = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.base = try container.decode(String.self, forKey: .base)
        self.byCompanion = try container.decodeIfPresent([String: String].self, forKey: .byCompanion)
    }

    public func encode(to encoder: Encoder) throws {
        if let byCompanion, !byCompanion.isEmpty {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(base, forKey: .base)
            try container.encode(byCompanion, forKey: .byCompanion)
        } else {
            var container = encoder.singleValueContainer()
            try container.encode(base)
        }
    }
}
