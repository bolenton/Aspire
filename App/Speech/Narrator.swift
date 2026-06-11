import AVFoundation
import Foundation
import StoryEngine

/// Speaks everything aloud and publishes word-by-word progress so the giant
/// on-screen text can highlight along — the literacy-reinforcement loop.
final class Narrator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var currentText: String = ""
    @Published private(set) var highlightRange: NSRange?
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?
    var profile: CalibrationProfile = .standard

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, voice: VoiceSpec? = nil, onFinish: (() -> Void)? = nil) {
        stop()
        self.onFinish = onFinish
        currentText = text
        highlightRange = nil
        isSpeaking = true

        let utterance = AVSpeechUtterance(string: text)
        let spec = voice ?? VoiceSpec()
        if let identifier = spec.voiceIdentifier,
           let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = chosen
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: spec.languageCode)
        }
        utterance.rate = Float(min(max(Double(AVSpeechUtteranceDefaultSpeechRate) * spec.rate * 2 * profile.speechRate, 0.1), 0.7))
        utterance.pitchMultiplier = Float(min(max(spec.pitchMultiplier * profile.speechPitch, 0.5), 2.0))
        utterance.volume = Float(min(max(spec.volume * profile.narrationVolume, 0), 1))
        synthesizer.speak(utterance)
    }

    /// Replays a single tapped word — literacy feature.
    func speakWord(_ word: String, voice: VoiceSpec? = nil) {
        guard !isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: (voice ?? VoiceSpec()).languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.8
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        highlightRange = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.highlightRange = characterRange
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.highlightRange = nil
            let finish = self.onFinish
            self.onFinish = nil
            finish?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.highlightRange = nil
            self.onFinish = nil
        }
    }
}
