import AVFoundation
import Foundation
import StoryEngine

/// Speaks everything aloud and publishes word-by-word progress so the giant
/// on-screen text can highlight along — the literacy-reinforcement loop.
///
/// Two voices, one seam: AVSpeech is always present and always correct; a
/// premium neural provider, when a parent configures one and a voice is
/// chosen, is a silent upgrade. The published surface is identical on both
/// paths so every call site (and the highlight) is oblivious to which voice
/// actually spoke. A cloud line that's slow or fails simply means AVSpeech
/// speaks it instead — never dead air, never a glitch in the captions.
@MainActor
final class Narrator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var currentText: String = ""
    @Published private(set) var highlightRange: NSRange?
    @Published private(set) var isSpeaking = false

    /// The neural provider, installed by AppModel from parent settings. nil
    /// (the default) means every line takes the AVSpeech path verbatim —
    /// byte-identical to the pre-premium-voice build.
    var cloudProvider: (any TTSProvider)?
    /// Shared on-disk store of synthesized lines; also written by the
    /// prefetcher so a warmed line plays from disk the instant it's needed.
    let cache = SpeechCache()
    /// Warms upcoming lines into `cache`. GameViewModel drives it on scene
    /// entry / step advance / dialogue open; it no-ops when no provider is set.
    private(set) lazy var prefetcher = SpeechPrefetcher(narrator: self)

    var profile: CalibrationProfile = .standard

    /// Default latency ceiling before a cache-miss line gives up on the
    /// network and lets AVSpeech speak. ask() replies pass a longer budget.
    static let defaultLatencyBudget: TimeInterval = 1.5
    /// AI answers earn a 6 s budget — the "thinking" cue already covers the
    /// wait, so a premium voice is worth holding out for there.
    static let askLatencyBudget: TimeInterval = 6.0

    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?

    // Cloud playback state. The player and its 30 Hz highlight timer drive
    // the same `highlightRange` the AVSpeech delegate does.
    private var player: AVAudioPlayer?
    private var highlightTimer: Timer?
    private var activeTimings: [TTSWordTiming] = []
    private var highlightIndex = 0
    /// The in-flight synthesis task for the current line. Cancelled by stop()
    /// or by the next speak(). The background fetch that warms the cache after
    /// a budget overrun is intentionally NOT this task — it outlives the line.
    private var pendingSpeak: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Speaking

    func speak(_ text: String, voice: VoiceSpec? = nil, onFinish: (() -> Void)? = nil) {
        speak(text, voice: voice, latencyBudget: Self.defaultLatencyBudget, onFinish: onFinish)
    }

    /// The full entry point. `latencyBudget` is how long a cache-miss line
    /// will wait on synthesis before AVSpeech takes over; the default
    /// overload preserves the original three-argument signature exactly, so
    /// no existing caller changes.
    func speak(_ text: String, voice: VoiceSpec? = nil,
               latencyBudget: TimeInterval, onFinish: (() -> Void)? = nil) {
        stop()
        self.onFinish = onFinish
        // Captions appear immediately — they never wait on the network.
        currentText = text
        highlightRange = nil
        isSpeaking = true

        let spec = voice ?? VoiceDirector.shared.narratorSpec()

        // Zero-regression guarantee: no provider, or no cloud voice chosen for
        // this speaker, takes the original AVSpeech path verbatim.
        guard let provider = cloudProvider, let cloudVoiceID = spec.cloudVoiceID,
              !cloudVoiceID.isEmpty else {
            speakWithAVSpeech(text, spec: spec)
            return
        }

        let key = SpeechCache.Key(
            providerID: provider.providerID, voiceID: cloudVoiceID,
            model: providerModel(provider), speechRate: profile.speechRate, text: text)

        // Cache hit → play from disk this turn, no network at all.
        if let entry = cache.lookup(key) {
            playCloud(entry: entry, text: text, spec: spec)
            return
        }

        // Cache miss → race synthesis against the latency budget. Either the
        // audio lands in time and plays, or AVSpeech takes over while the
        // fetch keeps running in the background to warm the cache.
        startCloudFetchRace(text: text, spec: spec, provider: provider,
                            cloudVoiceID: cloudVoiceID, key: key, budget: latencyBudget)
    }

    /// Replays a single tapped word — literacy feature. Stays AVSpeech-only:
    /// one word is poor neural-TTS value and the literacy loop must work on
    /// every device, online or off.
    func speakWord(_ word: String, voice: VoiceSpec? = nil) {
        guard !isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: word)
        let spec = voice ?? VoiceDirector.shared.narratorSpec()
        if let identifier = spec.voiceIdentifier,
           let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = chosen
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: spec.languageCode)
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.8
        synthesizer.speak(utterance)
    }

    func stop() {
        pendingSpeak?.cancel()
        pendingSpeak = nil
        stopCloudPlayback()
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        highlightRange = nil
    }

    // MARK: - AVSpeech path

    private func speakWithAVSpeech(_ text: String, spec: VoiceSpec) {
        let utterance = AVSpeechUtterance(string: text)
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

    // MARK: - Cloud fetch race

    private func startCloudFetchRace(text: String, spec: VoiceSpec,
                                     provider: any TTSProvider, cloudVoiceID: String,
                                     key: SpeechCache.Key, budget: TimeInterval) {
        let cache = self.cache
        pendingSpeak = Task { [weak self] in
            // Run synthesis and a budget timer concurrently; whichever wins
            // decides whether we play cloud audio or hand off to AVSpeech.
            let result: Result<TTSAudio, Error> = await withTaskGroup(of: RaceOutcome.self) { group in
                group.addTask {
                    do { return .audio(try await provider.synthesize(text: text, voiceID: cloudVoiceID)) }
                    catch { return .failed(error) }
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(budget * 1_000_000_000))
                    return .timedOut
                }
                defer { group.cancelAll() }
                for await outcome in group {
                    switch outcome {
                    case .audio(let audio): return .success(audio)
                    case .failed(let error): return .failure(error)
                    case .timedOut: return .failure(CancellationError())
                    }
                }
                return .failure(CancellationError())
            }

            if Task.isCancelled { return }
            guard let self, !Task.isCancelled else { return }

            switch result {
            case .success(let audio):
                // Always persist what we paid to synthesize, even though we
                // play it immediately — the next replay is then free.
                cache.store(audio, for: key)
                let entry = SpeechCache.Entry(audioURL: cache.lookup(key)?.audioURL
                                              ?? self.tempFile(audio),
                                              fileExtension: audio.fileExtension,
                                              wordTimings: audio.wordTimings)
                self.playCloud(entry: entry, text: text, spec: spec)
            case .failure:
                // Budget overrun or error: AVSpeech speaks this line NOW, with
                // captions and highlight already in place — no glitch — while
                // a detached fetch keeps warming the cache for next time.
                self.speakWithAVSpeech(text, spec: spec)
                self.warmCacheInBackground(text: text, provider: provider,
                                           cloudVoiceID: cloudVoiceID, key: key)
            }
            self.pendingSpeak = nil
        }
    }

    private enum RaceOutcome {
        case audio(TTSAudio)
        case failed(Error)
        case timedOut
    }

    /// Continues a lost-the-race synthesis off to one side so the line is
    /// cached for its next occurrence. Detached from `pendingSpeak`: stop()
    /// or the next speak() must not abort cache warming.
    private func warmCacheInBackground(text: String, provider: any TTSProvider,
                                       cloudVoiceID: String, key: SpeechCache.Key) {
        let cache = self.cache
        Task.detached(priority: .utility) {
            if let audio = try? await provider.synthesize(text: text, voiceID: cloudVoiceID) {
                cache.store(audio, for: key)
            }
        }
    }

    /// Fallback when a freshly-synthesized line somehow isn't on disk yet
    /// (store failure): write a throwaway temp file so playback still happens.
    private func tempFile(_ audio: TTSAudio) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(audio.fileExtension)
        try? audio.data.write(to: url)
        return url
    }

    // MARK: - Cloud playback + highlight

    private func playCloud(entry: SpeechCache.Entry, text: String, spec: VoiceSpec) {
        guard let player = try? AVAudioPlayer(contentsOf: entry.audioURL) else {
            // Corrupt or unreadable cache file — never strand the line.
            speakWithAVSpeech(text, spec: spec)
            return
        }
        player.delegate = self
        player.volume = Float(min(max(spec.volume * profile.narrationVolume, 0), 1))
        player.prepareToPlay()

        // Real timestamps if the provider gave them; otherwise spread the
        // words across the audio's true duration so the highlight never dims.
        let timings = entry.wordTimings
            ?? TTSTimingMapper.estimate(text: text, totalDuration: player.duration)

        self.player = player
        activeTimings = timings
        highlightIndex = 0
        highlightRange = nil
        isSpeaking = true
        player.play()
        startHighlightTimer()
    }

    /// 30 Hz is fast enough that a word never lingers visibly past its audio
    /// yet cheap enough to ignore — the timer just reads player.currentTime.
    private func startHighlightTimer() {
        highlightTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceHighlight() }
        }
        RunLoop.main.add(timer, forMode: .common)
        highlightTimer = timer
    }

    private func advanceHighlight() {
        guard let player, !activeTimings.isEmpty else { return }
        let now = player.currentTime
        // Walk forward to the word whose window contains the playhead. Linear
        // because the playhead only ever moves forward within a line.
        while highlightIndex < activeTimings.count {
            let timing = activeTimings[highlightIndex]
            if now < timing.start { break }
            if now <= timing.start + timing.duration {
                let range = NSRange(location: timing.location, length: timing.length)
                if highlightRange != range { highlightRange = range }
                return
            }
            highlightIndex += 1
        }
    }

    private func stopCloudPlayback() {
        highlightTimer?.invalidate()
        highlightTimer = nil
        player?.delegate = nil
        player?.stop()
        player = nil
        activeTimings = []
        highlightIndex = 0
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.highlightRange = characterRange }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.finishSpeaking() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.isSpeaking = false
                self.highlightRange = nil
                self.onFinish = nil
            }
        }
    }

    // MARK: - Shared finish bookkeeping

    /// One completion path for both voices — clears speaking state and fires
    /// onFinish exactly once, mirroring the original AVSpeech delegate.
    private func finishSpeaking() {
        stopCloudPlayback()
        isSpeaking = false
        highlightRange = nil
        let finish = onFinish
        onFinish = nil
        finish?()
    }

    private func providerModel(_ provider: any TTSProvider) -> String {
        if let eleven = provider as? ElevenLabsTTSProvider { return eleven.modelID }
        if let openAI = provider as? OpenAISpeechTTSProvider { return openAI.model }
        return ""
    }
}

extension Narrator: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.finishSpeaking() }
        }
    }
}
