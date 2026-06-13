import AVFoundation
import Foundation
import StoryEngine
import SwiftUI

enum AppRoute: Equatable {
    case home
    case calibration
    case companionPicker
    case game(slotID: String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var vault: PlayerVault
    @Published var route: AppRoute = .home
    @Published var frozen = false

    let pack: StoryPack
    let roster: CompanionRoster
    let narrator = Narrator()
    weak var activeGame: GameViewModel?

    private let vaultURL: URL

    var theme: Theme { Theme(profile: vault.calibration) }
    var childName: String { vault.calibration.childName.isEmpty ? "friend" : vault.calibration.childName }

    var availableCompanions: [Companion] {
        pack.availableCompanions(sharedRoster: roster)
    }

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        vaultURL = documents.appendingPathComponent("vault.json")
        vault = PlayerVault.load(from: vaultURL)
        pack = Self.loadResource("StoryPacks/ForestJourney", file: "pack",
                                 fallback: StoryPack(id: "empty", title: "Lantern", version: 1)) {
            try StoryPack.load(from: $0)
        }
        roster = Self.loadResource("StoryPacks/Companions", file: "roster",
                                   fallback: CompanionRoster(companions: [])) {
            try CompanionRoster.load(from: $0)
        }
        narrator.profile = vault.calibration
        VoiceDirector.shared.configureAutoVoices(companionIDs: availableCompanions.map(\.id))
        narrator.cloudProvider = makeTTSProvider()
    }

    private static func loadResource<T>(_ subdirectory: String, file: String,
                                        fallback: T, decode: (Data) throws -> T) -> T {
        let url = Bundle.main.url(forResource: file, withExtension: "json", subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: file, withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url), let value = try? decode(data) else {
            return fallback
        }
        return value
    }

    func saveVault() {
        try? vault.save(to: vaultURL)
        narrator.profile = vault.calibration
    }

    func startNewAdventure() {
        route = vault.calibration.childName.isEmpty ? .calibration : .companionPicker
    }

    func createSlot(companion: Companion) {
        guard let firstScene = pack.regions.first?.scenes.first else { return }
        var slot = vault.createSlot(pack: pack, companion: companion, startSceneID: firstScene.id)
        slot.progress.activeQuestID = slot.progress.availableQuests(in: pack).first?.id
        vault.update(slot)
        saveVault()
        route = .game(slotID: slot.id)
    }

    var latestSlot: SaveSlot? {
        vault.slots.max { $0.lastPlayedAt < $1.lastPlayedAt }
    }

    func makeGameViewModel(slotID: String) -> GameViewModel? {
        guard let slot = vault.slot(id: slotID),
              let companion = availableCompanions.first(where: { $0.id == slot.companionID }) else {
            return nil
        }
        let brain = makeBrain()
        if let remote = brain as? OpenAICompatibleBrain {
            // Make sure the Local Network permission is requested before her
            // first spoken question needs the server.
            Task { await LocalNetworkPrompter.prime(endpoint: remote.endpoint) }
        }
        let game = GameViewModel(
            slot: slot, pack: pack, companion: companion,
            childName: childName, narrator: narrator, brain: brain,
            highContrastWorld: vault.calibration.contrastTheme == .highContrastYellow,
            sharedMemories: { [weak self] in self?.vault.sharedJournal.events ?? [] },
            rememberShared: { [weak self] event in
                self?.vault.sharedJournal.remember(event)
                self?.saveVault()
            },
            saveSlot: { [weak self] updated in
                self?.vault.update(updated)
                self?.saveVault()
            })
        game.audio.worldVolume = Float(vault.calibration.worldVolume)
        return game
    }

    // MARK: - Freeze and explain (two-finger hold, works everywhere)

    func freezeBegan() {
        frozen = true
        narrator.stop()
        SoundBank.shared.play("earcon_freeze.wav")
        if let game = activeGame {
            game.movementFreeze()
            game.audio.setFrozen(true)
            narrator.speak(game.freezeReport(), voice: game.companion.resolvedVoice)
        } else {
            narrator.speak(menuSituationDescription)
        }
    }

    func freezeEnded() {
        frozen = false
        activeGame?.audio.setFrozen(false)
        activeGame?.movementResume()
    }

    private var menuSituationDescription: String {
        switch route {
        case .home:
            return "You're on the Lantern home screen. The big buttons start or continue an adventure. The small button at the bottom is for grown-ups."
        case .calibration:
            return "You're setting up the game so it feels just right. A grown-up can help with this part."
        case .companionPicker:
            return "You're choosing your companion. Three friends are waiting to meet you — tap each one to hear them say hello."
        case .game:
            return "You're in the adventure."
        }
    }

    // MARK: - Companion brain configuration (parent settings)

    @AppStorage("brain.endpoint") var brainEndpoint: String = ""
    @AppStorage("brain.model") var brainModel: String = ""
    @AppStorage("brain.provider") var brainProviderRaw: String = BrainProviderChoice.auto.rawValue

    /// The brain key now lives in the Keychain. Read-through migration: an
    /// older build's plaintext default is promoted into the Keychain and the
    /// default wiped on first access, so it exists in only one place after.
    var brainAPIKey: String {
        KeychainStore.migratedValue(account: KeychainStore.Key.brain,
                                    userDefaultsKey: "brain.apiKey") ?? ""
    }

    var brainProvider: BrainProviderChoice {
        BrainProviderChoice(rawValue: brainProviderRaw) ?? .auto
    }

    /// Provider policy. Every path bottoms out at the deterministic
    /// storyteller — the companion never goes silent.
    func makeBrain() -> any CompanionBrain {
        switch brainProvider {
        case .scripted:
            return ScriptedBrain()
        case .onDevice:
            return OnDeviceBrain.make() ?? ScriptedBrain()
        case .remote:
            return remoteBrain() ?? ScriptedBrain()
        case .auto:
            // A configured server is explicit parent intent — it wins.
            if let remote = remoteBrain() { return remote }
            if let onDevice = OnDeviceBrain.make() { return onDevice }
            return ScriptedBrain()
        }
    }

    private func remoteBrain() -> (any CompanionBrain)? {
        guard !brainEndpoint.isEmpty, !brainModel.isEmpty,
              let url = URL(string: brainEndpoint) else { return nil }
        return OpenAICompatibleBrain(endpoint: url, model: brainModel,
                                     apiKey: brainAPIKey.isEmpty ? nil : brainAPIKey)
    }

    var brainStatusDescription: String {
        switch brainProvider {
        case .scripted:
            return "Built-in storyteller — offline, always available."
        case .onDevice:
            return OnDeviceBrain.isAvailable
                ? "Apple's on-device model — private, free, works offline."
                : "Apple's on-device model isn't available on this device, so the built-in storyteller will answer."
        case .remote:
            return remoteBrain() != nil
                ? "Your server: \(brainModel) at \(brainEndpoint)."
                : "Server not set up yet — fill in the endpoint and model below."
        case .auto:
            if remoteBrain() != nil { return "Auto → your server (\(brainModel))." }
            if OnDeviceBrain.isAvailable { return "Auto → Apple's on-device model." }
            return "Auto → built-in storyteller. Add a server below (or use an Apple Intelligence device) to upgrade."
        }
    }

    /// Parent-settings connection test. HONEST on purpose: a configured
    /// server is called directly with no scripted fallback, so a broken
    /// connection reports its real error instead of being silently covered
    /// for — exactly the masking that makes "it acts like it works" bugs.
    func testBrain() async -> String {
        guard let companion = availableCompanions.first else {
            return "No companions loaded — check the story pack."
        }
        let snapshot = WorldSnapshot(
            tick: 0, sceneID: "brain_test", sceneName: "the testing meadow",
            sceneDescription: "A quiet, sunny meadow that exists just for testing.",
            pose: PlayerPose(), perceived: [],
            ambientSounds: ["a gentle breeze"])
        let context = CompanionContext(companion: companion, childName: childName,
                                       snapshot: snapshot)
        let question = "Hello! Please introduce yourself in one short, friendly sentence."
        let brain = makeBrain()

        if let remote = brain as? OpenAICompatibleBrain {
            // Raw socket first: triggers the Local Network prompt reliably
            // AND tells us exactly how far the connection got.
            let socket = await LocalNetworkPrompter.probe(endpoint: remote.endpoint)
            guard socket.ok else {
                return """
                ✗ Can't reach your server — the connection failed before the AI was even asked.
                Diagnosis: \(socket.message)
                If the Local Network dialog has never appeared and Lantern isn't listed in iPad Settings → Privacy & Security → Local Network: delete the app, restart the iPad, reinstall — iOS caches a stuck denial for development builds.
                """
            }
            do {
                let reply = try await remote.directReply(to: question, context: context)
                narrator.speak(reply, voice: companion.resolvedVoice)
                return "✓ Your server answered — \(remote.model) is live and will power the companion.\n\(companion.name) says: “\(reply)”"
            } catch {
                return """
                ✗ The \(socket.message) — so Wi-Fi, permission, and the port are all FINE — but the chat call failed:
                \(error.localizedDescription)
                Likely: the endpoint is missing /v1 at the end, or the model name doesn't match the server's (run `ollama list` on the Mac and copy the exact name).
                """
            }
        }

        do {
            let reply = try await brain.reply(to: question, context: context)
            narrator.speak(reply, voice: companion.resolvedVoice)
            let who = brain is ScriptedBrain ? "built-in storyteller" : "on-device Apple model"
            return "✓ Answered by the \(who).\n\(companion.name) says: “\(reply)”"
        } catch {
            return "✗ No answer (\(error.localizedDescription))."
        }
    }

    // MARK: - Premium voice configuration (parent settings)

    @AppStorage("tts.provider") var ttsProviderRaw: String = TTSProviderChoice.system.rawValue
    @AppStorage("tts.elevenlabs.model") var ttsElevenLabsModel: String = ""
    @AppStorage("tts.openai.endpoint") var ttsOpenAIEndpoint: String = ""
    @AppStorage("tts.openai.model") var ttsOpenAIModel: String = ""

    var ttsProvider: TTSProviderChoice {
        TTSProviderChoice(rawValue: ttsProviderRaw) ?? .system
    }

    /// Builds the configured neural-TTS provider, or nil for the system voice
    /// (the offline-first default). Mirrors makeBrain(): a missing key or
    /// endpoint silently means "stay on AVSpeech", never an error.
    func makeTTSProvider() -> (any TTSProvider)? {
        switch ttsProvider {
        case .system:
            return nil
        case .elevenLabs:
            guard let key = KeychainStore.get(KeychainStore.Key.elevenLabs), !key.isEmpty else {
                return nil
            }
            let model = ttsElevenLabsModel.isEmpty ? "eleven_flash_v2_5" : ttsElevenLabsModel
            var provider = ElevenLabsTTSProvider(apiKey: key, modelID: model)
            // ElevenLabs bakes speed into the audio; feed it her calibration so
            // the cache key's speed bucket matches what's actually synthesized.
            provider.rate = vault.calibration.speechRate
            return provider
        case .openAICompatible:
            guard !ttsOpenAIEndpoint.isEmpty, let url = URL(string: ttsOpenAIEndpoint) else {
                return nil
            }
            let key = KeychainStore.get(KeychainStore.Key.openAI)
            let model = ttsOpenAIModel.isEmpty ? "gpt-4o-mini-tts" : ttsOpenAIModel
            return OpenAISpeechTTSProvider(baseURL: url,
                                           apiKey: (key?.isEmpty ?? true) ? nil : key,
                                           model: model)
        }
    }

    /// Re-reads settings into the narrator. Called when the parent gate
    /// closes so a just-changed provider/voice takes effect immediately.
    func reinstallTTSProvider() {
        narrator.cloudProvider = makeTTSProvider()
    }

    var ttsStatusDescription: String {
        switch ttsProvider {
        case .system:
            return "Apple's built-in voices — offline, free, always available. Premium voices are an optional upgrade."
        case .elevenLabs:
            return makeTTSProvider() != nil
                ? "ElevenLabs — pick a voice for each companion below."
                : "Add your ElevenLabs API key below to turn this on."
        case .openAICompatible:
            return makeTTSProvider() != nil
                ? "Speech server: \(ttsOpenAIModel.isEmpty ? "gpt-4o-mini-tts" : ttsOpenAIModel) at \(ttsOpenAIEndpoint)."
                : "Add the server's address below (OpenAI or a local speech server)."
        }
    }

    /// Parent-settings voice test. HONEST like testBrain(): the configured
    /// provider is called directly with NO AVSpeech fallback, so a bad key or
    /// unchosen voice reports its real error instead of sounding like it works.
    func testVoice() async -> String {
        guard let provider = makeTTSProvider() else {
            return "Pick a premium provider and add its key first, or leave it on Apple's built-in voices."
        }
        let companion = availableCompanions.first
        let spec = companion?.resolvedVoice ?? VoiceDirector.shared.narratorSpec()
        guard let voiceID = spec.cloudVoiceID, !voiceID.isEmpty else {
            return "✗ No premium voice is chosen yet — pick one for \(companion?.name ?? "the narrator") in the list below."
        }
        let line = "Hello \(childName)! This is my real voice."
        do {
            let audio = try await provider.synthesize(text: line, voiceID: voiceID)
            playTestAudio(audio)
            return "✓ \(companion?.name ?? "The narrator") spoke with a premium voice — you should have just heard it."
        } catch {
            return """
            ✗ The premium voice didn't answer:
            \(error.localizedDescription)
            Likely: check the API key is correct, or that a voice is chosen for this companion.
            """
        }
    }

    private var testVoicePlayer: AVAudioPlayer?

    private func playTestAudio(_ audio: TTSAudio) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(audio.fileExtension)
        guard (try? audio.data.write(to: url)) != nil,
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = Float(min(max(vault.calibration.narrationVolume, 0), 1))
        player.play()
        testVoicePlayer = player
    }
}

enum TTSProviderChoice: String, CaseIterable {
    case system, elevenLabs, openAICompatible

    var label: String {
        switch self {
        case .system: return "Apple"
        case .elevenLabs: return "ElevenLabs"
        case .openAICompatible: return "OpenAI / server"
        }
    }
}

enum BrainProviderChoice: String, CaseIterable {
    case auto, onDevice, remote, scripted

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .onDevice: return "On-device"
        case .remote: return "My server"
        case .scripted: return "Built-in"
        }
    }
}
