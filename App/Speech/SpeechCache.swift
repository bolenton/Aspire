import CryptoKit
import Foundation
import StoryEngine

/// On-disk store for synthesized narration. Premium TTS costs money and
/// latency per line, so every line a child hears is kept and replayed for
/// free — including fully offline, which is why it lives in Application
/// Support (backed up, survives relaunch and reinstall-restore) rather than
/// Caches/ (the OS purges that under disk pressure). Excluded from iCloud
/// backup so a 200 MB voice cache never bloats a parent's backup.
///
/// Every method is synchronous: `lookup` is on the narrator's hot path right
/// before playback and must not bounce through an actor.
final class SpeechCache {
    /// One audio line plus its word timings, ready to hand to AVAudioPlayer
    /// and the reading highlight.
    struct Entry {
        var audioURL: URL
        var fileExtension: String
        /// nil when the provider gave no timestamps — the caller estimates.
        var wordTimings: [TTSWordTiming]?
    }

    /// The components that define one cached line. speechRate is baked into
    /// ElevenLabs audio (it re-renders at the requested speed), so a rate
    /// change must miss the cache — hence the speed bucket in the key.
    struct Key {
        var providerID: String
        var voiceID: String
        var model: String
        var speechRate: Double
        var text: String
    }

    /// Prune trigger. Comfortably holds a full pack's narration at flash-model
    /// bitrates while never quietly eating a parent's storage.
    static let maxBytes = 200 * 1024 * 1024

    private let directory: URL
    private let fileManager = FileManager.default
    /// Serializes store/prune so two prefetches can't corrupt a half-written
    /// pair; lookups read finished files and don't need it.
    private let writeQueue = DispatchQueue(label: "com.bolenton.lantern.speechcache")

    init() {
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        directory = base.appendingPathComponent("SpeechCache", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromBackup()
    }

    // MARK: - Keying

    /// SHA-256 of "providerID|voiceID|model+speedBucket|text". A hash keeps
    /// filenames fixed-length and filesystem-safe regardless of the line.
    func hash(for key: Key) -> String {
        let speedBucket = Int((key.speechRate * 10).rounded())
        let material = "\(key.providerID)|\(key.voiceID)|\(key.model)+\(speedBucket)|\(key.text)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func audioURL(_ hash: String, ext: String) -> URL {
        directory.appendingPathComponent("\(hash).\(ext)")
    }

    private func timingsURL(_ hash: String) -> URL {
        directory.appendingPathComponent("\(hash).json")
    }

    // MARK: - Lookup (hot path, synchronous)

    /// Returns the cached line if present, touching its mtime so the LRU
    /// prune treats a just-replayed line as freshly used.
    func lookup(_ key: Key) -> Entry? {
        let hash = hash(for: key)
        let url = audioURL(hash, ext: "mp3")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        touch(url)
        var timings: [TTSWordTiming]?
        let timingURL = timingsURL(hash)
        if let data = try? Data(contentsOf: timingURL) {
            touch(timingURL)
            timings = try? JSONDecoder().decode([TTSWordTiming].self, from: data)
        }
        return Entry(audioURL: url, fileExtension: "mp3", wordTimings: timings)
    }

    /// True without decoding anything — the prefetcher's skip-hits check.
    func contains(_ key: Key) -> Bool {
        fileManager.fileExists(atPath: audioURL(hash(for: key), ext: "mp3").path)
    }

    // MARK: - Store

    /// Writes the audio (and timings, when present) for a line, then prunes
    /// if the cache crossed its ceiling. Audio is written atomically so a
    /// concurrent lookup never sees a half-file.
    func store(_ audio: TTSAudio, for key: Key) {
        writeQueue.sync {
            let hash = hash(for: key)
            // Both providers emit mp3; lookup keys on .mp3, so store there too.
            let url = audioURL(hash, ext: "mp3")
            do {
                try audio.data.write(to: url, options: .atomic)
            } catch {
                return
            }
            if let timings = audio.wordTimings,
               let data = try? JSONEncoder().encode(timings) {
                try? data.write(to: timingsURL(hash), options: .atomic)
            }
            pruneLocked()
        }
    }

    // MARK: - Size and clearing

    /// Total bytes on disk — shown in settings next to "Clear voice cache".
    var totalSize: Int {
        contents().reduce(0) { $0 + $1.size }
    }

    /// Wipes everything. Offline replay is a convenience, never canon — a
    /// parent reclaiming the space loses nothing but re-synthesis cost.
    func clear() {
        writeQueue.sync {
            for file in contents() {
                try? fileManager.removeItem(at: file.url)
            }
        }
    }

    // MARK: - LRU prune

    /// Evicts least-recently-used pairs (oldest mtime first) until under the
    /// ceiling. The .json timings file rides with its .mp3 — one logical line.
    private func pruneLocked() {
        var files = contents()
        var total = files.reduce(0) { $0 + $1.size }
        guard total > Self.maxBytes else { return }
        files.sort { $0.modified < $1.modified }
        for file in files {
            guard total > Self.maxBytes else { break }
            try? fileManager.removeItem(at: file.url)
            total -= file.size
        }
    }

    // MARK: - Filesystem helpers

    private struct FileInfo {
        var url: URL
        var size: Int
        var modified: Date
    }

    private func contents() -> [FileInfo] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys) else { return [] }
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return FileInfo(url: url,
                            size: values?.fileSize ?? 0,
                            modified: values?.contentModificationDate ?? .distantPast)
        }
    }

    /// Stamp mtime to now so the LRU prune treats a read as recent use.
    private func touch(_ url: URL) {
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func excludeFromBackup() {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
