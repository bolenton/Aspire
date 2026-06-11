import Foundation

public struct PlayerPose: Codable, Equatable, Sendable {
    public var position: Vec3
    /// Degrees, 0 = facing -Z (RealityKit forward), positive turns right.
    public var headingDegrees: Double

    public init(position: Vec3 = Vec3(x: 0, y: 0, z: 0), headingDegrees: Double = 0) {
        self.position = position
        self.headingDegrees = headingDegrees
    }
}

public enum CompassDirection8: String, Codable, Sendable, CaseIterable {
    case ahead, aheadRight, right, behindRight, behind, behindLeft, left, aheadLeft

    public var spoken: String {
        switch self {
        case .ahead:       return "straight ahead"
        case .aheadRight:  return "ahead on your right"
        case .right:       return "to your right"
        case .behindRight: return "behind you, on the right"
        case .behind:      return "behind you"
        case .behindLeft:  return "behind you, on the left"
        case .left:        return "to your left"
        case .aheadLeft:   return "ahead on your left"
        }
    }

    /// Relative bearing in degrees (0 = dead ahead, positive = clockwise),
    /// any range, mapped into eight 45° sectors.
    public static func from(relativeBearing degrees: Double) -> CompassDirection8 {
        var normalized = degrees.truncatingRemainder(dividingBy: 360)
        if normalized < -180 { normalized += 360 }
        if normalized > 180 { normalized -= 360 }
        switch normalized {
        case -22.5..<22.5:    return .ahead
        case 22.5..<67.5:     return .aheadRight
        case 67.5..<112.5:    return .right
        case 112.5..<157.5:   return .behindRight
        case -67.5 ..< -22.5: return .aheadLeft
        case -112.5 ..< -67.5: return .left
        case -157.5 ..< -112.5: return .behindLeft
        default:              return .behind
        }
    }
}

public enum ElevationBand: String, Codable, Sendable {
    case level, above, below

    public var spokenSuffix: String? {
        switch self {
        case .level: return nil
        case .above: return "up high"
        case .below: return "down low"
        }
    }
}

/// All direction/distance wording lives here so it is tuned (and tested) in
/// exactly one place.
public enum SnapshotPhrasing {
    public static func spokenDistance(_ meters: Double) -> String {
        switch meters {
        case ..<1.5: return "right here"
        case ..<4:   return "a few steps away"
        case ..<10:  return "a short walk away"
        case ..<25:  return "about \(Int(meters.rounded())) big steps away"
        default:     return "far away"
        }
    }

    /// One compact line per entity for the LLM's WORLD RIGHT NOW block.
    public static func promptLine(for entity: PerceivedEntity) -> String {
        var line = "- \(entity.name): \(entity.direction.spoken)"
        if let suffix = entity.elevation.spokenSuffix { line += ", \(suffix)" }
        line += ", \(entity.spokenDistance)"
        if let sound = entity.soundDescription { line += " — you can hear \(sound)" }
        if entity.isQuestTarget { line += " (QUEST TARGET)" }
        if entity.isLocked, let reason = entity.lockedExplanation { line += " — NOT REACHABLE YET: \(reason)" }
        if entity.isAnonymousTease, let tease = entity.teaseLine { line += " — a mystery: \(tease)" }
        return line
    }
}

/// One thing the player can currently perceive, with everything the
/// companion is allowed to say about it.
public struct PerceivedEntity: Codable, Equatable, Sendable {
    public var entityID: String
    public var name: String
    public var kind: EntityKind
    public var direction: CompassDirection8
    public var elevation: ElevationBand
    public var distanceMeters: Double
    public var spokenDistance: String
    public var isAudible: Bool
    public var soundDescription: String?
    public var isQuestTarget: Bool
    public var isLocked: Bool
    public var lockedExplanation: String?
    public var revealedByAbilityID: String?
    public var isAnonymousTease: Bool
    /// The mystery wording for ability-gated secrets this companion can't
    /// sense ("Something rustles up high..."). Never the entity's real name.
    public var teaseLine: String?

    public init(entityID: String, name: String, kind: EntityKind,
                direction: CompassDirection8, elevation: ElevationBand,
                distanceMeters: Double, spokenDistance: String, isAudible: Bool,
                soundDescription: String? = nil, isQuestTarget: Bool = false,
                isLocked: Bool = false, lockedExplanation: String? = nil,
                revealedByAbilityID: String? = nil, isAnonymousTease: Bool = false,
                teaseLine: String? = nil) {
        self.entityID = entityID
        self.name = name
        self.kind = kind
        self.direction = direction
        self.elevation = elevation
        self.distanceMeters = distanceMeters
        self.spokenDistance = spokenDistance
        self.isAudible = isAudible
        self.soundDescription = soundDescription
        self.isQuestTarget = isQuestTarget
        self.isLocked = isLocked
        self.lockedExplanation = lockedExplanation
        self.revealedByAbilityID = revealedByAbilityID
        self.isAnonymousTease = isAnonymousTease
        self.teaseLine = teaseLine
    }
}

public struct QuestSnapshot: Codable, Equatable, Sendable {
    public var title: String
    public var summary: String
    public var stepIntro: String
    public var currentHint: String
    public var goal: QuestGoal
    public var targetName: String?
    public var targetDirection: CompassDirection8?

    public init(title: String, summary: String, stepIntro: String,
                currentHint: String, goal: QuestGoal,
                targetName: String? = nil, targetDirection: CompassDirection8? = nil) {
        self.title = title
        self.summary = summary
        self.stepIntro = stepIntro
        self.currentHint = currentHint
        self.goal = goal
        self.targetName = targetName
        self.targetDirection = targetDirection
    }
}

/// Everything the companion knows about this exact moment. Codable and
/// Equatable on purpose: golden-fixture tests on Linux, plus a free in-app
/// debug overlay ("what does the companion know right now?").
public struct WorldSnapshot: Codable, Equatable, Sendable {
    public var tick: TimeInterval
    public var sceneID: String
    public var sceneName: String
    public var sceneDescription: String
    public var pose: PlayerPose
    /// Sorted: quest target, ability-revealed, then nearest; capped.
    public var perceived: [PerceivedEntity]
    /// Spoken descriptions of the scene's ambient sounds ("wind in leaves").
    public var ambientSounds: [String]
    public var activeQuest: QuestSnapshot?
    /// Newest first, capped.
    public var recentEvents: [String]
    public var support: SupportLevel
    /// Resolved senseLines of currently ability-revealed entities.
    public var abilityFindings: [String]

    public init(tick: TimeInterval, sceneID: String, sceneName: String,
                sceneDescription: String, pose: PlayerPose,
                perceived: [PerceivedEntity], ambientSounds: [String] = [],
                activeQuest: QuestSnapshot? = nil, recentEvents: [String] = [],
                support: SupportLevel = .standard, abilityFindings: [String] = []) {
        self.tick = tick
        self.sceneID = sceneID
        self.sceneName = sceneName
        self.sceneDescription = sceneDescription
        self.pose = pose
        self.perceived = perceived
        self.ambientSounds = ambientSounds
        self.activeQuest = activeQuest
        self.recentEvents = recentEvents
        self.support = support
        self.abilityFindings = abilityFindings
    }
}
