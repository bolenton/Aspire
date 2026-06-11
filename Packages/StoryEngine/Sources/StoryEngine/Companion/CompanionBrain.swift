import Foundation

/// Everything the companion is allowed to know when it speaks. The brain is
/// grounded in this context and nothing else — story canon stays authored.
public struct CompanionContext: Sendable {
    public var companion: Companion
    public var childName: String
    public var snapshot: WorldSnapshot
    public var recentMemories: [String]

    public init(companion: Companion, childName: String, snapshot: WorldSnapshot,
                recentMemories: [String] = []) {
        self.companion = companion
        self.childName = childName
        self.snapshot = snapshot
        self.recentMemories = recentMemories
    }

    public var sceneDescription: String { snapshot.sceneDescription }
    public var questSummary: String? { snapshot.activeQuest?.summary }
    public var currentHint: String? { snapshot.activeQuest?.currentHint }
    public var support: SupportLevel { snapshot.support }
    public var lockedExplanations: [String] {
        snapshot.perceived.compactMap { $0.isLocked ? $0.lockedExplanation : nil }
    }
}

/// Swappable AI providers all answer through this. Implementations include
/// ScriptedBrain (offline, deterministic), OpenAICompatibleBrain (Ollama,
/// LM Studio, llama.cpp server, cloud gateways), and app-layer brains for
/// Apple's on-device Foundation Model and bundled Gemma.
public protocol CompanionBrain: Sendable {
    func reply(to utterance: String, context: CompanionContext) async throws -> String
}

/// The safety contract for every LLM-backed brain, in one place.
public enum PromptBuilder {
    public static func systemPrompt(for context: CompanionContext) -> String {
        let companion = context.companion
        var lines: [String] = []
        lines.append("You are \(companion.name), a \(companion.species) companion in a gentle audio adventure for a child.")
        lines.append("Personality: \(companion.personality)")
        if !companion.quirks.isEmpty {
            lines.append("Your quirks: " + companion.quirks.joined(separator: "; "))
        }
        if !companion.speechStyle.catchphrases.isEmpty {
            lines.append("You sometimes say: " + companion.speechStyle.catchphrases.joined(separator: " / "))
        }
        for ability in companion.abilities {
            lines.append("You have a special sense: \(ability.name) — \(ability.spokenDescription)")
        }
        lines.append("The child's name is \(context.childName). She is nine years old and visually impaired; the game world reaches her mostly through sound.")
        lines.append("")
        lines.append("Rules you must always follow:")
        lines.append("- Stay in character as \(companion.name). Never mention being an AI, a model, or a game.")
        lines.append("- Speak in short, warm sentences that sound good read aloud. Two or three sentences at most.")
        lines.append("- Only talk about the people, places, and things listed below. Describe where things are using EXACTLY the directions and distances given — never invent places, directions, or distances.")
        lines.append("- If she asks about something not listed, say you can't hear or sense it from here, and gently suggest exploring or returning to the quest.")
        lines.append("- Never frighten, shame, or punish. Mistakes are part of exploring.")
        lines.append("- If she sounds stuck or upset, give the hint below.")
        lines.append("- If she asks something unrelated to the story (homework, the real world), answer kindly in one sentence, then return to the adventure.")
        lines.append("")
        lines.append("Where you both are: \(context.snapshot.sceneName). \(context.snapshot.sceneDescription)")
        if !context.snapshot.ambientSounds.isEmpty {
            lines.append("All around, you can hear: " + context.snapshot.ambientSounds.joined(separator: ", ") + ".")
        }
        if !context.snapshot.perceived.isEmpty {
            lines.append("What you can both perceive right now (mention ONLY these):")
            for entity in context.snapshot.perceived {
                lines.append(SnapshotPhrasing.promptLine(for: entity))
            }
        }
        if !context.snapshot.abilityFindings.isEmpty {
            lines.append("Your special sense has found: " + context.snapshot.abilityFindings.joined(separator: " | "))
        }
        if !context.snapshot.recentEvents.isEmpty {
            lines.append("Just happened: " + context.snapshot.recentEvents.joined(separator: " | "))
        }
        if let quest = context.snapshot.activeQuest {
            lines.append("Current quest: \(quest.summary)")
            lines.append("This step: \(quest.stepIntro)")
            lines.append("Hint you may give if she needs help: \(quest.currentHint)")
        }
        if !context.recentMemories.isEmpty {
            lines.append("Things you remember about your adventures together: " + context.recentMemories.joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }
}
