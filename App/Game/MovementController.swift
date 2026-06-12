import CoreGraphics
import Foundation
import StoryEngine

/// Continuous-movement state machine. Emits events; never plays sounds
/// itself — the view model maps events to earcons and haptics, keeping the
/// rules deterministic and the feedback in one place.
@MainActor
final class MovementController {
    enum Mode: Equatable {
        case idle
        case joystick
        case autopilot(targetEntityID: String)
    }

    enum MovementEvent {
        /// Every 1.5 u traveled → footstep + haptic.
        case step
        /// Heading crossed a 45° sector boundary. Steering is smooth, but
        /// the tick preserves her existing 8-direction mental model.
        case turnSnap
        /// Clamped against the ±40 world edge while pushing (2 s cooldown).
        case boundaryBump
        case autopilotArrived
    }

    private(set) var mode: Mode = .idle

    var isAutopilotActive: Bool {
        if case .autopilot = mode { return true }
        return false
    }

    // Tuning: quadratic stick response keeps slow exploration precise while
    // a full push still crosses the meadow quickly; the stride matches the
    // old tap-to-walk step so footstep cadence keeps its meaning.
    private let deadzone = 0.15
    private let maxWalkSpeed = 3.0
    private let maxTurnRate = 120.0
    private let autopilotTurnRate = 180.0
    private let autopilotSpeed = 2.2
    private let stepStride = 1.5
    private let arrivalDistance = 2.5
    private let alignToleranceDegrees = 10.0
    private let worldLimit = 40.0
    private let boundaryCooldown: TimeInterval = 2.0

    private var stick: CGVector?
    private var autopilotTarget: Vec3?
    private var strideProgress = 0.0
    private var lastBoundaryBump = Date.distantPast

    /// `nil` = released → idle. A live vector takes over from autopilot
    /// unconditionally — her touch always wins.
    func setJoystick(vector: CGVector?) {
        if let vector {
            if mode != .joystick {
                mode = .joystick
                autopilotTarget = nil
                strideProgress = 0
            }
            stick = vector
        } else {
            stick = nil
            if mode == .joystick { mode = .idle }
        }
    }

    func startAutopilot(toward targetID: String, position: Vec3) {
        mode = .autopilot(targetEntityID: targetID)
        autopilotTarget = position
        stick = nil
        strideProgress = 0
    }

    func cancelAutopilot() {
        guard isAutopilotActive else { return }
        mode = .idle
        autopilotTarget = nil
    }

    func integrate(pose: PlayerPose, deltaTime: TimeInterval)
        -> (pose: PlayerPose, events: [MovementEvent]) {
        switch mode {
        case .idle:
            return (pose, [])
        case .joystick:
            return integrateJoystick(pose: pose, dt: deltaTime)
        case .autopilot:
            return integrateAutopilot(pose: pose, dt: deltaTime)
        }
    }

    // MARK: - Joystick

    private func integrateJoystick(pose: PlayerPose, dt: TimeInterval)
        -> (PlayerPose, [MovementEvent]) {
        guard let stick else { return (pose, []) }
        let rawMagnitude = min(1.0, Double(hypot(stick.dx, stick.dy)))
        guard rawMagnitude >= deadzone else { return (pose, []) }

        // Rescale past the deadzone so its edge means "barely moving".
        let scale = (rawMagnitude - deadzone) / (1 - deadzone) / rawMagnitude
        let x = Double(stick.dx) * scale
        let y = Double(stick.dy) * scale

        var next = pose
        var events: [MovementEvent] = []

        // Quadratic response near center for fine control.
        let previousSector = Self.sector(of: pose.headingDegrees)
        next.headingDegrees = Self.normalized(pose.headingDegrees + x * abs(x) * maxTurnRate * dt)
        if Self.sector(of: next.headingDegrees) != previousSector {
            events.append(.turnSnap)
        }

        var speed = -y * abs(y) * maxWalkSpeed   // screen up = walk forward
        if speed < 0 { speed *= 0.5 }            // backing up is deliberate and careful

        advance(&next, distance: speed * dt, events: &events, pushing: abs(speed) > 0.05)
        return (next, events)
    }

    // MARK: - Autopilot

    private func integrateAutopilot(pose: PlayerPose, dt: TimeInterval)
        -> (PlayerPose, [MovementEvent]) {
        guard let target = autopilotTarget else {
            mode = .idle
            return (pose, [])
        }
        if pose.position.distance(to: target) <= arrivalDistance {
            mode = .idle
            autopilotTarget = nil
            return (pose, [.autopilotArrived])
        }

        var next = pose
        var events: [MovementEvent] = []

        let bearing = Self.bearingDegrees(from: pose.position, to: target)
        let relative = Self.relativeDegrees(bearing - pose.headingDegrees)
        let maxStep = autopilotTurnRate * dt
        let previousSector = Self.sector(of: pose.headingDegrees)
        next.headingDegrees = Self.normalized(
            pose.headingDegrees + max(-maxStep, min(maxStep, relative)))
        if Self.sector(of: next.headingDegrees) != previousSector {
            events.append(.turnSnap)
        }

        // Face the destination first — turning while walking is
        // disorienting when sound is the map.
        guard abs(relative) <= alignToleranceDegrees else { return (next, events) }

        let distance = min(autopilotSpeed * dt, pose.position.distance(to: target))
        advance(&next, distance: distance, events: &events, pushing: true)
        return (next, events)
    }

    // MARK: - Shared stepping

    private func advance(_ pose: inout PlayerPose, distance: Double,
                         events: inout [MovementEvent], pushing: Bool) {
        let radians = pose.headingDegrees * .pi / 180
        var position = pose.position
        position.x += distance * sin(radians)
        position.z -= distance * cos(radians)

        let clampedX = min(max(position.x, -worldLimit), worldLimit)
        let clampedZ = min(max(position.z, -worldLimit), worldLimit)
        if pushing, clampedX != position.x || clampedZ != position.z,
           Date().timeIntervalSince(lastBoundaryBump) > boundaryCooldown {
            lastBoundaryBump = Date()
            events.append(.boundaryBump)
        }
        position.x = clampedX
        position.z = clampedZ

        strideProgress += pose.position.distance(to: position)
        pose.position = position
        while strideProgress >= stepStride {
            strideProgress -= stepStride
            events.append(.step)
        }
    }

    // MARK: - Angle helpers

    /// Heading mapped into [0, 360).
    private static func normalized(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Difference mapped into (-180, 180].
    private static func relativeDegrees(_ degrees: Double) -> Double {
        var wrapped = degrees.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 { wrapped -= 360 }
        if wrapped <= -180 { wrapped += 360 }
        return wrapped
    }

    private static func sector(of headingDegrees: Double) -> Int {
        Int(normalized(headingDegrees) / 45) % 8
    }

    /// World bearing toward a point, same convention as PlayerPose
    /// (0 = -Z, positive turns right).
    private static func bearingDegrees(from position: Vec3, to target: Vec3) -> Double {
        atan2(target.x - position.x, -(target.z - position.z)) * 180 / .pi
    }
}
