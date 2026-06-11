import Foundation

/// Where she is in the story: active quest, completed steps, flags, inventory.
/// Pure state machine — no Apple frameworks, fully testable.
public struct GameProgress: Codable, Equatable, Sendable {
    public var storyPackID: String
    public var currentSceneID: String
    public var activeQuestID: String?
    public var completedStepIDs: [String]
    public var flags: Set<String>
    public var inventory: [String]

    public init(storyPackID: String, currentSceneID: String, activeQuestID: String? = nil,
                completedStepIDs: [String] = [], flags: Set<String> = [], inventory: [String] = []) {
        self.storyPackID = storyPackID
        self.currentSceneID = currentSceneID
        self.activeQuestID = activeQuestID
        self.completedStepIDs = completedStepIDs
        self.flags = flags
        self.inventory = inventory
    }

    public func activeQuest(in pack: StoryPack) -> Quest? {
        guard let id = activeQuestID else { return nil }
        return pack.quests.first { $0.id == id }
    }

    public func currentStep(in pack: StoryPack) -> QuestStep? {
        guard let quest = activeQuest(in: pack) else { return nil }
        return quest.steps.first { !completedStepIDs.contains($0.id) }
    }

    public func isQuestComplete(_ quest: Quest) -> Bool {
        quest.steps.allSatisfy { completedStepIDs.contains($0.id) }
    }

    /// Whether an entity is usable yet (e.g. the castle portal needs the
    /// bridge repaired). Returns the explanation to speak when it is not.
    public func availability(of entity: Entity) -> (available: Bool, explanation: String?) {
        guard let flag = entity.requiresFlag, !flags.contains(flag) else {
            return (true, nil)
        }
        return (false, entity.lockedExplanation)
    }

    /// Completes the current step if `entityID` is its target. Returns the
    /// completed step so callers can speak its celebration line.
    @discardableResult
    public mutating func completeStepIfTargeted(entityID: String, in pack: StoryPack) -> QuestStep? {
        guard let step = currentStep(in: pack), step.targetEntityID == entityID else { return nil }
        completedStepIDs.append(step.id)
        if let flag = step.setsFlag { flags.insert(flag) }
        if step.goal == .collect { inventory.append(entityID) }
        return step
    }
}
