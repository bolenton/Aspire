import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Talks to any endpoint that speaks the OpenAI chat-completions API:
/// Ollama or LM Studio on the home network, a llama.cpp server, or any
/// cloud gateway. Falls back to ScriptedBrain on any failure so the fox
/// never goes silent.
public struct OpenAICompatibleBrain: CompanionBrain {
    public var endpoint: URL
    public var model: String
    public var apiKey: String?
    public var fallback: ScriptedBrain

    public init(endpoint: URL, model: String, apiKey: String? = nil) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.fallback = ScriptedBrain()
    }

    struct ChatRequest: Encodable {
        struct Message: Codable {
            var role: String
            var content: String
        }
        var model: String
        var messages: [Message]
        var max_tokens: Int = 160
        var temperature: Double = 0.7
    }

    struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { var content: String }
            var message: Message
        }
        var choices: [Choice]
    }

    public func reply(to utterance: String, context: CompanionContext) async throws -> String {
        do {
            return try await directReply(to: utterance, context: context)
        } catch {
            return try await fallback.reply(to: utterance, context: context)
        }
    }

    /// The raw server call with NO fallback — errors surface to the caller.
    /// Used by the parent-settings connection test so a broken server is
    /// reported honestly instead of being silently covered for.
    public func directReply(to utterance: String, context: CompanionContext) async throws -> String {
        var request = URLRequest(url: endpoint.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        // Generous: a local model's first request may include a cold load.
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body = ChatRequest(model: model, messages: [
            .init(role: "system", content: PromptBuilder.systemPrompt(for: context)),
            .init(role: "user", content: utterance)
        ])
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            // Surface the server's own words ("model 'x' not found, try
            // pulling it first") — far more diagnosable than a bare code.
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAICompatibleBrain", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) from the server: \(body)"])
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw URLError(.cannotDecodeContentData)
        }
        let spoken = Self.stripReasoning(content)
        guard !spoken.isEmpty else {
            throw URLError(.cannotDecodeContentData)
        }
        return spoken
    }

    /// Reasoning models (Qwen3, DeepSeek-R1, ...) emit <think>...</think>
    /// blocks before the answer — internal monologue the companion must
    /// never read aloud to a child.
    public static func stripReasoning(_ content: String) -> String {
        var result = content
        while let open = result.range(of: "<think>"),
              let close = result.range(of: "</think>", range: open.upperBound..<result.endIndex) {
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        // An unterminated think block means the answer never started.
        if let open = result.range(of: "<think>") {
            result.removeSubrange(open.lowerBound..<result.endIndex)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
