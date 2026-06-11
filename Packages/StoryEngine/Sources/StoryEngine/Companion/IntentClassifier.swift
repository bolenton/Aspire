import Foundation

public enum Intent: Equatable, Sendable {
    case whoAreYou
    case whereAmI
    case whatDoIHear
    /// Asking about a perceived entity by name; empty string = no match.
    case whereIs(String)
    case canIGo(String)
    case whatDoIDo
    case help
    case remember
    case whatHappened
    /// "What do you smell?" — matched against the companion's senseVerb.
    case abilitySense
    case fallback
}

/// Deterministic keyword intent matching for the scripted brain. Kept apart
/// from phrasing so both are individually testable.
public enum IntentClassifier {
    public static func classify(_ utterance: String, companion: Companion,
                                snapshot: WorldSnapshot) -> Intent {
        let text = utterance.lowercased()

        if text.contains("who are you") || text.contains("your name") || text.contains("what are you") {
            return .whoAreYou
        }
        if text.contains("where am i") || text.contains("where are we") {
            return .whereAmI
        }
        for ability in companion.abilities where text.contains(ability.senseVerb.lowercased()) {
            if text.contains("you") || text.contains("anything") {
                return .abilitySense
            }
        }
        if text.contains("hear") || text.contains("sound") || text.contains("listen") {
            return .whatDoIHear
        }
        if text.contains("happened") || text.contains("just now") {
            return .whatHappened
        }
        if text.contains("remember") || text.contains("last time") {
            return .remember
        }
        if text.contains("can i go") || text.contains("can we go") || text.contains("go to")
            || text.contains("let's go") || text.contains("lets go") {
            return .canIGo(matchedEntityName(in: text, snapshot: snapshot) ?? "")
        }
        if text.contains("where is") || text.contains("where's") || text.contains("where are")
            || text.contains("how do i get") || text.contains("find the") {
            return .whereIs(matchedEntityName(in: text, snapshot: snapshot) ?? "")
        }
        if text.contains("supposed to") || text.contains("what do i do")
            || text.contains("what should i do") || text.contains("what now")
            || text.contains("quest") || text.contains("objective") {
            return .whatDoIDo
        }
        if text.contains("help") || text.contains("stuck") || text.contains("hint")
            || text.contains("lost") {
            return .help
        }
        // A bare entity name ("the river?") counts as asking where it is.
        if let name = matchedEntityName(in: text, snapshot: snapshot) {
            return .whereIs(name)
        }
        return .fallback
    }

    /// Fuzzy match: any significant word of a perceived entity's name
    /// appearing in the utterance. Anonymous teases never match by name.
    static func matchedEntityName(in text: String, snapshot: WorldSnapshot) -> String? {
        for entity in snapshot.perceived where !entity.isAnonymousTease {
            let words = entity.name.lowercased().split(separator: " ").filter { $0.count > 3 }
            if words.contains(where: { text.contains($0) }) {
                return entity.name
            }
        }
        return nil
    }
}
