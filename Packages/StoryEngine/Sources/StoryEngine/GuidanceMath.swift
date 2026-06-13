import Foundation

/// The geometry behind the audio compass: where the quest target sits
/// relative to where she is looking, whether she is pointed at it, and how
/// urgently the guiding chime should tick as she closes in. Pure and
/// platform-independent so the rules stay testable on Linux — the same
/// bearing math `SnapshotBuilder` uses to phrase directions aloud.
public enum GuidanceMath {
    /// Relative bearing in degrees, normalized to (-180…180] with 0 = dead
    /// ahead and positive = clockwise (to her right). This is exactly the
    /// angle `SnapshotBuilder.direction` sorts into eight spoken sectors;
    /// the compass reads it continuously instead.
    public static func relativeBearing(from pose: PlayerPose, to target: Vec3) -> Double {
        let dx = target.x - pose.position.x
        let dz = target.z - pose.position.z
        guard dx != 0 || dz != 0 else { return 0 }
        let worldBearing = atan2(dx, -dz) * 180 / .pi
        return normalized(worldBearing - pose.headingDegrees)
    }

    /// True when she is pointed close enough at the target that the facing
    /// tick should sound. The tolerance is one half-sector by default so a
    /// glance toward the target rewards her without demanding a perfect aim.
    public static func isFacing(_ bearing: Double, tolerance: Double = 15) -> Bool {
        abs(normalized(bearing)) <= tolerance
    }

    /// How long to wait between facing ticks at a given distance: a slow
    /// 1.6 s pulse when the target is far (≥24 u) tightening to an eager
    /// 0.35 s as she arrives (≤3 u), interpolated linearly in between. The
    /// accelerating cadence is the "warmer / warmer" signal that she is
    /// closing in, with no clutter while she is still far away.
    public static func tickInterval(distance: Double) -> TimeInterval {
        let farDistance = 24.0, nearDistance = 3.0
        let farInterval = 1.6, nearInterval = 0.35
        if distance >= farDistance { return farInterval }
        if distance <= nearDistance { return nearInterval }
        let t = (distance - nearDistance) / (farDistance - nearDistance)
        return nearInterval + t * (farInterval - nearInterval)
    }

    /// Wrap any angle into (-180…180].
    private static func normalized(_ degrees: Double) -> Double {
        var wrapped = degrees.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 { wrapped -= 360 }
        if wrapped <= -180 { wrapped += 360 }
        return wrapped
    }
}
