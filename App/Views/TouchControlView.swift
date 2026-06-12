import SwiftUI
import UIKit

/// Transparent full-world-area touch layer: hold a thumb anywhere and that
/// point becomes a virtual joystick (push up = walk, slide sideways =
/// steer, release = stop); double-tap = autopilot toward the quest target.
/// Raw `touches*` overrides on purpose — gesture recognizers would delay
/// or fight the window-level two-finger freeze gesture, which must keep
/// working while the stick is held.
struct TouchControlView: UIViewRepresentable {
    /// False while overlays are open or VoiceOver runs — the three big
    /// buttons remain the VoiceOver movement path.
    var enabled: Bool
    /// Normalized stick vector (unit-clamped); nil on release.
    var onStickChanged: (CGVector?) -> Void
    /// Screen-space ring center + thumb position for the visual; nil on release.
    var onStickVisualChanged: ((center: CGPoint, thumb: CGPoint)?) -> Void
    var onDoubleTap: () -> Void
    /// Any touch landing: cancels autopilot, resets the idle timer.
    var onAnyTouch: () -> Void

    func makeUIView(context: Context) -> TouchLayerView {
        let view = TouchLayerView()
        view.backgroundColor = .clear
        configure(view)
        return view
    }

    func updateUIView(_ view: TouchLayerView, context: Context) {
        configure(view)
    }

    private func configure(_ view: TouchLayerView) {
        view.onStickChanged = onStickChanged
        view.onStickVisualChanged = onStickVisualChanged
        view.onDoubleTap = onDoubleTap
        view.onAnyTouch = onAnyTouch
        view.setEnabled(enabled)
    }
}

/// The UIView doing the actual single-touch tracking.
final class TouchLayerView: UIView {
    var onStickChanged: (CGVector?) -> Void = { _ in }
    var onStickVisualChanged: ((center: CGPoint, thumb: CGPoint)?) -> Void = { _ in }
    var onDoubleTap: () -> Void = {}
    var onAnyTouch: () -> Void = {}

    private let stickRadius: CGFloat = 110
    private let tapMaxDuration: TimeInterval = 0.25
    private let tapMaxMovement: CGFloat = 12
    private let doubleTapWindow: TimeInterval = 0.35
    private let doubleTapMaxDistance: CGFloat = 60

    private var trackedTouch: UITouch?
    /// True after a second finger landed (freeze gesture incoming): ignore
    /// everything until the whole hand lifts.
    private var ignoringUntilTouchesEnd = false
    private var liveTouchCount = 0
    private var stickCenter = CGPoint.zero
    private var lastPoint = CGPoint.zero
    private var touchBeganAt: TimeInterval = 0
    private var stickEngaged = false
    private var engageTimer: Timer?
    private var lastTapAt: TimeInterval = -.greatestFiniteMagnitude
    private var lastTapPoint = CGPoint.zero
    private var featureEnabled = true
    private var voiceOverObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Multi-touch must be on so the second finger is even delivered —
        // detecting it is how the stick yields to the freeze gesture.
        isMultipleTouchEnabled = true
        isAccessibilityElement = false
        voiceOverObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.applyEnabled()
        }
        applyEnabled()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let voiceOverObserver {
            NotificationCenter.default.removeObserver(voiceOverObserver)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard featureEnabled != enabled else { return }
        featureEnabled = enabled
        applyEnabled()
    }

    private func applyEnabled() {
        let active = featureEnabled && !UIAccessibility.isVoiceOverRunning
        isUserInteractionEnabled = active
        if !active {
            // Deferred: setEnabled arrives during SwiftUI's update pass, and
            // releasing the stick publishes model state.
            DispatchQueue.main.async { [weak self] in
                self?.standDown()
            }
        }
    }

    private func standDown() {
        engageTimer?.invalidate()
        engageTimer = nil
        trackedTouch = nil
        ignoringUntilTouchesEnd = false
        liveTouchCount = 0
        releaseStick()
    }

    private func releaseStick() {
        guard stickEngaged else { return }
        stickEngaged = false
        onStickChanged(nil)
        onStickVisualChanged(nil)
    }

    // MARK: - Touch tracking

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        liveTouchCount += touches.count
        onAnyTouch()
        guard !ignoringUntilTouchesEnd else { return }

        if trackedTouch != nil || touches.count > 1 {
            // Second finger: the freeze gesture is incoming. Let go
            // instantly and stand down until every finger lifts.
            engageTimer?.invalidate()
            engageTimer = nil
            trackedTouch = nil
            releaseStick()
            ignoringUntilTouchesEnd = true
            return
        }

        guard let touch = touches.first else { return }
        trackedTouch = touch
        stickCenter = touch.location(in: self)
        lastPoint = stickCenter
        touchBeganAt = touch.timestamp
        stickEngaged = false
        // Held past the tap threshold without moving = the stick engages
        // in place (zero vector — standing, ready to push).
        engageTimer = Timer.scheduledTimer(withTimeInterval: tapMaxDuration,
                                           repeats: false) { [weak self] _ in
            self?.engageStick()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        lastPoint = touch.location(in: self)
        if !stickEngaged,
           hypot(lastPoint.x - stickCenter.x, lastPoint.y - stickCenter.y) >= tapMaxMovement {
            engageStick()
        }
        if stickEngaged {
            sendStick(at: lastPoint)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        liveTouchCount = max(0, liveTouchCount - touches.count)
        defer {
            if liveTouchCount == 0 { ignoringUntilTouchesEnd = false }
        }
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        engageTimer?.invalidate()
        engageTimer = nil
        trackedTouch = nil

        if stickEngaged {
            releaseStick()
            return
        }

        let point = touch.location(in: self)
        let moved = hypot(point.x - stickCenter.x, point.y - stickCenter.y)
        guard touch.timestamp - touchBeganAt < tapMaxDuration,
              moved < tapMaxMovement else { return }

        if touchBeganAt - lastTapAt <= doubleTapWindow,
           hypot(point.x - lastTapPoint.x, point.y - lastTapPoint.y) <= doubleTapMaxDistance {
            lastTapAt = -.greatestFiniteMagnitude
            onDoubleTap()
        } else {
            lastTapAt = touch.timestamp
            lastTapPoint = point
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        liveTouchCount = max(0, liveTouchCount - touches.count)
        if liveTouchCount == 0 { ignoringUntilTouchesEnd = false }
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        engageTimer?.invalidate()
        engageTimer = nil
        trackedTouch = nil
        releaseStick()
    }

    // MARK: - Stick math

    private func engageStick() {
        guard trackedTouch != nil, !stickEngaged else { return }
        engageTimer?.invalidate()
        engageTimer = nil
        stickEngaged = true
        sendStick(at: lastPoint)
    }

    private func sendStick(at point: CGPoint) {
        var dx = (point.x - stickCenter.x) / stickRadius
        var dy = (point.y - stickCenter.y) / stickRadius
        let magnitude = hypot(dx, dy)
        if magnitude > 1 {
            dx /= magnitude
            dy /= magnitude
        }
        onStickChanged(CGVector(dx: dx, dy: dy))
        onStickVisualChanged((center: stickCenter,
                              thumb: CGPoint(x: stickCenter.x + dx * stickRadius,
                                             y: stickCenter.y + dy * stickRadius)))
    }
}
