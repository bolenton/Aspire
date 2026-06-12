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
    /// The portion of the melody she must sing back, scaled to her current
    /// challenge level.
    @Published var targetNotes: [SolfegeNote] = []
    @Published private(set) var events = EventLog()
    @Published var companionReply: String?
    /// True while the brain composes an answer to a spoken question.
    @Published var isThinking = false
    /// Head-tracking yaw offset (AirPods) on top of the body heading.
    @Published var headYawDegrees: Double = 0
    /// Bumped whenever the visible world changes (collects, unlocks) so the
    /// 3D view knows to rebuild.
    @Published private(set) var worldRevision = 0
    /// True while the companion is leading the way to the quest target.
    @Published private(set) var isAutopiloting = false
    /// Screen-space joystick ring + thumb dot, mirrored from the touch
    /// layer — vision confirms what the stick earcons already say.
    @Published var stickVisual: (center: CGPoint, thumb: CGPoint)?

    let pack: StoryPack
    let companion: Companion
    let childName: String
    let audio = SpatialAudioEngine()
    /// Ducks the world under the narrator's voice and the listening mic.
    let audioMix = AudioMixCoordinator()
    let headTracker = HeadTracker()
    let loop = GameLoop()
    let movement = MovementController()
    let narrator: Narrator
    /// High-contrast world rendering (calibration `highContrastYellow` theme),
    /// threaded through to `WorldView`.
    let highContrastWorld: Bool
    /// Last moment she did anything at all — WS5's idle nudges read this.
    var lastInteractionAt = Date()
    private let brain: any CompanionBrain
    private let saveSlot: (SaveSlot) -> Void
    /// Child-level favorites shared across playthroughs (vault journal).
    private let sharedMemories: () -> [MemoryEvent]
    private let rememberShared: (MemoryEvent) -> Void

    private var sessionStart = Date()
    private var stepStartedAt = Date()
    private var stepHintsUsed = 0

    /// Movement integrates here every display frame; the published `pose`
    /// only updates ~20 Hz so SwiftUI isn't re-rendering at 120 Hz.
    private var workingPose = PlayerPose()
    private var lastPosePublish = Date.distantPast
    private var lastSlowTick = Date.distantPast
    private var wasMoving = false
    private var stickHeld = false
    private var footstepFlip = false
    private var movementFrozen = false
    /// Hook for WS5's interaction-range enter/leave earcons.
    private var lastNearbyID: String?

    private var tick: TimeInterval { Date().timeIntervalSince(sessionStart) }

    /// Reaching within this distance completes reach/collect steps.
    private let arrivalDistance = 2.5
    private let stepLength = 1.5

    init(slot: SaveSlot, pack: StoryPack, companion: Companion, childName: String,
         narrator: Narrator, brain: any CompanionBrain,
         highContrastWorld: Bool = false,
         sharedMemories: @escaping () -> [MemoryEvent] = { [] },
         rememberShared: @escaping (MemoryEvent) -> Void = { _ in },
         saveSlot: @escaping (SaveSlot) -> Void) {
        self.slot = slot
        self.pack = pack
        self.companion = companion
        self.childName = childName
        self.narrator = narrator
        self.brain = brain
        self.highContrastWorld = highContrastWorld
        self.sharedMemories = sharedMemories
        self.rememberShared = rememberShared
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
        audioMix.attach(narrator: narrator, audio: audio)
        headTracker.start { [weak self] yaw in
            self?.headYawDegrees = yaw
            self?.pushListener()
        }
        loop.onTick = { [weak self] dt in self?.gameTick(dt) }
        loop.start()
        enterScene()
        stepStartedAt = Date()
    }

    /// Arrival in a scene — on game start and every portal crossing.
    private func enterScene() {
        guard let scene else { return }
        if movement.isAutopilotActive {
            // A portal crossing invalidates the old target silently.
            movement.cancelAutopilot()
            isAutopiloting = false
        }
        pose = PlayerPose()
        workingPose = pose
        headTracker.recenter()
        audio.loadScene(scene, resolved: resolvedEntities)
        pushListener()
        worldRevision += 1
        events.record(GameEvent(tick: tick, kind: .sceneEntered,
                                spoken: "You stepped into \(scene.name)."))
        var opening = scene.spokenDescription.resolved(for: companion.id)
        let findings = snapshot().abilityFindings
        if !findings.isEmpty {
            SoundBank.shared.playCue("senseAlert", companion: companion)
        }
        for finding in findings {
            opening += " \(finding)"
        }
        if let step = currentStep {
            opening += " \(step.intro.resolved(for: companion.id))"
        }
        narrator.speak(opening, voice: companion.resolvedVoice)
    }

    func end() {
        loop.stop()
        headTracker.stop()
        audio.removeAllSources()
        persist()
    }

    /// What she perceives: body heading plus head turn — her ears lead.
    private var perceptionPose: PlayerPose {
        PlayerPose(position: pose.position,
                   headingDegrees: pose.headingDegrees + headYawDegrees)
    }

    private func pushListener() {
        audio.updateListener(pose: perceptionPose)
    }

    func snapshot() -> WorldSnapshot {
        guard let scene else {
            return WorldSnapshot(tick: tick, sceneID: "", sceneName: "Lantern",
                                 sceneDescription: "", pose: pose, perceived: [])
        }
        return SnapshotBuilder.build(pack: pack, companion: companion, scene: scene,
                                     pose: perceptionPose, progress: slot.progress,
                                     events: events, support: slot.difficulty.support,
                                     tick: tick)
    }

    func context() -> CompanionContext {
        let merged = (slot.journal.events + sharedMemories())
            .sorted { $0.date > $1.date }
            .prefix(8)
            .map(\.spokenRecap)
        return CompanionContext(companion: companion, childName: childName,
                                snapshot: snapshot(), recentMemories: Array(merged))
    }

    func freezeReport() -> String {
        SituationReport.spoken(from: snapshot(), companion: companion, childName: childName)
    }

    // MARK: - Game tick

    /// One simulation step per display frame. Publishing is throttled
    /// because `pose` re-evaluates GameView's body: ~20 Hz while moving
    /// plus once on stop (WorldView's blend smooths between poses), with
    /// arrival and nearby checks at 5 Hz.
    private func gameTick(_ dt: TimeInterval) {
        guard !movementFrozen, currentDialogue == nil, activeSongSpell == nil else { return }

        let result = movement.integrate(pose: workingPose, deltaTime: dt)
        let moving = result.pose != workingPose
        workingPose = result.pose
        handle(result.events)

        if movement.isAutopilotActive != isAutopiloting {
            isAutopiloting = movement.isAutopilotActive
        }

        let now = Date()
        if moving, now.timeIntervalSince(lastPosePublish) >= 0.05 {
            lastPosePublish = now
            pose = workingPose
            pushListener()
        } else if !moving, wasMoving {
            pose = workingPose
            pushListener()
        }
        wasMoving = moving

        if now.timeIntervalSince(lastSlowTick) >= 0.2 {
            lastSlowTick = now
            slowTick()
        }
    }

    /// The 5 Hz sub-tick: quest arrival plus the nearby-entity scan.
    /// WS5 (guidance) hooks its near/leave earcons, idle-nudge check, and
    /// compass facing tick in here.
    private func slowTick() {
        checkArrival()
        let nearbyID = nearbyEntity?.entity.id
        if nearbyID != lastNearbyID {
            lastNearbyID = nearbyID
        }
    }

    /// Movement events → biome footsteps, earcons, haptics. Buttons and
    /// the stick both land here, so feedback stays identical.
    private func handle(_ movementEvents: [MovementController.MovementEvent]) {
        for event in movementEvents {
            switch event {
            case .step:
                footstepFlip.toggle()
                SoundBank.shared.play(footstepAsset(), volume: 0.55)
                HapticsDirector.shared.stepTick()
            case .turnSnap:
                SoundBank.shared.play("earcon_turn_tick.wav", volume: 0.35)
                HapticsDirector.shared.turnSnap()
            case .boundaryBump:
                SoundBank.shared.play("earcon_boundary.wav", volume: 0.8)
                HapticsDirector.shared.boundaryBump()
            case .autopilotArrived:
                isAutopiloting = false
                HapticsDirector.shared.setActive(false)
                SoundBank.shared.play("earcon_autopilot_stop.wav", volume: 0.7)
                pose = workingPose
                pushListener()
                // Reach/collect steps resolve right away; talk/song targets
                // hand over to the context button.
                checkArrival()
            }
        }
    }

    /// Footsteps speak the ground: forest is grass, caves echo on stone,
    /// the courtyard is flagstone. Two alternating samples per surface
    /// avoid the machine-gun feel of one repeated hit.
    private func footstepAsset() -> String {
        let surface: String
        switch scene?.environment {
        case "cave": surface = "cave"
        case "castle": surface = "stone"
        default: surface = "grass"
        }
        return footstepFlip ? "footstep_\(surface)_b.wav" : "footstep_\(surface).wav"
    }

    // MARK: - Continuous input (touch stick + autopilot)

    /// Touch-stick input; `nil` = released. A live stick is always hers:
    /// it cancels autopilot before the movement controller sees it.
    func stickChanged(_ vector: CGVector?) {
        lastInteractionAt = Date()
        if vector != nil, movement.isAutopilotActive {
            cancelAutopilot(announce: false)
        }
        if vector != nil, !stickHeld {
            stickHeld = true
            SoundBank.shared.play("earcon_stick_engage.wav", volume: 0.6)
            HapticsDirector.shared.engage()
            HapticsDirector.shared.setActive(true)
        } else if vector == nil, stickHeld {
            stickHeld = false
            if !movement.isAutopilotActive {
                HapticsDirector.shared.setActive(false)
            }
        }
        movement.setJoystick(vector: vector)
    }

    /// Double-tap: the companion leads the way to the quest target.
    func requestAutopilot() {
        lastInteractionAt = Date()
        guard currentDialogue == nil, activeSongSpell == nil else { return }
        guard let step = currentStep,
              let target = resolvedEntities.first(where: { $0.entity.id == step.targetEntityID }) else {
            narrator.speak("We can go anywhere you like — there's nothing we have to find right now.",
                           voice: companion.resolvedVoice)
            return
        }
        let name = target.entity.id == StoryConventions.companionPlaceholder
            ? companion.name : target.entity.name
        SoundBank.shared.play("earcon_autopilot_start.wav", volume: 0.8)
        narrator.speak("Hold on tight — I'll lead the way to the \(name)! Touch the screen any time to stop.",
                       voice: companion.resolvedVoice)
        movement.startAutopilot(toward: target.entity.id, position: target.entity.position)
        isAutopiloting = true
        HapticsDirector.shared.setActive(true)
    }

    /// Touch-cancel is quiet on purpose — a touch means she wants control,
    /// and narrating the obvious would be nagging. The soft stop earcon
    /// still confirms it.
    func cancelAutopilot(announce: Bool) {
        lastInteractionAt = Date()
        guard movement.isAutopilotActive else { return }
        movement.cancelAutopilot()
        isAutopiloting = false
        if !stickHeld {
            HapticsDirector.shared.setActive(false)
        }
        SoundBank.shared.play("earcon_autopilot_stop.wav", volume: 0.6)
        if announce {
            narrator.speak("Okay — we'll stop here. You lead!", voice: companion.resolvedVoice)
        }
    }

    /// Freeze-and-explain halts the body, not just the audio: stick
    /// released, autopilot off, simulation paused.
    func movementFreeze() {
        lastInteractionAt = Date()
        movementFrozen = true
        movement.setJoystick(vector: nil)
        if movement.isAutopilotActive {
            movement.cancelAutopilot()
            isAutopiloting = false
        }
        stickHeld = false
        stickVisual = nil
        HapticsDirector.shared.setActive(false)
        loop.stop()
    }

    func movementResume() {
        guard movementFrozen else { return }
        movementFrozen = false
        loop.start()
    }

    // MARK: - Movement (fallback buttons + VoiceOver path)

    func walk() {
        lastInteractionAt = Date()
        let radians = workingPose.headingDegrees * .pi / 180
        var position = workingPose.position
        position.x += stepLength * sin(radians)
        position.z -= stepLength * cos(radians)
        let clampedX = min(max(position.x, -40), 40)
        let clampedZ = min(max(position.z, -40), 40)
        let bumped = clampedX != position.x || clampedZ != position.z
        position.x = clampedX
        position.z = clampedZ

        var stepEvents: [MovementController.MovementEvent] = []
        if workingPose.position.distance(to: position) > 0.01 {
            stepEvents.append(.step)
        }
        if bumped {
            stepEvents.append(.boundaryBump)
        }
        workingPose.position = position
        pose = workingPose
        pushListener()
        handle(stepEvents)
        checkArrival()
    }

    func turn(degrees: Double) {
        lastInteractionAt = Date()
        workingPose.headingDegrees = (workingPose.headingDegrees + degrees)
            .truncatingRemainder(dividingBy: 360)
        pose = workingPose
        pushListener()
        // A ±45° button turn always lands on a new sector — same tick as
        // the stick crossing one.
        handle([.turnSnap])
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
              workingPose.position.distance(to: target.entity.position) <= arrivalDistance else { return }

        if step.goal == .collect {
            let availability = slot.progress.availability(of: target.entity)
            guard availability.available else { return }
        }
        completeCurrentStep(targetID: step.targetEntityID, kind: .navigation)
    }

    // MARK: - Interaction

    func interactWithNearby() {
        lastInteractionAt = Date()
        if movement.isAutopilotActive {
            // Interacting takes over — the autopilot must not resume
            // toward a stale target when the dialogue closes.
            movement.cancelAutopilot()
            isAutopiloting = false
        }
        guard let nearby = nearbyEntity else { return }
        let entity = nearby.entity

        let availability = slot.progress.availability(of: entity)
        if !availability.available {
            if let explanation = availability.explanation {
                narrator.speak(explanation, voice: companion.resolvedVoice)
            }
            return
        }

        if entity.kind == .portal, slot.progress.travel(through: entity) != nil {
            narrator.stop()
            enterScene()
            persist()
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
            narrator.speak(sense.resolved(for: companion.id), voice: companion.resolvedVoice)
        }
    }

    func choose(_ choice: DialogueChoice) {
        lastInteractionAt = Date()
        if let key = choice.memoryKey, let value = choice.memoryValue {
            // Favorites are about the child and cross playthroughs; story
            // choices stay with this companion's journey.
            let isFavorite = key.hasPrefix("favorite")
            let event = MemoryEvent(kind: isFavorite ? .favorite : .choice,
                                    key: key, value: value,
                                    spokenRecap: "You chose: \(choice.text.resolved(for: companion.id))",
                                    companionID: companion.id)
            if isFavorite {
                rememberShared(event)
            } else {
                slot.journal.remember(event)
            }
        }
        if let nextID = choice.nextDialogueID, let next = pack.dialogue(id: nextID) {
            currentDialogue = next
            narrator.speak(next.line.resolved(for: companion.id), voice: companion.resolvedVoice)
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
        targetNotes = spell.notes(forChallenge: slot.difficulty.support.challenge)
        let names = targetNotes.map(\.rawValue.capitalized).joined(separator: ", ")
        narrator.speak("Listen: \(names). Now you sing it back!",
                       voice: companion.resolvedVoice) { [weak self] in
            self?.playTargetMelody()
        }
    }

    /// Plays the target melody as real tones at the spell's tempo —
    /// listen first, then she repeats it.
    func playTargetMelody() {
        guard let spell = activeSongSpell else { return }
        let beat = 60.0 / Double(max(spell.tempo, 30))
        let melody = targetNotes
        Task { @MainActor in
            for note in melody {
                SoundBank.shared.playNote(note)
                try? await Task.sleep(nanoseconds: UInt64(beat * 1_000_000_000))
            }
        }
    }

    func sing(note: SolfegeNote) {
        lastInteractionAt = Date()
        guard let spell = activeSongSpell, !targetNotes.isEmpty else { return }
        SoundBank.shared.playNote(note)
        sungNotes.append(note)

        // Stop early on a wrong note? No — let her finish the phrase, then
        // respond gently. Mid-phrase corrections feel like punishment.
        guard sungNotes.count >= targetNotes.count else { return }
        if Array(sungNotes.suffix(targetNotes.count)) == targetNotes {
            activeSongSpell = nil
            sungNotes = []
            events.record(GameEvent(tick: tick, kind: .songCast,
                                    spoken: "You sang \(spell.name)!"))
            if let step = currentStep, step.goal == .song {
                completeCurrentStep(targetID: step.targetEntityID, kind: .song)
            }
        } else {
            sungNotes = []
            recordTelemetry(kind: .song, succeeded: false)
            narrator.speak("Almost! Listen once more, nice and slow.",
                           voice: companion.resolvedVoice) { [weak self] in
                self?.playTargetMelody()
            }
        }
    }

    // MARK: - Asking the companion

    func ask(_ utterance: String) {
        lastInteractionAt = Date()
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            narrator.speak("Hmm, I didn't catch that. Tap the button and try asking again!",
                           voice: companion.resolvedVoice)
            return
        }
        isThinking = true
        SoundBank.shared.playCue("thinking", companion: companion, volume: 0.7)
        let currentContext = context()
        Task {
            let reply: String
            do {
                reply = try await brain.reply(to: trimmed, context: currentContext)
            } catch {
                reply = (try? await ScriptedBrain().reply(to: trimmed, context: currentContext))
                    ?? "I'm right here with you."
            }
            self.isThinking = false
            self.companionReply = reply
            self.narrator.speak(reply, voice: self.companion.resolvedVoice)
        }
    }

    func requestHint() {
        lastInteractionAt = Date()
        stepHintsUsed += 1
        guard let step = currentStep else { return }
        let hint = slot.difficulty.hint(for: step, companionID: companion.id)
        narrator.speak(hint, voice: companion.resolvedVoice)
    }

    // MARK: - Progress

    private func completeCurrentStep(targetID: String, kind: ActivityKind) {
        guard let completed = slot.progress.completeStepIfTargeted(entityID: targetID, in: pack) else { return }
        events.record(GameEvent(tick: tick, kind: .stepCompleted,
                                spoken: completed.celebration.resolved(for: companion.id)))
        if completed.goal == .collect {
            audio.removeSource(id: targetID)
        }
        worldRevision += 1
        recordTelemetry(kind: kind, succeeded: true)

        var speech = completed.celebration.resolved(for: companion.id)

        let questDone = slot.progress.activeQuest(in: pack)
            .map { slot.progress.isQuestComplete($0) } ?? false
        SoundBank.shared.play(questDone ? "celebrate_quest.wav" : "celebrate_step.wav")
        SoundBank.shared.playCue("celebrate", companion: companion, volume: 0.8)

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

        narrator.speak(speech, voice: companion.resolvedVoice)
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
