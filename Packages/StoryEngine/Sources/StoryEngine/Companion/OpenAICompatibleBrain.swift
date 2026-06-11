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
            return try await complete(utterance: utterance, context: context)
        } catch {
            return try await fallback.reply(to: utterance, context: context)
        }
    }

    func complete(utterance: String, context: CompanionContext) async throws -> String {
        var request = URLRequest(url: endpoint.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 12
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
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw URLError(.cannotDecodeContentData)
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
