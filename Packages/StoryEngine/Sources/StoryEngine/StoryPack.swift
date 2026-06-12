import Foundation

public enum StoryConventions {
    /// Entity id / dialogue speaker that resolves to the chosen companion.
    public static let companionPlaceholder = "@companion"
}

/// A complete, self-contained story (Forest Journey, Space Explorer, ...).
/// All narrative canon lives here, authored by humans. The companion AI may
/// only speak about what this data contains.
public struct StoryPack: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var version: Int
    /// Pack-local companions (community packs may ship their own).
    public var companions: [Companion]?
    /// Allowlist of shared-roster companion ids; nil = the whole roster.
    public var companionIDs: [String]?
    public var regions: [Region]
    public var quests: [Quest]
    public var dialogues: [DialogueNode]
    public var songSpells: [SongSpell]

    public init(id: String, title: String, version: Int,
                companions: [Companion]? = nil, companionIDs: [String]? = nil,
                regions: [Region] = [], quests: [Quest] = [],
                dialogues: [DialogueNode] = [], songSpells: [SongSpell] = []) {
        self.id = id
        self.title = title
        self.version = version
        self.companions = companions
        self.companionIDs = companionIDs
        self.regions = regions
        self.quests = quests
        self.dialogues = dialogues
        self.songSpells = songSpells
    }

    public static func load(from data: Data) throws -> StoryPack {
        try JSONDecoder().decode(StoryPack.self, from: data)
    }

    /// Shared roster filtered by this pack's allowlist, plus pack-local
    /// companions.
    public func availableCompanions(sharedRoster: CompanionRoster?) -> [Companion] {
        var result: [Companion] = []
        if let roster = sharedRoster {
            if let allowlist = companionIDs {
                result += allowlist.compactMap { roster.companion(id: $0) }
            } else {
                result += roster.companions
            }
        }
        if let local = companions {
            result += local.filter { local in !result.contains(where: { $0.id == local.id }) }
        }
        return result
    }

    public func scene(id: String) -> Scene? {
        for region in regions {
            if let scene = region.scenes.first(where: { $0.id == id }) { return scene }
        }
        return nil
    }

    public func quest(id: String) -> Quest? {
        quests.first { $0.id == id }
    }

    public func dialogue(id: String) -> DialogueNode? {
        dialogues.first { $0.id == id }
    }

    public func songSpell(id: String) -> SongSpell? {
        songSpells.first { $0.id == id }
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, version, companions, companionIDs, regions, quests,
             dialogues, songSpells
        case companion // legacy singular form
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        version = try c.decode(Int.self, forKey: .version)
        if let list = try c.decodeIfPresent([Companion].self, forKey: .companions) {
            companions = list
        } else if let legacy = try c.decodeIfPresent(Companion.self, forKey: .companion) {
            companions = [legacy]
        } else {
            companions = nil
        }
        companionIDs = try c.decodeIfPresent([String].self, forKey: .companionIDs)
        regions = try c.decodeIfPresent([Region].self, forKey: .regions) ?? []
        quests = try c.decodeIfPresent([Quest].self, forKey: .quests) ?? []
        dialogues = try c.decodeIfPresent([DialogueNode].self, forKey: .dialogues) ?? []
        songSpells = try c.decodeIfPresent([SongSpell].self, forKey: .songSpells) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(companions, forKey: .companions)
        try c.encodeIfPresent(companionIDs, forKey: .companionIDs)
        try c.encode(regions, forKey: .regions)
        try c.encode(quests, forKey: .quests)
        try c.encode(dialogues, forKey: .dialogues)
        try c.encode(songSpells, forKey: .songSpells)
    }
}

public struct Region: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// 1 = easiest. Each region introduces exactly one new mechanic.
    public var difficultyTier: Int
    public var newMechanic: String
    public var scenes: [Scene]

    public init(id: String, name: String, difficultyTier: Int, newMechanic: String, scenes: [Scene]) {
        self.id = id
        self.name = name
        self.difficultyTier = difficultyTier
        self.newMechanic = newMechanic
        self.scenes = scenes
    }
}

public struct Scene: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Spoken when the scene begins and whenever she asks "where am I?"
    public var spokenDescription: FlavoredText
    /// Visual biome for the 3D world ("forest", "cave", "castle", ...).
    /// Unknown or missing values fall back to the forest look.
    public var environment: String?
    public var ambience: [SoundSpec]
    public var entities: [Entity]

    public init(id: String, name: String, spokenDescription: FlavoredText,
                environment: String? = nil,
                ambience: [SoundSpec] = [], entities: [Entity] = []) {
        self.id = id
        self.name = name
        self.spokenDescription = spokenDescription
        self.environment = environment
        self.ambience = ambience
        self.entities = entities
    }
}

public enum EntityKind: String, Codable, Sendable {
    case companion, character, landmark, item, portal
}

public struct Entity: Codable, Equatable, Sendable {
    public var id: String
    public var kind: EntityKind
    public var name: String
    public var position: Vec3
    public var sound: SoundSpec?
    public var visual: VisualSpec?
    /// Dialogue node started when she reaches/taps this entity.
    public var dialogueID: String?
    /// Flag that must be set before this entity can be used (e.g. a portal
    /// behind "bridge_repaired"). The companion explains why when it is not.
    public var requiresFlag: String?
    public var lockedExplanation: FlavoredText?
    /// Portals only: the scene this leads to.
    public var destinationSceneID: String?
    /// Entity exists only in playthroughs with this companion.
    public var requiresCompanion: String?
    /// Hidden unless the chosen companion has this perception ability.
    public var requiresAbility: String?
    /// Spoken by the companion when its ability reveals this entity.
    public var senseLine: FlavoredText?
    /// What companions WITHOUT the ability perceive — an anonymous mystery
    /// that fuels replay ("Something rustles up high..."). When nil, the
    /// entity is entirely invisible to them.
    public var hiddenTease: String?

    public init(id: String, kind: EntityKind, name: String, position: Vec3,
                sound: SoundSpec? = nil, visual: VisualSpec? = nil,
                dialogueID: String? = nil, requiresFlag: String? = nil,
                lockedExplanation: FlavoredText? = nil,
                destinationSceneID: String? = nil,
                requiresCompanion: String? = nil, requiresAbility: String? = nil,
                senseLine: FlavoredText? = nil, hiddenTease: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.position = position
        self.sound = sound
        self.visual = visual
        self.dialogueID = dialogueID
        self.requiresFlag = requiresFlag
        self.lockedExplanation = lockedExplanation
        self.destinationSceneID = destinationSceneID
        self.requiresCompanion = requiresCompanion
        self.requiresAbility = requiresAbility
        self.senseLine = senseLine
        self.hiddenTease = hiddenTease
    }
}

/// How an entity exists in the current playthrough, after companion and
/// ability gates are applied. Single source of truth for rendering,
/// snapshots, and the scripted brain.
public struct ResolvedEntity: Equatable, Sendable {
    public var entity: Entity
    public var revealedByAbilityID: String?
    /// Present only as a mystery — name and sound must not be exposed.
    public var isAnonymousTease: Bool

    public init(entity: Entity, revealedByAbilityID: String? = nil, isAnonymousTease: Bool = false) {
        self.entity = entity
        self.revealedByAbilityID = revealedByAbilityID
        self.isAnonymousTease = isAnonymousTease
    }
}

public extension Scene {
    /// Entities that exist for this companion:
    /// - requiresCompanion mismatches are excluded entirely
    /// - ability-gated entities are revealed (with the ability id) or, when
    ///   they carry a hiddenTease, included anonymously; otherwise excluded
    func activeEntities(companion: Companion) -> [ResolvedEntity] {
        entities.compactMap { entity in
            if let required = entity.requiresCompanion, required != companion.id {
                return nil
            }
            if let ability = entity.requiresAbility {
                if companion.hasAbility(ability) {
                    return ResolvedEntity(entity: entity, revealedByAbilityID: ability)
                }
                if entity.hiddenTease != nil {
                    return ResolvedEntity(entity: entity, isAnonymousTease: true)
                }
                return nil
            }
            return ResolvedEntity(entity: entity)
        }
    }
}

public struct Vec3: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public func distance(to other: Vec3) -> Double {
        let dx = other.x - x, dy = other.y - y, dz = other.z - z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}

public struct SoundSpec: Codable, Equatable, Sendable {
    public var asset: String
    public var loops: Bool
    public var volume: Double
    /// Distance at which the sound reaches full volume / fades to silence.
    public var nearRadius: Double
    public var farRadius: Double
    /// How the sound is described in speech: "flowing water", "creaking wood".
    public var spokenDescription: String?

    public init(asset: String, loops: Bool = true, volume: Double = 1.0,
                nearRadius: Double = 1.0, farRadius: Double = 30.0,
                spokenDescription: String? = nil) {
        self.asset = asset
        self.loops = loops
        self.volume = volume
        self.nearRadius = nearRadius
        self.farRadius = farRadius
        self.spokenDescription = spokenDescription
    }
}

public struct VisualSpec: Codable, Equatable, Sendable {
    public var shape: String
    public var colorHex: String
    public var scale: Double
    /// 0...2, multiplied by the support level's glow boost at render time.
    public var glow: Double

    public init(shape: String, colorHex: String, scale: Double = 1.0, glow: Double = 1.0) {
        self.shape = shape
        self.colorHex = colorHex
        self.scale = scale
        self.glow = glow
    }
}

public enum QuestGoal: String, Codable, Sendable {
    case reach, collect, talk, song
}

public struct Quest: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// What the companion says when she asks "what am I supposed to do?"
    public var spokenSummary: FlavoredText
    public var steps: [QuestStep]
    /// Companion-exclusive side quest.
    public var requiresCompanion: String?
    /// Quest only becomes available once this flag is set.
    public var requiresFlag: String?

    public init(id: String, title: String, spokenSummary: FlavoredText,
                steps: [QuestStep], requiresCompanion: String? = nil,
                requiresFlag: String? = nil) {
        self.id = id
        self.title = title
        self.spokenSummary = spokenSummary
        self.steps = steps
        self.requiresCompanion = requiresCompanion
        self.requiresFlag = requiresFlag
    }
}

public struct QuestStep: Codable, Equatable, Sendable {
    public var id: String
    public var goal: QuestGoal
    public var targetEntityID: String
    public var songSpellID: String?
    /// Spoken once when the step begins.
    public var intro: FlavoredText
    /// Spoken when the step completes. Never punishing — the world is safe.
    public var celebration: FlavoredText
    /// Index 0 = gentle nudge, last = fully explicit. The support level's
    /// hintTier picks the entry.
    public var hintLadder: [FlavoredText]
    /// Flag set when this step completes (drives requiresFlag gates).
    public var setsFlag: String?

    public init(id: String, goal: QuestGoal, targetEntityID: String,
                songSpellID: String? = nil, intro: FlavoredText,
                celebration: FlavoredText, hintLadder: [FlavoredText],
                setsFlag: String? = nil) {
        self.id = id
        self.goal = goal
        self.targetEntityID = targetEntityID
        self.songSpellID = songSpellID
        self.intro = intro
        self.celebration = celebration
        self.hintLadder = hintLadder
        self.setsFlag = setsFlag
    }
}

public struct DialogueNode: Codable, Equatable, Sendable {
    public var id: String
    /// "@companion" resolves to the chosen companion's name and voice.
    public var speaker: String
    public var line: FlavoredText
    public var choices: [DialogueChoice]

    public init(id: String, speaker: String, line: FlavoredText, choices: [DialogueChoice] = []) {
        self.id = id
        self.speaker = speaker
        self.line = line
        self.choices = choices
    }

    public func resolvedSpeaker(companion: Companion) -> String {
        speaker == StoryConventions.companionPlaceholder ? companion.name : speaker
    }
}

public struct DialogueChoice: Codable, Equatable, Sendable {
    public var id: String
    public var text: FlavoredText
    public var nextDialogueID: String?
    /// When set, the choice is written into the MemoryJournal so the
    /// companion can bring it up later.
    public var memoryKey: String?
    public var memoryValue: String?
    /// Choice offered only in playthroughs with this companion.
    public var requiresCompanion: String?

    public init(id: String, text: FlavoredText, nextDialogueID: String? = nil,
                memoryKey: String? = nil, memoryValue: String? = nil,
                requiresCompanion: String? = nil) {
        self.id = id
        self.text = text
        self.nextDialogueID = nextDialogueID
        self.memoryKey = memoryKey
        self.memoryValue = memoryValue
        self.requiresCompanion = requiresCompanion
    }
}

public enum SolfegeNote: String, Codable, Sendable, CaseIterable {
    case `do`, re, mi, fa, sol, la, ti
}

public struct SongSpell: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// The full melody ladder, easiest prefix first. How much of it the
    /// player must sing back scales with the support level's challenge.
    public var notes: [SolfegeNote]
    public var tempo: Int

    public init(id: String, name: String, notes: [SolfegeNote], tempo: Int = 90) {
        self.id = id
        self.name = name
        self.notes = notes
        self.tempo = tempo
    }

    /// Challenge 1 asks for the first three notes; each level adds one,
    /// clamped to the authored melody. Complexity rises gently as she does.
    public func notes(forChallenge challenge: Int) -> [SolfegeNote] {
        let count = min(notes.count, max(1, 2 + challenge))
        return Array(notes.prefix(count))
    }
}
