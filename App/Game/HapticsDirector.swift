import CoreHaptics
import UIKit

/// Thin haptics facade. No-ops where unsupported (all iPads have no Taptic
/// Engine), which is why every haptic in the game pairs with an earcon
/// that carries the meaning on its own.
@MainActor
final class HapticsDirector {
    static let shared = HapticsDirector()

    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notice = UINotificationFeedbackGenerator()

    private init() {}

    /// One footstep.
    func stepTick() {
        guard supported else { return }
        light.impactOccurred()
        light.prepare()
    }

    /// Heading crossed a 45° sector boundary.
    func turnSnap() {
        guard supported else { return }
        rigid.impactOccurred()
        rigid.prepare()
    }

    /// Pushed against the world edge.
    func boundaryBump() {
        guard supported else { return }
        heavy.impactOccurred()
    }

    /// Walked into range of something she can interact with.
    func interactionRange() {
        guard supported else { return }
        notice.notificationOccurred(.success)
    }

    /// The touch stick engaged under her thumb.
    func engage() {
        guard supported else { return }
        soft.impactOccurred()
    }

    /// Keeps the movement generators prepared while she's actively moving —
    /// an unprepared generator adds latency to the first tap.
    func setActive(_ active: Bool) {
        guard supported, active else { return }
        light.prepare()
        rigid.prepare()
    }
}
