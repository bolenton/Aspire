import CoreMotion
import Foundation

/// AirPods (Pro / Max / 3rd-gen) head tracking. Her head yaw becomes an
/// offset on top of the body heading from the turn buttons, so spatial
/// sounds stay anchored in the world when she turns her head — the world
/// stays out there. Does nothing gracefully without capable headphones.
final class HeadTracker {
    private let manager = CMHeadphoneMotionManager()
    private var baselineYaw: Double?
    private(set) var isTracking = false

    /// Reports head yaw in degrees, positive = turned right, relative to
    /// where her head pointed when tracking started.
    func start(onYaw: @escaping (Double) -> Void) {
        guard manager.isDeviceMotionAvailable, !isTracking else { return }
        isTracking = true
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let yawDegrees = -motion.attitude.yaw * 180 / .pi
            if self.baselineYaw == nil {
                self.baselineYaw = yawDegrees
            }
            onYaw(yawDegrees - (self.baselineYaw ?? yawDegrees))
        }
    }

    /// Re-zero "straight ahead" to wherever her head points right now.
    func recenter() {
        baselineYaw = nil
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        isTracking = false
        baselineYaw = nil
    }
}
