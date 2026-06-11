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
        return GameViewModel(
            slot: slot, pack: pack, companion: companion,
            childName: childName, narrator: narrator, brain: makeBrain(),
            sharedMemories: { [weak self] in self?.vault.sharedJournal.events ?? [] },
            rememberShared: { [weak self] event in
                self?.vault.sharedJournal.remember(event)
                self?.saveVault()
            },
            saveSlot: { [weak self] updated in
                self?.vault.update(updated)
                self?.saveVault()
            })
    }

    // MARK: - Freeze and explain (two-finger hold, works everywhere)

    func freezeBegan() {
        frozen = true
        narrator.stop()
        SoundBank.shared.play("earcon_freeze.wav")
        if let game = activeGame {
            game.audio.setFrozen(true)
            narrator.speak(game.freezeReport(), voice: game.companion.resolvedVoice)
        } else {
            narrator.speak(menuSituationDescription)
        }
    }

    func freezeEnded() {
        frozen = false
        activeGame?.audio.setFrozen(false)
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
    @AppStorage("brain.apiKey") var brainAPIKey: String = ""
    @AppStorage("brain.provider") var brainProviderRaw: String = BrainProviderChoice.auto.rawValue

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

    /// Parent-settings smoke test: asks the active brain one question with a
    /// tiny grounded context and reports who answered.
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
        do {
            let reply = try await makeBrain().reply(to: "Hello! Who are you?", context: context)
            narrator.speak(reply, voice: companion.resolvedVoice)
            return "✓ \(brainStatusDescription)\n\(companion.name) says: “\(reply)”"
        } catch {
            return "✗ No answer (\(error.localizedDescription)). In the game, the built-in storyteller covers for it automatically."
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
