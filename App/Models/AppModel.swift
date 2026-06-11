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
        return GameViewModel(slot: slot, pack: pack, companion: companion,
                             childName: childName, narrator: narrator,
                             brain: makeBrain()) { [weak self] updated in
            self?.vault.update(updated)
            self?.saveVault()
        }
    }

    // MARK: - Freeze and explain (two-finger hold, works everywhere)

    func freezeBegan() {
        frozen = true
        narrator.stop()
        if let game = activeGame {
            game.audio.setFrozen(true)
            narrator.speak(game.freezeReport(), voice: game.companion.voice)
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

    /// Brain chain: configured OpenAI-compatible endpoint (which itself falls
    /// back to scripted on any error) or the scripted brain outright. The
    /// companion never goes silent.
    func makeBrain() -> any CompanionBrain {
        if let url = URL(string: brainEndpoint), !brainEndpoint.isEmpty, !brainModel.isEmpty {
            return OpenAICompatibleBrain(endpoint: url, model: brainModel,
                                         apiKey: brainAPIKey.isEmpty ? nil : brainAPIKey)
        }
        return ScriptedBrain()
    }
}
