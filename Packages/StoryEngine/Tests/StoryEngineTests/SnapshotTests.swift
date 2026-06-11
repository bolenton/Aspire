import XCTest
@testable import StoryEngine

final class BearingTests: XCTestCase {
    func testEightSectorsFacingNorth() {
        let pose = PlayerPose() // origin, facing -Z
        let cases: [(Vec3, CompassDirection8)] = [
            (Vec3(x: 0, y: 0, z: -10), .ahead),
            (Vec3(x: 10, y: 0, z: -10), .aheadRight),
            (Vec3(x: 10, y: 0, z: 0), .right),
            (Vec3(x: 10, y: 0, z: 10), .behindRight),
            (Vec3(x: 0, y: 0, z: 10), .behind),
            (Vec3(x: -10, y: 0, z: 10), .behindLeft),
            (Vec3(x: -10, y: 0, z: 0), .left),
            (Vec3(x: -10, y: 0, z: -10), .aheadLeft),
        ]
        for (target, expected) in cases {
            XCTAssertEqual(SnapshotBuilder.direction(from: pose, to: target), expected,
                           "target \(target)")
        }
    }

    func testHeadingRotatesDirections() {
        // Facing east (+X): the river due east is now dead ahead.
        let pose = PlayerPose(position: Vec3(x: 0, y: 0, z: 0), headingDegrees: 90)
        XCTAssertEqual(SnapshotBuilder.direction(from: pose, to: Vec3(x: 10, y: 0, z: 0)), .ahead)
        XCTAssertEqual(SnapshotBuilder.direction(from: pose, to: Vec3(x: 0, y: 0, z: -10)), .left)
    }

    func testElevationBands() {
        let origin = Vec3(x: 0, y: 0, z: 0)
        XCTAssertEqual(SnapshotBuilder.elevation(from: origin, to: Vec3(x: 0, y: 4, z: 0)), .above)
        XCTAssertEqual(SnapshotBuilder.elevation(from: origin, to: Vec3(x: 0, y: -3, z: 0)), .below)
        XCTAssertEqual(SnapshotBuilder.elevation(from: origin, to: Vec3(x: 0, y: 1, z: 0)), .level)
    }

    func testDistanceBuckets() {
        XCTAssertEqual(SnapshotPhrasing.spokenDistance(0.5), "right here")
        XCTAssertEqual(SnapshotPhrasing.spokenDistance(2), "a few steps away")
        XCTAssertEqual(SnapshotPhrasing.spokenDistance(5), "a short walk away")
        XCTAssertEqual(SnapshotPhrasing.spokenDistance(12), "about 12 big steps away")
        XCTAssertEqual(SnapshotPhrasing.spokenDistance(40), "far away")
    }
}

final class SnapshotBuilderTests: XCTestCase {
    func testRiverIsToTheRightWithSound() {
        let snapshot = Fixtures.snapshot()
        let river = snapshot.perceived.first { $0.entityID == "river" }
        XCTAssertEqual(river?.direction, .right)
        XCTAssertEqual(river?.spokenDistance, "about 12 big steps away")
        XCTAssertEqual(river?.isAudible, true)
        XCTAssertEqual(river?.soundDescription, "flowing water")
    }

    func testCompanionPlaceholderGetsRealName() {
        let snapshot = Fixtures.snapshot(companion: Fixtures.clover)
        let companion = snapshot.perceived.first { $0.entityID == StoryConventions.companionPlaceholder }
        XCTAssertEqual(companion?.name, "Clover")
    }

    func testCloverHearsFartherThanEmber() {
        // 33m from the river: beyond its 30m radius (and the 20m landmark
        // radius), but within Clover's boosted hearing.
        let farPose = PlayerPose(position: Vec3(x: 45, y: 0, z: 0))
        let forEmber = Fixtures.snapshot(companion: Fixtures.ember, pose: farPose)
        XCTAssertNil(forEmber.perceived.first { $0.entityID == "river" })

        let forClover = Fixtures.snapshot(companion: Fixtures.clover, pose: farPose)
        let river = forClover.perceived.first { $0.entityID == "river" }
        XCTAssertEqual(river?.isAudible, true)
    }

    func testQuestTargetAlwaysPerceivedAndFirst() {
        let farPose = PlayerPose(position: Vec3(x: 200, y: 0, z: 0))
        let snapshot = Fixtures.snapshot(pose: farPose)
        XCTAssertEqual(snapshot.perceived.first?.entityID, "old_oak")
        XCTAssertEqual(snapshot.perceived.first?.isQuestTarget, true)
    }

    func testTeaseIsAnonymized() {
        let snapshot = Fixtures.snapshot(companion: Fixtures.petal)
        let tease = snapshot.perceived.first { $0.entityID == "buried_treat" }
        XCTAssertEqual(tease?.name, "something hidden")
        XCTAssertEqual(tease?.isAnonymousTease, true)
        XCTAssertNil(tease?.soundDescription)
        XCTAssertEqual(tease?.teaseLine, "Something is hiding near the big root, but I can't tell what.")
    }

    func testAbilityFindingsCollected() {
        let snapshot = Fixtures.snapshot(companion: Fixtures.ember)
        XCTAssertEqual(snapshot.abilityFindings,
                       ["My nose found something buried near the big root!"])
    }

    func testLockedGateCarriesExplanation() {
        let snapshot = Fixtures.snapshot()
        let gate = snapshot.perceived.first { $0.entityID == "castle_gate" }
        XCTAssertEqual(gate?.isLocked, true)
        XCTAssertEqual(gate?.lockedExplanation, "The bridge to the castle is still broken.")
    }

    func testQuestSnapshotUsesHintTierAndDirection() {
        let eager = SupportLevel(audioCueGain: 1.6, glowBoost: 1.6, hintTier: 2, challenge: 1)
        let snapshot = Fixtures.snapshot(support: eager)
        XCTAssertEqual(snapshot.activeQuest?.currentHint,
                       "Walk straight toward the creaking sound ahead. That's the old oak.")
        XCTAssertEqual(snapshot.activeQuest?.targetName, "old oak")
        XCTAssertEqual(snapshot.activeQuest?.targetDirection, .ahead)
    }

    func testAmbientAndEventsFlowThrough() {
        var events = EventLog()
        events.record(GameEvent(tick: 1, kind: .sceneEntered, spoken: "You stepped into Fox Hollow."))
        events.record(GameEvent(tick: 2, kind: .stepCompleted, spoken: "You found the old oak!"))
        let snapshot = Fixtures.snapshot(events: events)
        XCTAssertEqual(snapshot.ambientSounds, ["wind in the leaves", "crickets singing"])
        XCTAssertEqual(snapshot.recentEvents.first, "You found the old oak!")
    }

    func testSceneDescriptionIsCompanionFlavored() {
        XCTAssertEqual(Fixtures.snapshot(companion: Fixtures.clover).sceneDescription,
                       "A mossy clearing. So many gentle sounds to hear here.")
        XCTAssertEqual(Fixtures.snapshot(companion: Fixtures.ember).sceneDescription,
                       "A mossy clearing wrapped in tall whispering trees.")
    }
}

final class SituationReportTests: XCTestCase {
    func testReadoutMentionsSceneTargetAndLockedReason() {
        let report = SituationReport.spoken(from: Fixtures.snapshot(),
                                            companion: Fixtures.ember, childName: "Aria")
        XCTAssertTrue(report.hasPrefix("You are in Fox Hollow."))
        XCTAssertTrue(report.contains("old oak"))
        XCTAssertTrue(report.contains("we're looking for the old oak"))
        XCTAssertTrue(report.contains("My nose found something buried near the big root!"))
    }

    func testReadoutIsDeterministic() {
        let a = SituationReport.spoken(from: Fixtures.snapshot(), companion: Fixtures.ember, childName: "Aria")
        let b = SituationReport.spoken(from: Fixtures.snapshot(), companion: Fixtures.ember, childName: "Aria")
        XCTAssertEqual(a, b)
    }

    func testTeaseSentence() {
        let entity = PerceivedEntity(entityID: "x", name: "something hidden", kind: .item,
                                     direction: .behind, elevation: .above,
                                     distanceMeters: 6, spokenDistance: "a short walk away",
                                     isAudible: false, isAnonymousTease: true,
                                     teaseLine: "Something rustles up there.")
        XCTAssertEqual(SituationReport.sentence(for: entity, companion: Fixtures.petal),
                       "Something rustles up there. It's behind you, a short walk away.")
    }

    func testLockedSentence() {
        let entity = PerceivedEntity(entityID: "castle_gate", name: "castle gate", kind: .portal,
                                     direction: .left, elevation: .level,
                                     distanceMeters: 16, spokenDistance: "about 16 big steps away",
                                     isAudible: false, isLocked: true,
                                     lockedExplanation: "The bridge to the castle is still broken.")
        XCTAssertEqual(SituationReport.sentence(for: entity, companion: Fixtures.ember),
                       "The castle gate is to your left, about 16 big steps away. The bridge to the castle is still broken.")
    }
}
