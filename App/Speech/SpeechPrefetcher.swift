import Foundation
import StoryEngine

/// Warms the speech cache ahead of the child so premium lines play instantly
/// instead of pausing on the network. Serial and low-priority by design: it
/// must never compete with the line she's hearing right now, and it skips
/// anything already cached so a re-entered scene costs nothing.
///
/// Ownership: the Narrator owns one of these (`narrator.prefetcher`) and the
/// prefetcher reads the Narrator's live `cloudProvider` / `cache` / `profile`
/// at call time, so the integration in GameViewModel is a single line per
/// hook — see this type's doc and the workstream's publicAPI notes. When no
/// provider is configured every method is an immediate no-op.
@MainActor
final class SpeechPrefetcher {
    private unowned let narrator: Narrator
    /// One task at a time, cancellable as a whole on scene exit. Each new
    /// batch chains after the previous so synthesis stays strictly serial.
    private var task: Task<Void, Never>?

    init(narrator: Narrator) {
        self.narrator = narrator
    }

    // MARK: - Hooks (call sites in GameViewModel)

    /// Everything a scene's opening moments will speak: the scene description,
    /// the active quest's summary, and the current step's intro, celebration,
    /// and every hint rung (any of which an idle nudge or a "tell me again"
    /// can reach). Plus the WS5 nudge/boundary one-liners that play in this
    /// scene without warning.
    func prefetchScene(_ scene: Scene?, pack: StoryPack, companion: Companion,
                       step: QuestStep?, questSummary: String?,
                       extraLines: [String] = []) {
        guard provider != nil else { return }
        var lines: [String] = []
        if let scene { lines.append(scene.spokenDescription.resolved(for: companion.id)) }
        if let questSummary { lines.append(questSummary) }
        if let step { lines += stepLines(step, companion: companion) }
        lines += extraLines
        enqueue(lines, companion: companion)
    }

    /// The step she just unlocked — its intro, celebration, and hint ladder —
    /// so the moment-of-advance narration is already warm.
    func prefetchStep(_ step: QuestStep?, companion: Companion) {
        guard provider != nil, let step else { return }
        enqueue(stepLines(step, companion: companion), companion: companion)
    }

    /// A dialogue node plus one level ahead: the node's line and the line of
    /// the node each choice leads to, so her next tap never waits.
    func prefetchDialogue(_ node: DialogueNode?, pack: StoryPack, companion: Companion) {
        guard provider != nil, let node else { return }
        var lines = [node.line.resolved(for: companion.id)]
        for choice in node.choices {
            if let nextID = choice.nextDialogueID, let next = pack.dialogue(id: nextID) {
                lines.append(next.line.resolved(for: companion.id))
            }
        }
        enqueue(lines, companion: companion)
    }

    /// Drop pending work when leaving a scene — the next scene's lines matter,
    /// not this one's leftovers. (AI replies are never prefetched; the
    /// "thinking" cue covers their latency.)
    func cancelAll() {
        task?.cancel()
        task = nil
    }

    // MARK: - Internals

    private var provider: (any TTSProvider)? { narrator.cloudProvider }

    private func stepLines(_ step: QuestStep, companion: Companion) -> [String] {
        var lines = [step.intro.resolved(for: companion.id),
                     step.celebration.resolved(for: companion.id)]
        lines += step.hintLadder.map { $0.resolved(for: companion.id) }
        return lines
    }

    /// Chains a batch onto the serial task. Each line synthesizes only if its
    /// chosen cloud voice is set and it isn't already cached; cancellation
    /// (scene exit) stops the batch between lines.
    private func enqueue(_ lines: [String], companion: Companion) {
        let cloudVoiceID = companion.resolvedVoice.cloudVoiceID
        guard let voiceID = cloudVoiceID, !voiceID.isEmpty, !lines.isEmpty else { return }
        let previous = task
        let cache = narrator.cache
        let provider = self.provider
        let speechRate = narrator.profile.speechRate
        task = Task(priority: .utility) { [weak self] in
            _ = await previous?.value
            guard let provider else { return }
            let model = Self.model(of: provider)
            for line in lines {
                if Task.isCancelled { return }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = SpeechCache.Key(providerID: provider.providerID, voiceID: voiceID,
                                          model: model, speechRate: speechRate, text: line)
                if cache.contains(key) { continue }
                if let audio = try? await provider.synthesize(text: line, voiceID: voiceID) {
                    cache.store(audio, for: key)
                }
            }
            _ = self // keep the prefetcher alive for the batch's duration
        }
    }

    private static func model(of provider: any TTSProvider) -> String {
        if let eleven = provider as? ElevenLabsTTSProvider { return eleven.modelID }
        if let openAI = provider as? OpenAISpeechTTSProvider { return openAI.model }
        return ""
    }
}
