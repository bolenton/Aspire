import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ElevenLabs neural TTS. Uses the with-timestamps endpoint so the reading
/// highlight tracks real word boundaries instead of estimates — the one
/// cloud feature AVSpeech can't approximate.
public struct ElevenLabsTTSProvider: TTSProvider {
    public var apiKey: String
    public var modelID: String
    public var baseURL: URL

    /// Playback speed baked into the synthesized audio (the app sets it from
    /// the child's speechRate). Clamped on set to ElevenLabs' supported
    /// 0.8…1.2 — values outside that range are rejected by the service.
    public var rate: Double {
        get { storedRate }
        set { storedRate = min(max(newValue, 0.8), 1.2) }
    }
    private var storedRate: Double = 1.0

    public var providerID: String { "elevenlabs" }

    public init(apiKey: String, modelID: String = "eleven_flash_v2_5",
                baseURL: URL = URL(string: "https://api.elevenlabs.io")!) {
        self.apiKey = apiKey
        self.modelID = modelID
        self.baseURL = baseURL
    }

    // MARK: - Wire formats

    /// ElevenLabs takes `output_format` as a query parameter on the
    /// with-timestamps endpoint, NOT a body field — a body `output_format`
    /// is silently ignored and the service falls back to its default codec.
    static let outputFormat = "mp3_44100_128"

    struct SynthesisRequest: Encodable {
        struct VoiceSettings: Encodable {
            var speed: Double
        }
        var text: String
        var model_id: String
        var voice_settings: VoiceSettings
    }

    struct SynthesisResponse: Decodable {
        struct Alignment: Decodable {
            var characters: [String]
            var character_start_times_seconds: [Double]
            var character_end_times_seconds: [Double]
        }
        var audio_base64: String
        var alignment: Alignment?
    }

    struct VoicesResponse: Decodable {
        struct Voice: Decodable {
            var voice_id: String
            var name: String
            var labels: [String: String?]?
        }
        var voices: [Voice]
    }

    // MARK: - Synthesis

    public func synthesize(text: String, voiceID: String) async throws -> TTSAudio {
        let request = try synthesisRequest(text: text, voiceID: voiceID)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response, data: data)
        return try Self.decodeSynthesis(data, text: text)
    }

    func synthesisRequest(text: String, voiceID: String) throws -> URLRequest {
        let url = baseURL
            .appendingPathComponent("v1/text-to-speech/\(voiceID)/with-timestamps")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "output_format", value: Self.outputFormat)]
        var request = URLRequest(url: components?.url ?? url)
        request.httpMethod = "POST"
        // Generous ceiling; callers enforce their own tighter latency budgets
        // and fall back to AVSpeech long before this fires.
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.httpBody = try JSONEncoder().encode(
            SynthesisRequest(text: text, model_id: modelID,
                             voice_settings: .init(speed: storedRate)))
        return request
    }

    static func decodeSynthesis(_ data: Data, text: String) throws -> TTSAudio {
        let decoded = try JSONDecoder().decode(SynthesisResponse.self, from: data)
        guard let audio = Data(base64Encoded: decoded.audio_base64) else {
            throw URLError(.cannotDecodeContentData)
        }
        var timings: [TTSWordTiming]?
        if let alignment = decoded.alignment {
            let mapped = TTSTimingMapper.wordTimings(
                text: text,
                characters: alignment.characters,
                starts: alignment.character_start_times_seconds,
                ends: alignment.character_end_times_seconds)
            // Empty means the mapper had nothing trustworthy; nil tells the
            // caller to estimate from the decoded audio's real duration.
            timings = mapped.isEmpty ? nil : mapped
        }
        return TTSAudio(data: audio, fileExtension: "mp3", wordTimings: timings)
    }

    // MARK: - Voice catalog

    public func listVoices() async throws -> [TTSVoice] {
        let request = voicesRequest()
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response, data: data)
        return try Self.decodeVoices(data)
    }

    func voicesRequest() -> URLRequest {
        let url = baseURL.appendingPathComponent("v2/voices")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "page_size", value: "100")]
        var request = URLRequest(url: components?.url ?? url)
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        return request
    }

    static func decodeVoices(_ data: Data) throws -> [TTSVoice] {
        let decoded = try JSONDecoder().decode(VoicesResponse.self, from: data)
        return decoded.voices.map { voice in
            // Labels ("accent: american, age: young") become the picker's
            // subtitle; sorted by key so the same voice always reads the same.
            let detail = (voice.labels ?? [:])
                .sorted { $0.key < $1.key }
                .compactMap { $0.value }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            return TTSVoice(id: voice.voice_id, name: voice.name,
                            detail: detail.isEmpty ? nil : detail)
        }
    }

    // MARK: - Errors

    /// Surface the service's own words ("voice not found", "quota exceeded")
    /// — far more diagnosable in the parent settings than a bare code. Same
    /// philosophy as OpenAICompatibleBrain.directReply.
    static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw NSError(domain: "ElevenLabsTTSProvider", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) from ElevenLabs: \(body)"])
        }
    }
}
