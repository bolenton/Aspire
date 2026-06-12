import XCTest
@testable import StoryEngine

final class TTSTimingMapperTests: XCTestCase {
    /// Synthetic ElevenLabs-style alignment: one entry per grapheme cluster
    /// (how the service sends emoji), `step` seconds each, gapless.
    private func alignment(for text: String, step: Double = 0.1)
        -> (characters: [String], starts: [Double], ends: [Double]) {
        let characters = text.map(String.init)
        let starts = (0..<characters.count).map { Double($0) * step }
        let ends = (1...characters.count).map { Double($0) * step }
        return (characters, starts, ends)
    }

    private func substring(of text: String, _ timing: TTSWordTiming) -> String {
        (text as NSString).substring(
            with: NSRange(location: timing.location, length: timing.length))
    }

    // MARK: - Alignment mapping

    func testSurrogatePairOffsetsStayNSRangeCompatible() {
        // The fox emoji is one alignment character but TWO UTF-16 units —
        // offsets after it must account for both or the highlight drifts.
        let text = "Go 🦊 now!"
        let aligned = alignment(for: text)
        let timings = TTSTimingMapper.wordTimings(
            text: text, characters: aligned.characters,
            starts: aligned.starts, ends: aligned.ends)

        XCTAssertEqual(timings.count, 3)
        XCTAssertEqual(timings[0].location, 0)
        XCTAssertEqual(timings[0].length, 2)
        XCTAssertEqual(timings[1].location, 3)
        XCTAssertEqual(timings[1].length, 2)
        XCTAssertEqual(timings[2].location, 6)
        XCTAssertEqual(timings[2].length, 4)
        XCTAssertEqual(substring(of: text, timings[0]), "Go")
        XCTAssertEqual(substring(of: text, timings[1]), "🦊")
        XCTAssertEqual(substring(of: text, timings[2]), "now!")

        // Entries are 0.1 s each: "🦊" is the 4th entry, "now!" entries 6–9.
        XCTAssertEqual(timings[1].start, 0.3, accuracy: 1e-9)
        XCTAssertEqual(timings[1].duration, 0.1, accuracy: 1e-9)
        XCTAssertEqual(timings[2].start, 0.5, accuracy: 1e-9)
        XCTAssertEqual(timings[2].duration, 0.4, accuracy: 1e-9)
    }

    func testMultiSpaceRangesMatchNarrationTextView() {
        // Consecutive spaces produce an empty piece in NarrationTextView's
        // split; it still occupies an offset slot but gets no timing.
        let text = "Hello  world"
        let aligned = alignment(for: text)
        let timings = TTSTimingMapper.wordTimings(
            text: text, characters: aligned.characters,
            starts: aligned.starts, ends: aligned.ends)

        XCTAssertEqual(timings.count, 2)
        XCTAssertEqual(timings[0].location, 0)
        XCTAssertEqual(timings[0].length, 5)
        XCTAssertEqual(timings[1].location, 7)
        XCTAssertEqual(timings[1].length, 5)
        XCTAssertEqual(substring(of: text, timings[1]), "world")
    }

    func testMismatchedAlignmentFallsBackToEstimate() {
        // Joined characters don't reconstruct the text → offsets are
        // untrustworthy → result must be exactly the estimate over the
        // alignment's total duration.
        let text = "Hello world"
        let timings = TTSTimingMapper.wordTimings(
            text: text, characters: ["H", "i"], starts: [0.0, 0.5], ends: [0.5, 2.0])
        XCTAssertEqual(timings, TTSTimingMapper.estimate(text: text, totalDuration: 2.0))
        XCTAssertFalse(timings.isEmpty)
    }

    func testMismatchedArrayCountsFallBackToEstimate() {
        let text = "Hi"
        let timings = TTSTimingMapper.wordTimings(
            text: text, characters: ["H", "i"], starts: [0.0], ends: [1.0])
        XCTAssertEqual(timings, TTSTimingMapper.estimate(text: text, totalDuration: 1.0))
    }

    func testEmptyTextProducesNoTimings() {
        XCTAssertEqual(TTSTimingMapper.wordTimings(text: "", characters: [],
                                                   starts: [], ends: []), [])
    }

    func testFullCoverageInvariants() {
        // Emoji, punctuation, and a double space in one line: every
        // non-empty word gets exactly one timing, in order, and every range
        // round-trips through NSString to the exact word button text.
        let text = "The 🦊 ran  far! Then… it stopped."
        let aligned = alignment(for: text, step: 0.07)
        let timings = TTSTimingMapper.wordTimings(
            text: text, characters: aligned.characters,
            starts: aligned.starts, ends: aligned.ends)

        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        XCTAssertEqual(timings.count, words.count)

        let textLength = (text as NSString).length
        for (timing, word) in zip(timings, words) {
            XCTAssertEqual(substring(of: text, timing), word)
            XCTAssertLessThanOrEqual(timing.location + timing.length, textLength)
            XCTAssertGreaterThanOrEqual(timing.duration, 0)
        }
        for (earlier, later) in zip(timings, timings.dropFirst()) {
            XCTAssertLessThan(earlier.location, later.location)
            XCTAssertLessThanOrEqual(earlier.start, later.start)
        }
    }

    // MARK: - Estimation

    func testEstimateCoversFullDurationInOrder() {
        let text = "We made it to the glowing gate"
        let timings = TTSTimingMapper.estimate(text: text, totalDuration: 6.0)

        XCTAssertEqual(timings.count, 7)
        XCTAssertEqual(timings[0].start, 0, accuracy: 1e-9)
        var clock = 0.0
        for timing in timings {
            XCTAssertEqual(timing.start, clock, accuracy: 1e-9)
            clock += timing.duration
        }
        XCTAssertEqual(clock, 6.0, accuracy: 1e-9)
    }

    func testSentencePunctuationEarnsExtraTime() {
        // Same UTF-16 length, only the sentence-ending bang differs — the
        // voice pauses there, so the highlight must linger there.
        let timings = TTSTimingMapper.estimate(text: "ahoy! ahoyx", totalDuration: 10)
        XCTAssertEqual(timings.count, 2)
        XCTAssertGreaterThan(timings[0].duration, timings[1].duration)
    }

    func testPerWordFloorProtectsTinyWords() {
        // Pure length proportion would give "a" 1/13 of the time; the floor
        // must grant it more so it doesn't flash by.
        let timings = TTSTimingMapper.estimate(text: "a gigantically", totalDuration: 10)
        XCTAssertEqual(timings.count, 2)
        XCTAssertGreaterThan(timings[0].duration, 10.0 * 1.0 / 13.0)
    }

    func testEstimateEdgeCases() {
        XCTAssertEqual(TTSTimingMapper.estimate(text: "", totalDuration: 5), [])
        XCTAssertEqual(TTSTimingMapper.estimate(text: "   ", totalDuration: 5), [])
        XCTAssertEqual(TTSTimingMapper.estimate(text: "hi there", totalDuration: 0), [])
    }

    func testEstimateRangesMatchNarrationTextView() {
        let text = "Look — a 🦋 landed!"
        let timings = TTSTimingMapper.estimate(text: text, totalDuration: 3)
        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        XCTAssertEqual(timings.count, words.count)
        for (timing, word) in zip(timings, words) {
            XCTAssertEqual(substring(of: text, timing), word)
        }
    }
}
