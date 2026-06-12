import Foundation

/// How she moves through the world: the touch-anywhere joystick (default)
/// or the classic tap buttons, tucked bottom-left so the world stays clear.
/// VoiceOver always gets the buttons — they are the accessible movement
/// path regardless of this choice.
enum ControlScheme: String, CaseIterable {
    case joystick
    case buttons

    static let storageKey = "controls.scheme"
}
