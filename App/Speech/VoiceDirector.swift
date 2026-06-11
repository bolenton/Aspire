import AVFoundation
import Foundation
import StoryEngine

/// Resolves the actual synthesis voice each companion speaks with:
/// parent override (per companion, behind the gate) > auto-assigned best
/// installed voice > the roster's authored identifier. Auto-assignment
/// ranks installed voices premium > enhanced > default and gives each
/// companion a distinct one, so downloading better voices in iOS Settings
/// upgrades the whole cast with zero configuration.
final class VoiceDirector {
    static let shared = VoiceDirector()

    private let defaults = UserDefaults.standard
    private var autoAssignments: [String: String] = [:]

    private func overrideKey(_ companionID: String) -> String {
        "voice.override.\(companionID)"
    }

    func overrideIdentifier(for companionID: String) -> String? {
        defaults.string(forKey: overrideKey(companionID))
    }

    func setOverride(_ identifier: String?, for companionID: String) {
        if let identifier, !identifier.isEmpty {
            defaults.set(identifier, forKey: overrideKey(companionID))
        } else {
            defaults.removeObject(forKey: overrideKey(companionID))
        }
    }

    /// English voices, best first. Personal Voices rank above everything —
    /// a parent recorded that one on purpose.
    func rankedVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { score($0) > score($1) }
    }

    private func score(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score: Int
        switch voice.quality {
        case .premium: score = 300
        case .enhanced: score = 200
        default: score = 100
        }
        if isPersonal(voice) { score += 1000 }
        return score
    }

    func isPersonal(_ voice: AVSpeechSynthesisVoice) -> Bool {
        if #available(iOS 17.0, *) {
            return voice.voiceTraits.contains(.isPersonalVoice)
        }
        return false
    }

    /// Distinct top voices per companion. Personal Voices are never
    /// auto-assigned — dad's voice joins the cast only when a parent picks it.
    func configureAutoVoices(companionIDs: [String]) {
        let candidates = rankedVoices().filter { !isPersonal($0) }
        guard !candidates.isEmpty else { return }
        let upgraded = candidates.filter { $0.quality != .default }
        let pool = upgraded.isEmpty ? candidates : upgraded
        for (index, companionID) in companionIDs.enumerated() {
            autoAssignments[companionID] = pool[index % pool.count].identifier
        }
    }

    /// The roster spec upgraded with the best concrete voice available.
    func spec(for companion: Companion) -> VoiceSpec {
        var spec = companion.voice
        if let identifier = overrideIdentifier(for: companion.id)
            ?? autoAssignments[companion.id]
            ?? spec.voiceIdentifier {
            spec.voiceIdentifier = identifier
        }
        return spec
    }

    func displayName(_ voice: AVSpeechSynthesisVoice) -> String {
        if isPersonal(voice) {
            return "\(voice.name) — Personal Voice"
        }
        switch voice.quality {
        case .premium: return "\(voice.name) (Premium)"
        case .enhanced: return "\(voice.name) (Enhanced)"
        default: return voice.name
        }
    }

    var personalVoiceAuthorized: Bool {
        if #available(iOS 17.0, *) {
            return AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .authorized
        }
        return false
    }

    func requestPersonalVoiceAccess(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
        } else {
            completion(false)
        }
    }
}

extension Companion {
    /// What this companion actually sounds like on this device, right now.
    var resolvedVoice: VoiceSpec {
        VoiceDirector.shared.spec(for: self)
    }
}
