import Foundation

/// A complete, self-contained story (Forest Journey, Space Explorer, ...).
/// All narrative canon lives here, authored by humans. The companion AI may
/// only speak about what this data contains.
public struct StoryPack: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var version: Int
    public var companion: Companion
    public var regions: [Region]
    public var quests: [Quest]
    public var dialogues: [DialogueNode]
    public var songSpells: [SongSpell]

    public init(id: String, title: String, version: Int, companion: Companion,
                regions: [Region], quests: [Quest], dialogues: [DialogueNode],
                songSpells: [SongSpell]) {
        self.id = id
        self.title = title
        self.version = version
        self.companion = companion
        self.regions = regions
        self.quests = quests
        self.dialogues = dialogues
        self.songSpells = songSpells
    }

    public static func load(from data: Data) throws -> StoryPack {
        try JSONDecoder().decode(StoryPack.self, from: data)
    }
}

public struct Companion: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var species: String
    public var personality: String

    public init(id: String, name: String, species: String, personality: String) {
        self.id = id
        self.name = name
        self.species = species
        self.personality = personality
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
    public var spokenDescription: String
    public var ambience: [SoundSpec]
    public var entities: [Entity]

    public init(id: String, name: String, spokenDescription: String,
                ambience: [SoundSpec], entities: [Entity]) {
        self.id = id
        self.name = name
        self.spokenDescription = spokenDescription
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
    /// Flag that must be true before this entity can be used (e.g. a portal
    /// behind "bridge_repaired"). The companion explains why when it is not.
    public var requiresFlag: String?
    public var lockedExplanation: String?

    public init(id: String, kind: EntityKind, name: String, position: Vec3,
                sound: SoundSpec? = nil, visual: VisualSpec? = nil,
                dialogueID: String? = nil, requiresFlag: String? = nil,
                lockedExplanation: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.position = position
        self.sound = sound
        self.visual = visual
        self.dialogueID = dialogueID
        self.requiresFlag = requiresFlag
        self.lockedExplanation = lockedExplanation
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
}

public struct SoundSpec: Codable, Equatable, Sendable {
    public var asset: String
    public var loops: Bool
    public var volume: Double
    /// Distance at which the sound reaches full volume / fades to silence.
    public var nearRadius: Double
    public var farRadius: Double

    public init(asset: String, loops: Bool = true, volume: Double = 1.0,
                nearRadius: Double = 1.0, farRadius: Double = 30.0) {
        self.asset = asset
        self.loops = loops
        self.volume = volume
        self.nearRadius = nearRadius
        self.farRadius = farRadius
    }
}

public struct VisualSpec: Codable, Equatable, Sendable {
    public var shape: String
    public var colorHex: String
    public var scale: Double
    /// 0...2, multiplied by DifficultyDirector glow boost at render time.
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
    public var spokenSummary: String
    public var steps: [QuestStep]

    public init(id: String, title: String, spokenSummary: String, steps: [QuestStep]) {
        self.id = id
        self.title = title
        self.spokenSummary = spokenSummary
        self.steps = steps
    }
}

public struct QuestStep: Codable, Equatable, Sendable {
    public var id: String
    public var goal: QuestGoal
    public var targetEntityID: String
    public var songSpellID: String?
    /// Spoken once when the step begins.
    public var intro: String
    /// Spoken when the step completes. Never punishing — the world is safe.
    public var celebration: String
    /// Index 0 = gentle nudge, last = fully explicit. DifficultyDirector
    /// picks the tier.
    public var hintLadder: [String]
    /// Flag set when this step completes (drives requiresFlag gates).
    public var setsFlag: String?

    public init(id: String, goal: QuestGoal, targetEntityID: String,
                songSpellID: String? = nil, intro: String, celebration: String,
                hintLadder: [String], setsFlag: String? = nil) {
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
    public var speaker: String
    public var line: String
    public var choices: [DialogueChoice]

    public init(id: String, speaker: String, line: String, choices: [DialogueChoice] = []) {
        self.id = id
        self.speaker = speaker
        self.line = line
        self.choices = choices
    }
}

public struct DialogueChoice: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var nextDialogueID: String?
    /// When set, the choice is written into the MemoryJournal so the
    /// companion can bring it up later.
    public var memoryKey: String?
    public var memoryValue: String?

    public init(id: String, text: String, nextDialogueID: String? = nil,
                memoryKey: String? = nil, memoryValue: String? = nil) {
        self.id = id
        self.text = text
        self.nextDialogueID = nextDialogueID
        self.memoryKey = memoryKey
        self.memoryValue = memoryValue
    }
}

public enum SolfegeNote: String, Codable, Sendable {
    case `do`, re, mi, fa, sol, la, ti
}

public struct SongSpell: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var notes: [SolfegeNote]
    public var tempo: Int

    public init(id: String, name: String, notes: [SolfegeNote], tempo: Int = 90) {
        self.id = id
        self.name = name
        self.notes = notes
        self.tempo = tempo
    }
}
