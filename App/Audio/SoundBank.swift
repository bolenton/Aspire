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

    // MARK: - Music (one track at a time, on its own channel)

    private var musicPlayer: AVAudioPlayer?
    /// Authored music level, kept separate from the duck multiplier so
    /// releasing a duck restores exactly what was asked for.
    private var musicBaseVolume: Float = 0.8
    private var musicDuckFactor: Float = 1.0

    func playMusic(_ assetName: String, volume: Float = 0.8, loops: Bool = true) {
        guard let url = url(for: assetName),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        musicPlayer?.stop()
        musicBaseVolume = volume
        player.volume = 0
        player.numberOfLoops = loops ? -1 : 0
        player.play()
        // Music started mid-duck fades in already ducked — same contract as
        // the spatial sources, so a voice in progress is never stepped on.
        player.setVolume(volume * musicDuckFactor, fadeDuration: 1.2)
        musicPlayer = player
    }

    /// Duck hook for AudioMixCoordinator: scales the authored music level
    /// while a voice speaks or the mic listens.
    func setMusicDuck(_ factor: Float, fade: TimeInterval) {
        musicDuckFactor = factor
        musicPlayer?.setVolume(musicBaseVolume * factor, fadeDuration: fade)
    }

    func stopMusic(fadeOut: TimeInterval = 0.8) {
        guard let player = musicPlayer else { return }
        musicPlayer = nil
        player.setVolume(0, fadeDuration: fadeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeOut + 0.1) {
            player.stop()
        }
    }

    private func url(for assetName: String) -> URL? {
        if let cached = urlCache[assetName] { return cached }
        let base = (assetName as NSString).deletingPathExtension
        let ext = (assetName as NSString).pathExtension
        let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Assets/Audio")
            ?? Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Assets/music")
            ?? Bundle.main.url(forResource: base, withExtension: ext)
        urlCache[assetName] = url
        return url
    }
}
