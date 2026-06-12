import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Talks to any endpoint that speaks the OpenAI audio/speech API: OpenAI
/// itself or a local server (LocalAI, AllTalk, ...) on the home network —
/// the same offline-friendly reach as OpenAICompatibleBrain. The API
/// returns raw audio with no timestamps, so word timings are always
/// estimated by the caller.
public struct OpenAISpeechTTSProvider: TTSProvider {
    public var baseURL: URL
    public var apiKey: String?
    public var model: String

    public var providerID: String { "openai-speech" }

    public init(baseURL: URL, apiKey: String?, model: String = "gpt-4o-mini-tts") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    /// OpenAI's built-in voices. Local servers accept arbitrary voice names,
    /// so the settings UI also offers free-text entry — this list is a
    /// starting point, not a constraint.
    public static let builtInVoices: [TTSVoice] = [
        "alloy", "ash", "ballad", "coral", "echo", "fable",
        "nova", "onyx", "sage", "shimmer", "verse"
    ].map { TTSVoice(id: $0, name: $0.capitalized) }

    struct SpeechRequest: Encodable {
        var model: String
        var input: String
        var voice: String
        var response_format: String = "mp3"
    }

    public func synthesize(text: String, voiceID: String) async throws -> TTSAudio {
        let request = try speechRequest(text: text, voiceID: voiceID)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            // Surface the server's own words — same diagnosability
            // philosophy as OpenAICompatibleBrain.directReply.
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAISpeechTTSProvider", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) from the speech server: \(body)"])
        }
        return Self.audio(from: data)
    }

    func speechRequest(text: String, voiceID: String) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/audio/speech"))
        request.httpMethod = "POST"
        // Generous ceiling; callers enforce their own tighter latency budgets
        // and fall back to AVSpeech long before this fires.
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            SpeechRequest(model: model, input: text, voice: voiceID))
        return request
    }

    /// The success body IS the audio — no envelope to decode. Timings stay
    /// nil so the caller estimates them from the real playback duration.
    static func audio(from data: Data) -> TTSAudio {
        TTSAudio(data: data, fileExtension: "mp3", wordTimings: nil)
    }

    public func listVoices() async throws -> [TTSVoice] {
        Self.builtInVoices
    }
}
