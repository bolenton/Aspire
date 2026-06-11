import SwiftUI
import StoryEngine

/// All colors derive from the calibrated contrast theme — different eye
/// conditions need different polarities, so nothing is hardcoded in views.
struct Theme {
    let background: Color
    let text: Color
    let accent: Color
    let highlight: Color
    let textScale: Double

    init(profile: CalibrationProfile) {
        textScale = profile.textScale
        switch profile.contrastTheme {
        case .lightOnDark:
            background = Color(red: 0.04, green: 0.04, blue: 0.10)
            text = Color(red: 1.0, green: 0.96, blue: 0.86)
            accent = Color(red: 1.0, green: 0.82, blue: 0.29)
            highlight = Color(red: 0.35, green: 0.78, blue: 0.94)
        case .darkOnLight:
            background = Color(red: 0.99, green: 0.97, blue: 0.92)
            text = Color(red: 0.07, green: 0.07, blue: 0.12)
            accent = Color(red: 0.55, green: 0.27, blue: 0.0)
            highlight = Color(red: 0.0, green: 0.35, blue: 0.60)
        case .highContrastYellow:
            background = .black
            text = .yellow
            accent = .yellow
            highlight = .white
        }
    }

    func fontSize(_ base: CGFloat) -> CGFloat {
        base * textScale
    }
}

/// Giant, glowing, high-contrast button — the only button style in the game.
struct GiantButtonStyle: ButtonStyle {
    let theme: Theme
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: theme.fontSize(28), weight: .bold, design: .rounded))
            .foregroundColor(filled ? theme.background : theme.accent)
            .padding(.vertical, 22)
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(filled ? theme.accent : theme.background)
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.accent, lineWidth: 4))
            )
            .shadow(color: theme.accent.opacity(0.6), radius: configuration.isPressed ? 4 : 14)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
    }
}
