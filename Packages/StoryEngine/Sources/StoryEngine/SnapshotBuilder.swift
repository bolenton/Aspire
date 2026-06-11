import Foundation

/// Pure function of its inputs — no clocks, no globals, fully testable.
/// The app builds a snapshot when an utterance finalizes (using the pose
/// sampled at speech start) and keeps a throttled cached one for the debug
/// overlay and instant scripted replies.
public enum SnapshotBuilder {
    /// Silent landmarks are still perceivable within this radius.
    public static let landmarkRadius: Double = 20
    public static let perceivedCap = 10
    public static let eventsCap = 5

    public static func build(pack: StoryPack, companion: Companion, scene: Scene,
                             pose: PlayerPose, progress: GameProgress,
                             events: EventLog, support: SupportLevel,
                             tick: TimeInterval) -> WorldSnapshot {
        let currentStep = progress.currentStep(in: pack)
        let hearingMultiplier = companion.audibleRangeMultiplier
        var findings: [String] = []

        var perceived: [PerceivedEntity] = scene.activeEntities(companion: companion).compactMap { resolved in
            let entity = resolved.entity
            let distance = pose.position.distance(to: entity.position)
            let direction = direction(from: pose, to: entity.position)
            let elevation = elevation(from: pose.position, to: entity.position)
            let isQuestTarget = currentStep?.targetEntityID == entity.id

            let audibleRange = (entity.sound?.farRadius ?? 0) * hearingMultiplier
            let isAudible = entity.sound != nil && distance <= audibleRange
            guard isAudible || distance <= landmarkRadius || isQuestTarget else { return nil }

            if resolved.isAnonymousTease {
                return PerceivedEntity(
                    entityID: entity.id, name: "something hidden", kind: entity.kind,
                    direction: direction, elevation: elevation,
                    distanceMeters: distance,
                    spokenDistance: SnapshotPhrasing.spokenDistance(distance),
                    isAudible: false, isQuestTarget: false,
                    isAnonymousTease: true, teaseLine: entity.hiddenTease)
            }

            if resolved.revealedByAbilityID != nil,
               let senseLine = entity.senseLine?.resolved(for: companion.id) {
                findings.append(senseLine)
            }

            let name = entity.id == StoryConventions.companionPlaceholder ? companion.name : entity.name
            let availability = progress.availability(of: entity)
            return PerceivedEntity(
                entityID: entity.id, name: name, kind: entity.kind,
                direction: direction, elevation: elevation,
                distanceMeters: distance,
                spokenDistance: SnapshotPhrasing.spokenDistance(distance),
                isAudible: isAudible,
                soundDescription: isAudible ? entity.sound?.spokenDescription : nil,
                isQuestTarget: isQuestTarget,
                isLocked: !availability.available,
                lockedExplanation: availability.explanation,
                revealedByAbilityID: resolved.revealedByAbilityID)
        }

        perceived.sort { a, b in
            if a.isQuestTarget != b.isQuestTarget { return a.isQuestTarget }
            if (a.revealedByAbilityID != nil) != (b.revealedByAbilityID != nil) {
                return a.revealedByAbilityID != nil
            }
            return a.distanceMeters < b.distanceMeters
        }
        if perceived.count > perceivedCap {
            perceived = Array(perceived.prefix(perceivedCap))
        }

        return WorldSnapshot(
            tick: tick,
            sceneID: scene.id,
            sceneName: scene.name,
            sceneDescription: scene.spokenDescription.resolved(for: companion.id),
            pose: pose,
            perceived: perceived,
            ambientSounds: scene.ambience.compactMap(\.spokenDescription),
            activeQuest: questSnapshot(pack: pack, companion: companion, scene: scene,
                                       pose: pose, progress: progress, support: support),
            recentEvents: events.recent(limit: eventsCap).map(\.spoken),
            support: support,
            abilityFindings: findings)
    }

    static func direction(from pose: PlayerPose, to target: Vec3) -> CompassDirection8 {
        let dx = target.x - pose.position.x
        let dz = target.z - pose.position.z
        guard dx != 0 || dz != 0 else { return .ahead }
        let worldBearing = atan2(dx, -dz) * 180 / .pi
        return CompassDirection8.from(relativeBearing: worldBearing - pose.headingDegrees)
    }

    static func elevation(from position: Vec3, to target: Vec3) -> ElevationBand {
        let dy = target.y - position.y
        if dy > 2 { return .above }
        if dy < -2 { return .below }
        return .level
    }

    private static func questSnapshot(pack: StoryPack, companion: Companion,
                                      scene: Scene, pose: PlayerPose,
                                      progress: GameProgress,
                                      support: SupportLevel) -> QuestSnapshot? {
        guard let quest = progress.activeQuest(in: pack),
              let step = progress.currentStep(in: pack) else { return nil }
        let hintIndex = step.hintLadder.isEmpty ? nil : min(support.hintTier, step.hintLadder.count - 1)
        let hint = hintIndex.map { step.hintLadder[$0].resolved(for: companion.id) }
            ?? step.intro.resolved(for: companion.id)

        var targetName: String?
        var targetDirection: CompassDirection8?
        if let target = scene.entities.first(where: { $0.id == step.targetEntityID }) {
            targetName = target.id == StoryConventions.companionPlaceholder ? companion.name : target.name
            targetDirection = direction(from: pose, to: target.position)
        }
        return QuestSnapshot(
            title: quest.title,
            summary: quest.spokenSummary.resolved(for: companion.id),
            stepIntro: step.intro.resolved(for: companion.id),
            currentHint: hint,
            goal: step.goal,
            targetName: targetName,
            targetDirection: targetDirection)
    }
}
