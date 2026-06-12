import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import StoryEngine

/// Golden tests for both providers' wire formats — request encoding and
/// response decoding against captured/synthetic JSON. NO live network calls:
/// the request builders and decoders are pure, so the contract is testable
/// on every CI run, offline.
final class ElevenLabsTTSProviderEncodingTests: XCTestCase {
    func testSynthesisRequestEncoding() throws {
        var provider = ElevenLabsTTSProvider(apiKey: "xi-secret")
        provider.rate = 1.05
        let request = try provider.synthesisRequest(text: "Hello little fox!", voiceID: "voice123")

        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.elevenlabs.io/v1/text-to-speech/voice123/with-timestamps")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "xi-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 15)

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["text"] as? String, "Hello little fox!")
        XCTAssertEqual(json["model_id"] as? String, "eleven_flash_v2_5")
        XCTAssertEqual(json["output_format"] as? String, "mp3_44100_128")
        let settings = try XCTUnwrap(json["voice_settings"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(settings["speed"] as? Double), 1.05, accuracy: 1e-9)
    }

    func testModelIDIsParentOverridable() throws {
        let provider = ElevenLabsTTSProvider(apiKey: "k", modelID: "eleven_multilingual_v2")
        let request = try provider.synthesisRequest(text: "Hi", voiceID: "v")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["model_id"] as? String, "eleven_multilingual_v2")
    }

    func testRateClampsToSupportedRange() {
        var provider = ElevenLabsTTSProvider(apiKey: "k")
        XCTAssertEqual(provider.rate, 1.0)
        provider.rate = 2.0
        XCTAssertEqual(provider.rate, 1.2)
        provider.rate = 0.1
        XCTAssertEqual(provider.rate, 0.8)
    }

    func testSynthesisResponseDecoding() throws {
        let audioBytes = Data([0x49, 0x44, 0x33, 0x04, 0x00])
        let json = """
        {
          "audio_base64": "\(audioBytes.base64EncodedString())",
          "alignment": {
            "characters": ["H", "i", " ", "🦊"],
            "character_start_times_seconds": [0.0, 0.1, 0.2, 0.3],
            "character_end_times_seconds": [0.1, 0.2, 0.3, 0.6]
          }
        }
        """
        let audio = try ElevenLabsTTSProvider.decodeSynthesis(Data(json.utf8), text: "Hi 🦊")

        XCTAssertEqual(audio.data, audioBytes)
        XCTAssertEqual(audio.fileExtension, "mp3")
        let timings = try XCTUnwrap(audio.wordTimings)
        XCTAssertEqual(timings.count, 2)
        XCTAssertEqual(timings[0].location, 0)
        XCTAssertEqual(timings[0].length, 2)
        XCTAssertEqual(timings[0].start, 0.0, accuracy: 1e-9)
        XCTAssertEqual(timings[0].duration, 0.2, accuracy: 1e-9)
        XCTAssertEqual(timings[1].location, 3)
        XCTAssertEqual(timings[1].length, 2)
        XCTAssertEqual(timings[1].start, 0.3, accuracy: 1e-9)
        XCTAssertEqual(timings[1].duration, 0.3, accuracy: 1e-9)
    }

    func testMissingAlignmentLeavesTimingsNil() throws {
        let json = """
        {"audio_base64": "\(Data([0x01]).base64EncodedString())"}
        """
        let audio = try ElevenLabsTTSProvider.decodeSynthesis(Data(json.utf8), text: "Hi")
        XCTAssertNil(audio.wordTimings)
    }

    func testInvalidBase64Throws() {
        let json = """
        {"audio_base64": "not base64!!!"}
        """
        XCTAssertThrowsError(
            try ElevenLabsTTSProvider.decodeSynthesis(Data(json.utf8), text: "Hi"))
    }

    func testVoicesRequest() {
        let provider = ElevenLabsTTSProvider(apiKey: "xi-secret")
        let request = provider.voicesRequest()
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.elevenlabs.io/v2/voices?page_size=100")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "xi-secret")
    }

    func testVoicesResponseDecoding() throws {
        let json = """
        {
          "voices": [
            {"voice_id": "abc", "name": "Rachel",
             "labels": {"age": "young", "accent": "american", "gender": null}},
            {"voice_id": "def", "name": "Bear", "labels": {}},
            {"voice_id": "ghi", "name": "Plain"}
          ]
        }
        """
        let voices = try ElevenLabsTTSProvider.decodeVoices(Data(json.utf8))
        XCTAssertEqual(voices, [
            // Labels sorted by key, nulls dropped — deterministic subtitles.
            TTSVoice(id: "abc", name: "Rachel", detail: "american, young"),
            TTSVoice(id: "def", name: "Bear", detail: nil),
            TTSVoice(id: "ghi", name: "Plain", detail: nil)
        ])
    }

    func testErrorIncludesResponseBodyExcerpt() throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: XCTUnwrap(URL(string: "https://api.elevenlabs.io")),
            statusCode: 401, httpVersion: nil, headerFields: nil))
        let body = Data(#"{"detail": "invalid api key"}"#.utf8)
        XCTAssertThrowsError(try ElevenLabsTTSProvider.checkStatus(response, data: body)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.code, 401)
            XCTAssertTrue(nsError.localizedDescription.contains("invalid api key"),
                          nsError.localizedDescription)
        }
    }
}

final class OpenAISpeechTTSProviderEncodingTests: XCTestCase {
    private let base = URL(string: "http://192.168.1.20:8080")!

    func testSpeechRequestEncoding() throws {
        let provider = OpenAISpeechTTSProvider(baseURL: base, apiKey: "sk-test")
        let request = try provider.speechRequest(text: "Onward, brave explorer!", voiceID: "coral")

        XCTAssertEqual(request.url?.absoluteString,
                       "http://192.168.1.20:8080/v1/audio/speech")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini-tts")
        XCTAssertEqual(json["input"] as? String, "Onward, brave explorer!")
        XCTAssertEqual(json["voice"] as? String, "coral")
        XCTAssertEqual(json["response_format"] as? String, "mp3")
    }

    func testNoAuthHeaderForKeylessLocalServer() throws {
        let provider = OpenAISpeechTTSProvider(baseURL: base, apiKey: nil)
        let request = try provider.speechRequest(text: "Hi", voiceID: "anyName")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testCustomModelEncodes() throws {
        let provider = OpenAISpeechTTSProvider(baseURL: base, apiKey: nil, model: "tts-1-hd")
        let request = try provider.speechRequest(text: "Hi", voiceID: "v")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "tts-1-hd")
    }

    func testRawBytesBecomeAudioWithoutTimings() {
        let bytes = Data([0xFF, 0xFB, 0x90, 0x00])
        let audio = OpenAISpeechTTSProvider.audio(from: bytes)
        XCTAssertEqual(audio.data, bytes)
        XCTAssertEqual(audio.fileExtension, "mp3")
        XCTAssertNil(audio.wordTimings, "no timestamps from this API — caller estimates")
    }

    func testBuiltInVoiceCatalog() async throws {
        let voices = try await OpenAISpeechTTSProvider(baseURL: base, apiKey: nil).listVoices()
        XCTAssertEqual(voices.map(\.id), ["alloy", "ash", "ballad", "coral", "echo",
                                          "fable", "nova", "onyx", "sage", "shimmer", "verse"])
        XCTAssertEqual(voices.first?.name, "Alloy")
    }
}
