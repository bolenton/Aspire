import XCTest
@testable import StoryEngine

final class GuidanceMathTests: XCTestCase {

    // MARK: - relativeBearing

    func testDeadAheadIsZero() {
        let pose = PlayerPose() // origin, facing -Z
        XCTAssertEqual(GuidanceMath.relativeBearing(from: pose, to: Vec3(x: 0, y: 0, z: -10)),
                       0, accuracy: 1e-9)
    }

    func testRightIsPositiveLeftIsNegative() {
        let pose = PlayerPose()
        XCTAssertEqual(GuidanceMath.relativeBearing(from: pose, to: Vec3(x: 10, y: 0, z: 0)),
                       90, accuracy: 1e-9)
        XCTAssertEqual(GuidanceMath.relativeBearing(from: pose, to: Vec3(x: -10, y: 0, z: 0)),
                       -90, accuracy: 1e-9)
    }

    func testElevationIgnored() {
        // Only the ground plane matters for a heading; y must not change it.
        let pose = PlayerPose()
        XCTAssertEqual(GuidanceMath.relativeBearing(from: pose, to: Vec3(x: 10, y: 50, z: 0)),
                       90, accuracy: 1e-9)
    }

    func testCoincidentTargetIsZero() {
        let pose = PlayerPose(position: Vec3(x: 5, y: 0, z: 5), headingDegrees: 37)
        XCTAssertEqual(GuidanceMath.relativeBearing(from: pose, to: Vec3(x: 5, y: 1, z: 5)),
                       0, accuracy: 1e-9)
    }

    func testWraparoundStaysInRange() {
        // Facing nearly south while the target sits behind-left: the raw
        // difference exceeds 180 and must wrap into (-180…180].
        let pose = PlayerPose(position: Vec3(x: 0, y: 0, z: 0), headingDegrees: 170)
        let target = Vec3(x: -10, y: 0, z: -10) // world bearing -45
        let bearing = GuidanceMath.relativeBearing(from: pose, to: target)
        XCTAssertGreaterThan(bearing, -180)
        XCTAssertLessThanOrEqual(bearing, 180)
        // -45 - 170 = -215 → wraps to +145.
        XCTAssertEqual(bearing, 145, accuracy: 1e-9)
    }

    func testBehindWrapsToPositive180() {
        // Directly behind: -180 must normalize to +180, never escape range.
        let pose = PlayerPose()
        let bearing = GuidanceMath.relativeBearing(from: pose, to: Vec3(x: 0, y: 0, z: 10))
        XCTAssertEqual(abs(bearing), 180, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(bearing, 180)
        XCTAssertGreaterThan(bearing, -180)
    }

    func testAgreesWithSnapshotBuilderDirection() {
        // The compass and the spoken sectors must read the same geometry.
        let poses = [PlayerPose(),
                     PlayerPose(position: Vec3(x: 3, y: 0, z: -2), headingDegrees: 90),
                     PlayerPose(position: Vec3(x: -7, y: 0, z: 4), headingDegrees: 215)]
        let targets = [Vec3(x: 10, y: 0, z: -10), Vec3(x: -5, y: 0, z: 8),
                       Vec3(x: 0, y: 0, z: 12), Vec3(x: 6, y: 0, z: 6)]
        for pose in poses {
            for target in targets {
                let bearing = GuidanceMath.relativeBearing(from: pose, to: target)
                XCTAssertEqual(CompassDirection8.from(relativeBearing: bearing),
                               SnapshotBuilder.direction(from: pose, to: target),
                               "pose \(pose) target \(target)")
            }
        }
    }

    // MARK: - isFacing

    func testIsFacingWithinDefaultTolerance() {
        XCTAssertTrue(GuidanceMath.isFacing(0))
        XCTAssertTrue(GuidanceMath.isFacing(14.9))
        XCTAssertTrue(GuidanceMath.isFacing(-14.9))
    }

    func testToleranceEdgesAreInclusive() {
        XCTAssertTrue(GuidanceMath.isFacing(15))
        XCTAssertTrue(GuidanceMath.isFacing(-15))
        XCTAssertFalse(GuidanceMath.isFacing(15.1))
        XCTAssertFalse(GuidanceMath.isFacing(-15.1))
    }

    func testIsFacingCustomTolerance() {
        XCTAssertTrue(GuidanceMath.isFacing(20, tolerance: 25))
        XCTAssertFalse(GuidanceMath.isFacing(20, tolerance: 15))
    }

    func testIsFacingNormalizesInput() {
        // A bearing handed in unwrapped (e.g. 359°) is really -1° — facing.
        XCTAssertTrue(GuidanceMath.isFacing(359))
        XCTAssertFalse(GuidanceMath.isFacing(180))
    }

    // MARK: - tickInterval

    func testTickIntervalBounds() {
        XCTAssertEqual(GuidanceMath.tickInterval(distance: 24), 1.6, accuracy: 1e-9)
        XCTAssertEqual(GuidanceMath.tickInterval(distance: 3), 0.35, accuracy: 1e-9)
    }

    func testTickIntervalClampsBeyondBounds() {
        XCTAssertEqual(GuidanceMath.tickInterval(distance: 100), 1.6, accuracy: 1e-9)
        XCTAssertEqual(GuidanceMath.tickInterval(distance: 0), 0.35, accuracy: 1e-9)
        XCTAssertEqual(GuidanceMath.tickInterval(distance: -5), 0.35, accuracy: 1e-9)
    }

    func testTickIntervalMonotonicallyIncreasesWithDistance() {
        var previous = GuidanceMath.tickInterval(distance: 0)
        for d in stride(from: 0.5, through: 30, by: 0.5) {
            let interval = GuidanceMath.tickInterval(distance: d)
            XCTAssertGreaterThanOrEqual(interval, previous, "distance \(d)")
            previous = interval
        }
    }

    func testTickIntervalMidpoint() {
        // Halfway between near (3) and far (24) is 13.5 u → halfway interval.
        let interval = GuidanceMath.tickInterval(distance: 13.5)
        XCTAssertEqual(interval, (0.35 + 1.6) / 2, accuracy: 1e-9)
    }

    func testTickIntervalAlwaysWithinAuthoredRange() {
        for d in stride(from: -10.0, through: 60, by: 0.25) {
            let interval = GuidanceMath.tickInterval(distance: d)
            XCTAssertGreaterThanOrEqual(interval, 0.35)
            XCTAssertLessThanOrEqual(interval, 1.6)
        }
    }
}
