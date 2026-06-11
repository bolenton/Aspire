import Foundation
import StoryEngine
import SwiftUI

/// The audio-first game loop for one scene: movement, spatial audio,
/// quest progression, dialogue, song-spells, telemetry, and the live
/// world snapshot that grounds both AI and freeze-and-explain.
@MainActor
final class GameViewModel: ObservableObject {
    @Published var slot: SaveSlot
    @Published var pose = PlayerPose()
    @Published var currentDialogue: DialogueNode?
    @Published var activeSongSpell: SongSpell?
    @Published var sungNotes: [SolfegeNote] = []
    @Published private(set) var events = EventLog()
    @Published var companionReply: String?

    let pack: StoryPack
    let companion: Companion
    let childName: String
    let audio = SpatialAudioEngine()
    let narrator: Narrator
    private let brain: any CompanionBrain
    private let saveSlot: (SaveSlot) -> Void

    private var sessionStart = Date()
    private var stepStartedAt = Date()
    private var stepHintsUsed = 0

    private var tick: TimeInterval { Date().timeIntervalSince(sessionStart) }

    /// Reaching within this distance completes reach/collect steps.
    private let arrivalDistance = 2.5
    private let stepLength = 1.5

    init(slot: SaveSlot, pack: StoryPack, companion: Companion, childName: String,
         narrator: Narrator, brain: any CompanionBrain,
         saveSlot: @escaping (SaveSlot) -> Void) {
        self.slot = slot
        self.pack = pack
        self.companion = companion
        self.childName = childName
        self.narrator = narrator
        self.brain = brain
        self.saveSlot = saveSlot
    }

    var scene: StoryEngine.Scene? {
        pack.scene(id: slot.progress.currentSceneID)
    }

    var resolvedEntities: [ResolvedEntity] {
        scene?.activeEntities(companion: companion) ?? []
    }

    var currentStep: QuestStep? {
        slot.progress.currentStep(in: pack)
    }

    // MARK: - Lifecycle

    func begin() {
        audio.start()
        if let scene {
            audio.loadScene(scene, resolved: resolvedEntities)
            audio.updateListener(pose: pose)
            events.record(GameEvent(tick: tick, kind: .sceneEntered,
                                    spoken: "You stepped into \(scene.name)."))
            var opening = scene.spokenDescription.resolved(for: companion.id)
            for finding in snapshot().abilityFindings {
                opening += " \(finding)"
            }
            if let step = currentStep {
                opening += " \(step.intro.resolved(for: companion.id))"
            }
            narrator.speak(opening, voice: companion.voice)
        }
        stepStartedAt = Date()
    }

    func snapshot() -> WorldSnapshot {
        guard let scene else {
            return WorldSnapshot(tick: tick, sceneID: "", sceneName: "Lantern",
                                 sceneDescription: "", pose: pose, perceived: [])
        }
        return SnapshotBuilder.build(pack: pack, companion: companion, scene: scene,
                                     pose: pose, progress: slot.progress,
                                     events: events, support: slot.difficulty.support,
                                     tick: tick)
    }

    func context() -> CompanionContext {
        CompanionContext(companion: companion, childName: childName,
                         snapshot: snapshot(), recentMemories: [])
    }

    func freezeReport() -> String {
        SituationReport.spoken(from: snapshot(), companion: companion, childName: childName)
    }

    // MARK: - Movement

    func walk() {
        let radians = pose.headingDegrees * .pi / 180
        var position = pose.position
        position.x += stepLength * sin(radians)
        position.z -= stepLength * cos(radians)
        position.x = min(max(position.x, -40), 40)
        position.z = min(max(position.z, -40), 40)
        pose.position = position
        audio.updateListener(pose: pose)
        checkArrival()
    }

    func turn(degrees: Double) {
        pose.headingDegrees = (pose.headingDegrees + degrees).truncatingRemainder(dividingBy: 360)
        audio.updateListener(pose: pose)
    }

    /// The nearest interactable thing, for the big context-sensitive button.
    var nearbyEntity: ResolvedEntity? {
        resolvedEntities
            .filter { !$0.isAnonymousTease }
            .filter { pose.position.distance(to: $0.entity.position) <= arrivalDistance }
            .min { pose.position.distance(to: $0.entity.position) < pose.position.distance(to: $1.entity.position) }
    }

    private func checkArrival() {
        guard let step = currentStep, step.goal == .reach || step.goal == .collect,
              let target = resolvedEntities.first(where: { $0.entity.id == step.targetEntityID }),
              pose.position.distance(to: target.entity.position) <= arrivalDistance else { return }

        if step.goal == .collect {
            let availability = slot.progress.availability(of: target.entity)
            guard availability.available else { return }
        }
        completeCurrentStep(targetID: step.targetEntityID, kind: .navigation)
    }

    // MARK: - Interaction

    func interactWithNearby() {
        guard let nearby = nearbyEntity else { return }
        let entity = nearby.entity

        let availability = slot.progress.availability(of: entity)
        if !availability.available {
            if let explanation = availability.explanation {
                narrator.speak(explanation, voice: companion.voice)
            }
            return
        }

        if let step = currentStep, step.targetEntityID == entity.id {
            switch step.goal {
            case .talk:
                if let dialogueID = entity.dialogueID, let dialogue = pack.dialogue(id: dialogueID) {
                    currentDialogue = dialogue
                    return
                }
            case .song:
                if let spellID = step.songSpellID, let spell = pack.songSpell(id: spellID) {
                    startSongSpell(spell)
                    return
                }
            case .reach, .collect:
                completeCurrentStep(targetID: entity.id, kind: .navigation)
                return
            }
        }

        if let dialogueID = entity.dialogueID, let dialogue = pack.dialogue(id: dialogueID) {
            currentDialogue = dialogue
        } else if let sense = entity.senseLine, nearby.revealedByAbilityID != nil {
            narrator.speak(sense.resolved(for: companion.id), voice: companion.voice)
        }
    }

    func choose(_ choice: DialogueChoice) {
        if let key = choice.memoryKey, let value = choice.memoryValue {
            let event = MemoryEvent(kind: .choice, key: key, value: value,
                                    spokenRecap: "You chose: \(choice.text.resolved(for: companion.id))",
                                    companionID: companion.id)
            slot.journal.remember(event)
        }
        if let nextID = choice.nextDialogueID, let next = pack.dialogue(id: nextID) {
            currentDialogue = next
            narrator.speak(next.line.resolved(for: companion.id), voice: companion.voice)
        } else {
            currentDialogue = nil
            events.record(GameEvent(tick: tick, kind: .dialogueFinished,
                                    spoken: "You and \(companion.name) made a plan."))
            if let step = currentStep, step.goal == .talk {
                completeCurrentStep(targetID: step.targetEntityID, kind: .dialogue)
            }
        }
        persist()
    }

    // MARK: - Song spells

    func startSongSpell(_ spell: SongSpell) {
        activeSongSpell = spell
        sungNotes = []
        let names = spell.notes.map(\.rawValue.capitalized).joined(separator: ", ")
        narrator.speak("Listen: \(names). Now you sing it back!", voice: companion.voice)
    }

    func sing(note: SolfegeNote) {
        guard let spell = activeSongSpell else { return }
        sungNotes.append(note)
        narrator.speakWord(note.rawValue.capitalized, voice: companion.voice)

        guard sungNotes.count >= spell.notes.count else { return }
        if Array(sungNotes.suffix(spell.notes.count)) == spell.notes {
            activeSongSpell = nil
            sungNotes = []
            events.record(GameEvent(tick: tick, kind: .songCast,
                                    spoken: "You sang \(spell.name)!"))
            if let step = currentStep, step.goal == .song {
                completeCurrentStep(targetID: step.targetEntityID, kind: .song)
            }
        } else {
            // Never punish: gentle retry, count it for the difficulty director.
            sungNotes = []
            recordTelemetry(kind: .song, succeeded: false)
            narrator.speak("Almost! Let's try again, nice and slow.", voice: companion.voice)
        }
    }

    // MARK: - Asking the companion

    func ask(_ utterance: String) {
        let currentContext = context()
        Task {
            let reply: String
            do {
                reply = try await brain.reply(to: utterance, context: currentContext)
            } catch {
                reply = (try? await ScriptedBrain().reply(to: utterance, context: currentContext))
                    ?? "I'm right here with you."
            }
            self.companionReply = reply
            self.narrator.speak(reply, voice: self.companion.voice)
        }
    }

    func requestHint() {
        stepHintsUsed += 1
        guard let step = currentStep else { return }
        let hint = slot.difficulty.hint(for: step, companionID: companion.id)
        narrator.speak(hint, voice: companion.voice)
    }

    // MARK: - Progress

    private func completeCurrentStep(targetID: String, kind: ActivityKind) {
        guard let completed = slot.progress.completeStepIfTargeted(entityID: targetID, in: pack) else { return }
        events.record(GameEvent(tick: tick, kind: .stepCompleted,
                                spoken: completed.celebration.resolved(for: companion.id)))
        if completed.goal == .collect {
            audio.removeSource(id: targetID)
        }
        recordTelemetry(kind: kind, succeeded: true)

        var speech = completed.celebration.resolved(for: companion.id)

        if let quest = slot.progress.activeQuest(in: pack), slot.progress.isQuestComplete(quest) {
            slot.journal.remember(MemoryEvent(kind: .questCompleted, key: quest.id, value: "done",
                                              spokenRecap: "Together you finished \(quest.title).",
                                              companionID: companion.id))
            if let next = slot.progress.availableQuests(in: pack)
                .first(where: { !slot.progress.isQuestComplete($0) }) {
                slot.progress.activeQuestID = next.id
                speech += " \(next.spokenSummary.resolved(for: companion.id))"
            } else {
                slot.progress.activeQuestID = nil
                speech += " You finished every adventure here... for now!"
            }
        } else if let next = currentStep {
            speech += " \(next.intro.resolved(for: companion.id))"
        }

        narrator.speak(speech, voice: companion.voice)
        stepStartedAt = Date()
        stepHintsUsed = 0
        persist()
    }

    private func recordTelemetry(kind: ActivityKind, succeeded: Bool) {
        let sample = TelemetrySample(kind: kind, succeeded: succeeded,
                                     duration: Date().timeIntervalSince(stepStartedAt),
                                     hintsUsed: stepHintsUsed)
        slot.difficulty.record(sample)
        if slot.difficulty.lastChangeWasEscalation {
            events.record(GameEvent(tick: tick, kind: .struggleDetected,
                                    spoken: "\(companion.name) noticed that one was tricky."))
        }
    }

    func persist() {
        saveSlot(slot)
    }
}
