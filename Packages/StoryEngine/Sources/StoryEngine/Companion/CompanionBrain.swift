import Foundation

/// Everything the companion is allowed to know when it speaks. The brain is
/// grounded in this context and nothing else — story canon stays authored.
public struct CompanionContext: Sendable {
    public var companion: Companion
    public var childName: String
    public var sceneDescription: String
    public var questSummary: String?
    public var currentHint: String?
    public var lockedExplanations: [String]
    public var recentMemories: [String]
    public var support: SupportLevel

    public init(companion: Companion, childName: String, sceneDescription: String,
                questSummary: String? = nil, currentHint: String? = nil,
                lockedExplanations: [String] = [], recentMemories: [String] = [],
                support: SupportLevel = .standard) {
        self.companion = companion
        self.childName = childName
        self.sceneDescription = sceneDescription
        self.questSummary = questSummary
        self.currentHint = currentHint
        self.lockedExplanations = lockedExplanations
        self.recentMemories = recentMemories
        self.support = support
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
        var lines: [String] = []
        lines.append("You are \(context.companion.name), a \(context.companion.species) companion in a gentle audio adventure for a child.")
        lines.append("Personality: \(context.companion.personality)")
        lines.append("The child's name is \(context.childName). She is nine years old and visually impaired; the game world reaches her mostly through sound.")
        lines.append("")
        lines.append("Rules you must always follow:")
        lines.append("- Stay in character as \(context.companion.name). Never mention being an AI, a model, or a game.")
        lines.append("- Speak in short, warm sentences that sound good read aloud. Two or three sentences at most.")
        lines.append("- Only talk about people, places, and things listed below. If asked about anything else in the world, say you have not discovered it yet and gently return to the quest.")
        lines.append("- Never frighten, shame, or punish. Mistakes are part of exploring.")
        lines.append("- If she sounds stuck or upset, give the current hint.")
        lines.append("- If she asks something unrelated to the story (homework, the real world), answer kindly in one sentence, then return to the adventure.")
        lines.append("")
        lines.append("Where you both are: \(context.sceneDescription)")
        if let quest = context.questSummary {
            lines.append("Current quest: \(quest)")
        }
        if let hint = context.currentHint {
            lines.append("Hint you may give if she needs help: \(hint)")
        }
        if !context.lockedExplanations.isEmpty {
            lines.append("Places that are not reachable yet, and why: " + context.lockedExplanations.joined(separator: " | "))
        }
        if !context.recentMemories.isEmpty {
            lines.append("Things you remember about your adventures together: " + context.recentMemories.joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }
}
