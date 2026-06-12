import XCTest
@testable import StoryEngine

final class IntentClassifierTests: XCTestCase {
    func testCoreIntents() {
        let snapshot = Fixtures.snapshot()
        let ember = Fixtures.ember

        XCTAssertEqual(IntentClassifier.classify("Who are you?", companion: ember, snapshot: snapshot), .whoAreYou)
        XCTAssertEqual(IntentClassifier.classify("Where am I?", companion: ember, snapshot: snapshot), .whereAmI)
        XCTAssertEqual(IntentClassifier.classify("What do you hear?", companion: ember, snapshot: snapshot), .whatDoIHear)
        XCTAssertEqual(IntentClassifier.classify("What am I supposed to do?", companion: ember, snapshot: snapshot), .whatDoIDo)
        XCTAssertEqual(IntentClassifier.classify("I'm stuck, help!", companion: ember, snapshot: snapshot), .help)
        XCTAssertEqual(IntentClassifier.classify("Do you remember the fisherman?", companion: ember, snapshot: snapshot), .remember)
        XCTAssertEqual(IntentClassifier.classify("What just happened?", companion: ember, snapshot: snapshot), .whatHappened)
    }

    func testSenseVerbRoutesToAbilityOnlyForOwner() {
        let snapshot = Fixtures.snapshot()
        XCTAssertEqual(IntentClassifier.classify("What do you smell?", companion: Fixtures.ember, snapshot: snapshot), .abilitySense)
        // Petal has no smell ability — same words shouldn't trigger hers.
        XCTAssertNotEqual(IntentClassifier.classify("What do you smell?", companion: Fixtures.petal, snapshot: snapshot), .abilitySense)
        // Plain hearing question stays the hearing intent, even for Clover.
        XCTAssertEqual(IntentClassifier.classify("What do you hear?", companion: Fixtures.clover, snapshot: snapshot), .whatDoIHear)
        XCTAssertEqual(IntentClassifier.classify("What do your ears hear?", companion: Fixtures.clover, snapshot: snapshot), .abilitySense)
    }

    func testEntityNameExtraction() {
        let snapshot = Fixtures.snapshot()
        XCTAssertEqual(IntentClassifier.classify("Can I go to the castle?", companion: Fixtures.ember, snapshot: snapshot), .canIGo("castle gate"))
        XCTAssertEqual(IntentClassifier.classify("Where is the river?", companion: Fixtures.ember, snapshot: snapshot), .whereIs("river"))
        XCTAssertEqual(IntentClassifier.classify("Can we go to the moon?", companion: Fixtures.ember, snapshot: snapshot), .canIGo(""))
        // A bare entity name counts as asking where it is.
        XCTAssertEqual(IntentClassifier.classify("The river?", companion: Fixtures.ember, snapshot: snapshot), .whereIs("river"))
    }
}

final class TemplateRendererTests: XCTestCase {
    func testSubstitutionAndDefaults() {
        let reply = TemplateRenderer.render(intentKey: "whereIsFound", utterance: "where is the river",
                                            companion: Fixtures.ember,
                                            substitutions: ["target": "river",
                                                            "direction": "to your right",
                                                            "distance": "about 12 big steps away",
                                                            "childName": "Aria"])
        XCTAssertTrue(reply.contains("river"))
        XCTAssertTrue(reply.contains("to your right"))
        XCTAssertFalse(reply.contains("{"))
    }

    func testDeterministicSelection() {
        let first = TemplateRenderer.render(intentKey: "help", utterance: "help me",
                                            companion: Fixtures.ember, substitutions: ["hint": "h", "childName": "A"])
        let second = TemplateRenderer.render(intentKey: "help", utterance: "help me",
                                             companion: Fixtures.ember, substitutions: ["hint": "h", "childName": "A"])
        XCTAssertEqual(first, second)
    }

    func testCompanionTemplateOverridesDefault() {
        var styled = Fixtures.ember
        styled.speechStyle.templates["help"] = ["{exclamation} Sniff sniff... {hint}"]
        let reply = TemplateRenderer.render(intentKey: "help", utterance: "help",
                                            companion: styled,
                                            substitutions: ["hint": "follow the creak", "childName": "Aria"])
        XCTAssertEqual(reply, "Yip! Sniff sniff... follow the creak")
    }
}

final class ScriptedBrainTests: XCTestCase {
    private let brain = ScriptedBrain()

    func testCanIGoCastleExplainsBrokenBridge() {
        let reply = brain.answer("Can I go to the castle?", context: Fixtures.context())
        XCTAssertTrue(reply.contains("The bridge to the castle is still broken."), reply)
    }

    func testWhereIsRiverGivesDirectionAndDistance() {
        let reply = brain.answer("Where is the river?", context: Fixtures.context())
        XCTAssertTrue(reply.contains("to your right"), reply)
        XCTAssertTrue(reply.contains("about 12 big steps away"), reply)
    }

    func testWhatDoIHearEnumeratesRealSounds() {
        let reply = brain.answer("What do you hear?", context: Fixtures.context())
        XCTAssertTrue(reply.contains("flowing water to your right"), reply)
        XCTAssertTrue(reply.contains("creaking wood straight ahead"), reply)
    }

    func testUnknownPlaceNeverConfirmsCanon() {
        let reply = brain.answer("Can I go to the dragon's volcano?", context: Fixtures.context())
        XCTAssertTrue(reply.contains("Follow the sounds"), reply)
        XCTAssertFalse(reply.lowercased().contains("volcano"), reply)
    }

    func testAbilitySenseSpeaksFindings() {
        let reply = brain.answer("What do you smell?", context: Fixtures.context())
        XCTAssertTrue(reply.contains("My nose found something buried near the big root!"), reply)
    }

    func testQuestAndHintAnswers() {
        let context = Fixtures.context()
        XCTAssertTrue(brain.answer("What am I supposed to do?", context: context)
            .contains("We promised the old oak"), "quest summary expected")
        XCTAssertTrue(brain.answer("I need a hint", context: context)
            .contains("creaking"), "tier-1 hint expected")
    }

    func testMemoryRecall() {
        let context = Fixtures.context(memories: ["Last time you helped the fisherman."])
        let reply = brain.answer("Do you remember last time?", context: context)
        XCTAssertTrue(reply.contains("Last time you helped the fisherman."), reply)
    }

    func testRepliesUseChildName() {
        let reply = brain.answer("hello there friend", context: Fixtures.context())
        XCTAssertTrue(reply.contains("Aria"), reply)
    }
}

final class ReasoningStripTests: XCTestCase {
    func testStripsThinkBlocks() {
        let raw = "<think>The child asked about the river. Mention the direction.</think>The river is to your right, friend!"
        XCTAssertEqual(OpenAICompatibleBrain.stripReasoning(raw),
                       "The river is to your right, friend!")
    }

    func testStripsUnterminatedThinkBlock() {
        XCTAssertEqual(OpenAICompatibleBrain.stripReasoning("<think>still going..."), "")
    }

    func testPlainContentUntouched() {
        XCTAssertEqual(OpenAICompatibleBrain.stripReasoning("  Hello there!  "), "Hello there!")
    }
}

final class PromptBuilderTests: XCTestCase {
    func testPromptIsGroundedInSnapshot() {
        let prompt = PromptBuilder.systemPrompt(for: Fixtures.context(memories: ["She named the acorn Goldie."]))

        XCTAssertTrue(prompt.contains("You are Ember, a fox companion"))
        XCTAssertTrue(prompt.contains("Fox Nose"))
        XCTAssertTrue(prompt.contains("The child's name is Aria"))
        XCTAssertTrue(prompt.contains("mention ONLY these"))
        XCTAssertTrue(prompt.contains("- river: to your right"))
        XCTAssertTrue(prompt.contains("(QUEST TARGET)"))
        XCTAssertTrue(prompt.contains("NOT REACHABLE YET: The bridge to the castle is still broken."))
        XCTAssertTrue(prompt.contains("never invent places, directions, or distances"))
        XCTAssertTrue(prompt.contains("She named the acorn Goldie."))
    }

    func testPromptStaysCompact() {
        let prompt = PromptBuilder.systemPrompt(for: Fixtures.context())
        // Rough token budget for small local models: ~4 chars per token.
        XCTAssertLessThan(prompt.count, 2800, "system prompt should stay under ~700 tokens")
    }
}
