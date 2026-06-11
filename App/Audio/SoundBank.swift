import AVFoundation
import Foundation
import StoryEngine

/// Plays non-spatial sounds: earcons, celebrations, companion cues, and
/// solfège notes. Missing assets are skipped gracefully, same contract as
/// the spatial engine.
final class SoundBank {
    static let shared = SoundBank()

    private var urlCache: [String: URL?] = [:]
    private var activePlayers: [AVAudioPlayer] = []

    func play(_ assetName: String, volume: Float = 1.0) {
        guard let url = url(for: assetName),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = volume
        activePlayers.removeAll { !$0.isPlaying }
        activePlayers.append(player)
        player.play()
    }

    func playNote(_ note: SolfegeNote, volume: Float = 1.0) {
        play("note_\(note.rawValue).wav", volume: volume)
    }

    /// A companion's named cue ("greeting", "celebrate", "senseAlert", ...).
    func playCue(_ cue: String, companion: Companion, volume: Float = 1.0) {
        guard let asset = companion.sounds[cue] else { return }
        play(asset, volume: volume)
    }

    private func url(for assetName: String) -> URL? {
        if let cached = urlCache[assetName] { return cached }
        let base = (assetName as NSString).deletingPathExtension
        let ext = (assetName as NSString).pathExtension
        let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Assets/Audio")
            ?? Bundle.main.url(forResource: base, withExtension: ext)
        urlCache[assetName] = url
        return url
    }
}
