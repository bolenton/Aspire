import AVFoundation
import Foundation
import Speech

/// Tap-to-talk: first tap opens the companion's ears (earcon + streaming
/// on-device recognition with a live transcript), second tap sends
/// IMMEDIATELY with whatever has been transcribed so far — no waiting on a
/// "final" recognition result that may never arrive. An empty transcript is
/// still delivered, so the companion can say "I didn't catch that".
final class SpeechListener: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onFinal: ((String) -> Void)?

    static func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

    func start(onFinal: @escaping (String) -> Void) {
        guard !isListening else { return }
        self.onFinal = onFinal
        transcript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.duckOthers, .defaultToSpeaker,
                                              .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    // Recognition ended on its own (silence timeout, final
                    // result, or an error) — deliver whatever we heard.
                    if error != nil || result?.isFinal == true {
                        self.finishAndSend()
                    }
                }
            }
        } catch {
            self.onFinal = nil
            teardown()
        }
    }

    /// Second tap (or recognition ending on its own): deliver the current
    /// transcript right now, even when it's empty.
    func finishAndSend() {
        guard let handler = onFinal else { return }
        onFinal = nil
        let text = transcript
        teardown()
        handler(text)
    }

    func cancel() {
        onFinal = nil
        teardown()
    }

    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
