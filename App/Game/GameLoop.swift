import QuartzCore

/// CADisplayLink wrapper driving the per-frame game simulation. The tick
/// lives here — owned by the view model — rather than in the render
/// callback, because SwiftUI can tear the world view down at any moment
/// and gameplay must keep its MainActor guarantees.
@MainActor
final class GameLoop {
    /// Called once per display frame with the seconds since the last tick.
    var onTick: ((TimeInterval) -> Void)?
    private(set) var isRunning = false

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastTimestamp = nil
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
    }

    @objc private func step(_ link: CADisplayLink) {
        let dt: TimeInterval
        if let lastTimestamp {
            dt = link.timestamp - lastTimestamp
        } else {
            dt = link.duration
        }
        lastTimestamp = link.timestamp
        // Clamp huge gaps (app suspension, debugger pauses) so a single
        // tick can never teleport her across the world.
        onTick?(max(0, min(dt, 0.1)))
    }
}
