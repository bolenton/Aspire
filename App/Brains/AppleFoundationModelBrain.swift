import Foundation
import StoryEngine

#if canImport(FoundationModels)
import FoundationModels

/// Apple's on-device language model (Apple Intelligence hardware, iOS 26+):
/// free, private, no setup, works offline. Grounded by the same
/// PromptBuilder safety contract as every other brain.
@available(iOS 26.0, *)
struct AppleFoundationModelBrain: CompanionBrain {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    func reply(to utterance: String, context: CompanionContext) async throws -> String {
        // A fresh session per question: the world snapshot in the system
        // prompt changes with every utterance, so statelessness is correct.
        let session = LanguageModelSession(instructions: PromptBuilder.systemPrompt(for: context))
        let response = try await session.respond(to: utterance)
        return response.content
    }
}
#endif

/// Resolves the on-device model across SDKs and hardware: nil when built
/// with an older Xcode SDK, on pre-iOS-26 systems, or on devices without
/// Apple Intelligence (like an A16 iPad).
enum OnDeviceBrain {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleFoundationModelBrain.isAvailable
        }
        #endif
        return false
    }

    static func make() -> (any CompanionBrain)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleFoundationModelBrain.isAvailable {
            return SafeBrain(primary: AppleFoundationModelBrain())
        }
        #endif
        return nil
    }
}

/// Wraps any brain so the companion can never go silent: any failure falls
/// through to the deterministic scripted storyteller mid-conversation.
struct SafeBrain: CompanionBrain {
    let primary: any CompanionBrain

    func reply(to utterance: String, context: CompanionContext) async throws -> String {
        do {
            return try await primary.reply(to: utterance, context: context)
        } catch {
            return try await ScriptedBrain().reply(to: utterance, context: context)
        }
    }
}
