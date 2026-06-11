import Foundation

/// Renders a companion's per-intent phrase templates with substitutions.
/// Template choice is deterministic (stable hash of the utterance) so tests
/// are reproducible but answers vary across different questions. Companions
/// missing an intent key fall back to built-in defaults, so a minimal
/// companion definition is fully playable.
public enum TemplateRenderer {
    public static func render(intentKey: String, utterance: String,
                              companion: Companion,
                              substitutions: [String: String]) -> String {
        let templates = companion.speechStyle.templates[intentKey]
            ?? defaultTemplates[intentKey]
            ?? ["{exclamation} I'm right here with you, {childName}."]
        let index = Int(stableHash(utterance) % UInt64(templates.count))
        var result = templates[index]

        var allSubstitutions = substitutions
        allSubstitutions["companionName"] = companion.name
        allSubstitutions["species"] = companion.species
        allSubstitutions["exclamation"] = companion.speechStyle.exclamation
        for (key, value) in allSubstitutions {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    /// FNV-1a — Swift's Hasher is seeded per process, so it can't be used
    /// for reproducible template selection.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    public static let defaultTemplates: [String: [String]] = [
        "whoAreYou": [
            "{exclamation} I'm {companionName}, your {species}! {abilityDescription} I go where you go, {childName}.",
        ],
        "whereAmI": [
            "We're in {scene}. {sceneDescription}",
        ],
        "whatDoIHear": [
            "Listen with me, {childName}... I hear {list}.",
            "{exclamation} I hear {list}.",
        ],
        "whatDoIHearQuiet": [
            "It's peaceful right now, {childName}. Just {ambient}.",
            "Shh... only {ambient} right now.",
        ],
        "whereIsFound": [
            "The {target} is {direction}, {distance}.",
            "{exclamation} The {target}? It's {direction}, {distance}.",
        ],
        "whereIsLocked": [
            "The {target} is {direction} — but {reason}",
        ],
        "whereIsUnknown": [
            "Hmm, I haven't found that from here, {childName}. Let's keep listening and exploring!",
        ],
        "canIGoOpen": [
            "Yes! The {target} is {direction}, {distance}. Let's go, {childName}!",
        ],
        "canIGoLocked": [
            "We can someday, {childName} — but not yet. {reason}",
        ],
        "canIGoUnknown": [
            "We can try! Follow the sounds, {childName}, and I'll stay right beside you.",
        ],
        "whatDoIDo": [
            "Here's our quest, {childName}: {quest}",
            "{exclamation} Remember our quest? {quest}",
        ],
        "whatDoIDoNoQuest": [
            "Right now we're just exploring, {childName}. Follow any sound that makes you curious!",
        ],
        "help": [
            "{exclamation} Try this: {hint}",
            "Don't worry, {childName} — {hint}",
        ],
        "helpNoHint": [
            "Stop and listen for a moment, {childName}. The world will tell you where to go.",
        ],
        "remember": [
            "{memory} I remember it well, {childName}!",
        ],
        "rememberNone": [
            "Our adventure is just beginning, {childName}. Soon we'll have so much to remember!",
        ],
        "whatHappened": [
            "Let me think... {events}",
        ],
        "whatHappenedNone": [
            "Nothing new just yet, {childName}. Our story is waiting for us!",
        ],
        "abilitySense": [
            "{exclamation} {findings}",
        ],
        "abilitySenseNone": [
            "My {abilityName} doesn't find anything hidden right now, {childName}. Let's explore somewhere new!",
        ],
        "fallback": [
            "Hmm, I'm not sure about that one, {childName}. But remember — {quest}",
        ],
        "fallbackNoQuest": [
            "Let's keep exploring, {childName}. I'm right here with you.",
        ],
    ]
}
