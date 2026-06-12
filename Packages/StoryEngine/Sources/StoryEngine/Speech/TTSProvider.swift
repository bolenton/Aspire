import Foundation

/// A voice offered by a TTS service, shaped for direct use in a settings
/// picker — `id` is what the provider's API wants back, `name`/`detail`
/// are what a parent reads.
public struct TTSVoice: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var detail: String?

    public init(id: String, name: String, detail: String? = nil) {
        self.id = id
        self.name = name
        self.detail = detail
    }
}

/// One spoken word's slice of the synthesized audio. Offsets are UTF-16 so
/// they map 1:1 to NSRange — the reading highlight and the tappable word
/// buttons in NarrationTextView both speak NSRange.
public struct TTSWordTiming: Codable, Equatable, Sendable {
    /// UTF-16 offsets into the synthesized text (maps 1:1 to NSRange).
    public var location: Int
    public var length: Int
    public var start: TimeInterval
    public var duration: TimeInterval

    public init(location: Int, length: Int, start: TimeInterval, duration: TimeInterval) {
        self.location = location
        self.length = length
        self.start = start
        self.duration = duration
    }
}

/// The product of one synthesis call: encoded audio plus, when the service
/// provides them, word timings for the reading highlight.
public struct TTSAudio: Sendable {
    public var data: Data
    public var fileExtension: String
    /// nil → the caller estimates timings from the decoded audio duration
    /// (TTSTimingMapper.estimate), so the highlight never goes dark.
    public var wordTimings: [TTSWordTiming]?

    public init(data: Data, fileExtension: String, wordTimings: [TTSWordTiming]? = nil) {
        self.data = data
        self.fileExtension = fileExtension
        self.wordTimings = wordTimings
    }
}

/// Swappable neural-TTS services all synthesize through this. The app
/// treats every provider as an optional upgrade over AVSpeech — any error
/// or latency overrun simply means the local voice speaks instead.
public protocol TTSProvider: Sendable {
    /// Stable string baked into disk-cache keys; never reuse across services.
    var providerID: String { get }
    func synthesize(text: String, voiceID: String) async throws -> TTSAudio
    func listVoices() async throws -> [TTSVoice]
}
