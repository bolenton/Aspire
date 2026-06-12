import Combine
import Foundation

/// Single owner of duck state. Deterministic: voice always wins — whenever
/// the narrator speaks or the mic listens, the world pulls back so words are
/// never fought for. (`SpeechListener`'s `.duckOthers` session option only
/// ducks *other apps*; in-app ducking has to be done here.)
@MainActor
final class AudioMixCoordinator {
    /// Authored duck targets: ambience nearly disappears under voice, entity
    /// loops keep more level because they carry navigation information, and
    /// music sits in between.
    private static let ambienceDuck = 0.35
    private static let entityDuck = 0.40
    private static let musicDuck: Float = 0.5
    /// Fast attack so the voice is clear from its first word; slow release
    /// so the world swells back instead of snapping.
    private static let attack: TimeInterval = 0.25
    private static let release: TimeInterval = 1.0

    private(set) var isDucked = false

    private weak var audio: SpatialAudioEngine?
    private var speakingSubscription: AnyCancellable?
    private var narratorSpeaking = false
    private var listening = false

    func attach(narrator: Narrator, audio: SpatialAudioEngine) {
        self.audio = audio
        speakingSubscription = narrator.$isSpeaking
            .removeDuplicates()
            .sink { [weak self] speaking in
                self?.narratorSpeaking = speaking
                self?.applyDuckState()
            }
    }

    /// Pushed from GameView whenever the speech listener starts or stops.
    func setListening(_ listening: Bool) {
        self.listening = listening
        applyDuckState()
    }

    private func applyDuckState() {
        let shouldDuck = narratorSpeaking || listening
        guard shouldDuck != isDucked else { return }
        isDucked = shouldDuck
        let fade = shouldDuck ? Self.attack : Self.release
        audio?.setGroupGain(category: .ambience,
                            multiplier: shouldDuck ? Self.ambienceDuck : 1.0, fade: fade)
        audio?.setGroupGain(category: .entity,
                            multiplier: shouldDuck ? Self.entityDuck : 1.0, fade: fade)
        SoundBank.shared.setMusicDuck(shouldDuck ? Self.musicDuck : 1.0, fade: fade)
    }
}
