import Foundation

/// Deterministic fallback so the game is fully playable with no AI configured
/// at all — on a plane, on a school iPad, before any model is set up.
/// Every LLM provider is strictly an upgrade on top of this. Answers come
/// from the world snapshot, so they are situationally aware: directions,
/// distances, locked reasons, and ability findings are all real.
public struct ScriptedBrain: CompanionBrain {
    public init() {}

    public func reply(to utterance: String, context: CompanionContext) async throws -> String {
        answer(utterance, context: context)
    }

    /// Synchronous core — also used by the freeze-and-explain overlay and
    /// anywhere an instant reply is needed.
    public func answer(_ utterance: String, context: CompanionContext) -> String {
        let companion = context.companion
        let snapshot = context.snapshot
        let intent = IntentClassifier.classify(utterance, companion: companion, snapshot: snapshot)
        var subs: [String: String] = ["childName": context.childName]
        let key: String

        switch intent {
        case .whoAreYou:
            subs["abilityDescription"] = companion.abilities.first?.spokenDescription ?? ""
            key = "whoAreYou"

        case .whereAmI:
            subs["scene"] = snapshot.sceneName
            subs["sceneDescription"] = snapshot.sceneDescription
            key = "whereAmI"

        case .whatDoIHear:
            let audible = snapshot.perceived.filter { $0.isAudible && !$0.isAnonymousTease }.prefix(4)
            let described = audible.compactMap { entity -> String? in
                guard let sound = entity.soundDescription else { return nil }
                return "\(sound) \(entity.direction.spoken)"
            }
            if described.isEmpty {
                subs["ambient"] = snapshot.ambientSounds.isEmpty
                    ? "the quiet" : snapshot.ambientSounds.joined(separator: " and ")
                key = "whatDoIHearQuiet"
            } else {
                subs["list"] = joinSpoken(described)
                key = "whatDoIHear"
            }

        case .whereIs(let name), .canIGo(let name):
            let isGo = { if case .canIGo = intent { return true } else { return false } }()
            if let entity = snapshot.perceived.first(where: { $0.name == name && !name.isEmpty }) {
                subs["target"] = entity.name
                subs["direction"] = entity.direction.spoken
                subs["distance"] = entity.spokenDistance
                if entity.isLocked, let reason = entity.lockedExplanation {
                    subs["reason"] = reason
                    key = isGo ? "canIGoLocked" : "whereIsLocked"
                } else {
                    key = isGo ? "canIGoOpen" : "whereIsFound"
                }
            } else {
                key = isGo ? "canIGoUnknown" : "whereIsUnknown"
            }

        case .whatDoIDo:
            if let quest = snapshot.activeQuest {
                subs["quest"] = quest.summary
                key = "whatDoIDo"
            } else {
                key = "whatDoIDoNoQuest"
            }

        case .help:
            if let hint = snapshot.activeQuest?.currentHint {
                subs["hint"] = hint
                key = "help"
            } else {
                key = "helpNoHint"
            }

        case .remember:
            if let memory = context.recentMemories.first {
                subs["memory"] = memory
                key = "remember"
            } else {
                key = "rememberNone"
            }

        case .whatHappened:
            if snapshot.recentEvents.isEmpty {
                key = "whatHappenedNone"
            } else {
                subs["events"] = joinSpoken(Array(snapshot.recentEvents.prefix(3)))
                key = "whatHappened"
            }

        case .abilitySense:
            if snapshot.abilityFindings.isEmpty {
                subs["abilityName"] = companion.abilities.first?.name ?? "special sense"
                key = "abilitySenseNone"
            } else {
                subs["findings"] = snapshot.abilityFindings.joined(separator: " ")
                key = "abilitySense"
            }

        case .fallback:
            if let quest = snapshot.activeQuest {
                subs["quest"] = quest.summary
                key = "fallback"
            } else {
                key = "fallbackNoQuest"
            }
        }

        return TemplateRenderer.render(intentKey: key, utterance: utterance,
                                       companion: companion, substitutions: subs)
    }

    private func joinSpoken(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }
}
