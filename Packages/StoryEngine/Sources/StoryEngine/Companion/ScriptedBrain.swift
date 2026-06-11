import Foundation

/// Deterministic fallback so the game is fully playable with no AI configured
/// at all — on a plane, on a school iPad, before any model is set up.
/// Every LLM provider is strictly an upgrade on top of this.
public struct ScriptedBrain: CompanionBrain {
    public init() {}

    public func reply(to utterance: String, context: CompanionContext) async throws -> String {
        let question = utterance.lowercased()

        if question.contains("who are you") || question.contains("your name") {
            return "I'm \(context.companion.name), your \(context.companion.species)! I go where you go, \(context.childName)."
        }
        if question.contains("where am i") || question.contains("where are we") {
            return context.sceneDescription
        }
        if question.contains("remember") || question.contains("last time") {
            if let memory = context.recentMemories.first {
                return "\(memory) I remember it well, \(context.childName)."
            }
            return "Our adventure is just beginning, \(context.childName). Soon we'll have so much to remember!"
        }
        if question.contains("what") && (question.contains("do") || question.contains("supposed")) {
            if let quest = context.questSummary {
                return quest
            }
            return "Right now we're just exploring, \(context.childName). Follow any sound that makes you curious!"
        }
        if question.contains("help") || question.contains("stuck") || question.contains("hint") {
            if let hint = context.currentHint {
                return hint
            }
            return "Stop and listen for a moment, \(context.childName). The world will tell you where to go."
        }
        if question.contains("can i go") || question.contains("can we go") {
            if let locked = context.lockedExplanations.first {
                return locked
            }
            return "We can try! Follow the sounds and I'll stay right beside you."
        }

        if let quest = context.questSummary {
            return "Hmm, I'm not sure about that one, \(context.childName). But remember — \(quest)"
        }
        return "Let's keep exploring, \(context.childName). I'm right here with you."
    }
}
