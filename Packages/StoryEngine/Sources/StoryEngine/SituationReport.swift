import Foundation

/// The "freeze and explain" readout: a pure, deterministic rendering of the
/// snapshot, spoken when she holds two fingers anywhere. No LLM involved —
/// it must work instantly, offline, identically every time.
public enum SituationReport {
    /// Spoken entities are capped so the readout stays digestible; the quest
    /// target and ability findings are always included.
    public static let spokenEntityCap = 6

    public static func spoken(from snapshot: WorldSnapshot, companion: Companion,
                              childName: String) -> String {
        var sentences: [String] = []
        sentences.append("You are in \(snapshot.sceneName).")

        for entity in snapshot.perceived.prefix(spokenEntityCap) {
            sentences.append(sentence(for: entity, companion: companion))
        }

        if let quest = snapshot.activeQuest, let target = quest.targetName {
            if let direction = quest.targetDirection {
                sentences.append("Remember, we're looking for the \(target) — it's \(direction.spoken).")
            } else {
                sentences.append("Remember, we're looking for the \(target).")
            }
        }

        for finding in snapshot.abilityFindings {
            sentences.append(finding)
        }

        return sentences.joined(separator: " ")
    }

    static func sentence(for entity: PerceivedEntity, companion: Companion) -> String {
        if entity.isAnonymousTease {
            let tease = entity.teaseLine ?? "There's something I can't quite make out"
            return "\(tease) It's \(entity.direction.spoken), \(entity.spokenDistance)."
        }

        let subject: String
        switch entity.kind {
        case .companion, .character:
            subject = entity.name
        case .landmark, .item, .portal:
            subject = "The \(entity.name)"
        }

        var sentence = "\(subject) is \(entity.direction.spoken)"
        if let suffix = entity.elevation.spokenSuffix { sentence += ", \(suffix)" }
        sentence += ", \(entity.spokenDistance)"
        if let sound = entity.soundDescription { sentence += " — you can hear \(sound)" }
        sentence += "."
        if entity.isLocked, let reason = entity.lockedExplanation {
            sentence += " \(reason)"
        }
        return sentence
    }
}
