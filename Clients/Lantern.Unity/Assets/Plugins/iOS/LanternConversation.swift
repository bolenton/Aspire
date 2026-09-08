import Foundation
import FoundationModels

/// A fresh model session uses current game facts and a small, in-memory conversation window.
@objc(LanternConversationBridge)
final class LanternConversationBridge: NSObject {
    private static var pending: Task<Void, Never>?
    private static var activeRequest: Int32 = 0

    @objc static func availability() -> Int32 {
        guard #available(iOS 26.0, *) else { return 1 }
        switch SystemLanguageModel.default.availability {
        case .available:
            return SystemLanguageModel.default.supportsLocale(Locale(identifier: "en-US")) ? 0 : 5
        case .unavailable(.deviceNotEligible): return 2
        case .unavailable(.appleIntelligenceNotEnabled): return 3
        case .unavailable(.modelNotReady): return 4
        @unknown default: return 4
        }
    }

    @objc static func cancel(_ request: Int32) {
        guard request == activeRequest else { return }
        pending?.cancel()
        pending = nil
        activeRequest = 0
    }

    @objc static func respond(_ payload: String, request: Int32, completion: @escaping (String) -> Void) {
        pending?.cancel()
        activeRequest = request
        guard #available(iOS 26.0, *), availability() == 0,
              let data = payload.data(using: .utf8),
              let input = try? JSONDecoder().decode(Input.self, from: data) else {
            completion(envelope(request, status: "unavailable"))
            return
        }
        pending = Task { @MainActor in
            do {
                // Default Apple guardrails remain enabled. No model tools can change the world.
                let session = LanguageModelSession(instructions: input.instructions)
                let result = try await session.respond(to: input.prompt,
                    options: GenerationOptions(temperature: 0.65, maximumResponseTokens: 120))
                try Task.checkCancellation()
                guard activeRequest == request else { return }
                completion(envelope(request, status: "ready", text: result.content))
            } catch {
                guard !Task.isCancelled, activeRequest == request else { return }
                // Do not log or retain the child's utterance or the model transcript.
                completion(envelope(request, status: "fallback"))
            }
            if activeRequest == request { pending = nil; activeRequest = 0 }
        }
    }

    private struct Input: Decodable { let instructions: String; let prompt: String }
    private struct Output: Encodable { let request: Int32; let status: String; let text: String }
    private static func envelope(_ request: Int32, status: String, text: String = "") -> String {
        guard let data = try? JSONEncoder().encode(Output(request: request, status: status, text: text)) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
