import Foundation

/// Pure timing math shared by every TTS path. Word boundaries here MUST
/// mirror NarrationTextView's rule — split on single spaces, cumulative
/// UTF-16 offsets — or the reading highlight would drift off the tappable
/// word buttons. Change one only with the other.
public enum TTSTimingMapper {
    /// ElevenLabs character alignment → word timings over the ORIGINAL text.
    /// Defensive by design: if the joined alignment characters don't
    /// reconstruct the text exactly (normalization, service quirks), the
    /// offsets can't be trusted, so we quietly fall back to estimate() —
    /// a slightly-off highlight beats a wrong one.
    public static func wordTimings(text: String, characters: [String],
                                   starts: [Double], ends: [Double]) -> [TTSWordTiming] {
        guard characters.count == starts.count, characters.count == ends.count,
              characters.joined() == text else {
            return estimate(text: text, totalDuration: ends.last ?? 0)
        }
        let slots = wordSlots(in: text)
        guard !slots.isEmpty else { return [] }

        // UTF-16 offset of each alignment entry; an entry may span several
        // UTF-16 units (emoji arrive as one alignment character).
        var offsets: [Int] = []
        offsets.reserveCapacity(characters.count)
        var cursor = 0
        for character in characters {
            offsets.append(cursor)
            cursor += character.utf16.count
        }

        var result: [TTSWordTiming] = []
        var index = 0
        for slot in slots {
            // Skip the separators before this word, then absorb every entry
            // it overlaps. Both sequences are ordered, so one linear pass.
            while index < characters.count,
                  offsets[index] + characters[index].utf16.count <= slot.location {
                index += 1
            }
            var wordStart: Double?
            var wordEnd: Double?
            while index < characters.count, offsets[index] < slot.location + slot.length {
                if wordStart == nil { wordStart = starts[index] }
                wordEnd = max(wordEnd ?? ends[index], ends[index])
                index += 1
            }
            guard let start = wordStart, let end = wordEnd else {
                // Alignment ran dry mid-text — impossible when joined == text,
                // but a wrong highlight is never worth a crash.
                return estimate(text: text, totalDuration: ends.last ?? 0)
            }
            result.append(TTSWordTiming(location: slot.location, length: slot.length,
                                        start: start, duration: max(0, end - start)))
        }
        return result
    }

    /// No-timestamp fallback: spread the audio duration across the words,
    /// proportional to UTF-16 length with a per-word floor (so "a" doesn't
    /// flash by) and extra weight after sentence punctuation (the voice
    /// pauses there; the highlight should linger with it).
    public static func estimate(text: String, totalDuration: TimeInterval) -> [TTSWordTiming] {
        let slots = wordSlots(in: text)
        guard !slots.isEmpty, totalDuration > 0 else { return [] }

        let weights = slots.map { slot -> Double in
            var weight = max(Double(slot.length), minimumWordWeight)
            if endsSentence(slot.text) { weight += sentencePauseWeight }
            return weight
        }
        let totalWeight = weights.reduce(0, +)

        var clock: TimeInterval = 0
        var result: [TTSWordTiming] = []
        for (slot, weight) in zip(slots, weights) {
            let duration = totalDuration * weight / totalWeight
            result.append(TTSWordTiming(location: slot.location, length: slot.length,
                                        start: clock, duration: duration))
            clock += duration
        }
        return result
    }

    // MARK: - Word boundaries (NarrationTextView's rule)

    struct WordSlot: Equatable {
        var text: String
        var location: Int
        var length: Int
    }

    /// Split on single spaces with cumulative UTF-16 offsets — byte-for-byte
    /// the layout NarrationTextView builds its word buttons from. Empty
    /// pieces (consecutive spaces) still advance the offset but can never be
    /// highlighted, so they get no timing.
    static func wordSlots(in text: String) -> [WordSlot] {
        var result: [WordSlot] = []
        var location = 0
        for piece in text.components(separatedBy: " ") {
            let length = piece.utf16.count
            if !piece.isEmpty {
                result.append(WordSlot(text: piece, location: location, length: length))
            }
            location += length + 1
        }
        return result
    }

    // MARK: - Weighting

    /// Floor in UTF-16-length units, not seconds — proportional weights can
    /// never overshoot the real audio duration the way a fixed floor could.
    private static let minimumWordWeight = 2.0
    private static let sentencePauseWeight = 3.0
    private static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]
    private static let trailingWrappers: Set<Character> = ["\"", "'", ")", "]", "\u{201D}", "\u{2019}"]

    private static func endsSentence(_ word: String) -> Bool {
        var trimmed = Substring(word)
        while let last = trimmed.last, trailingWrappers.contains(last) {
            trimmed = trimmed.dropLast()
        }
        guard let last = trimmed.last else { return false }
        return sentenceEnders.contains(last)
    }
}
