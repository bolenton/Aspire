import StoryEngine
import SwiftUI
import UIKit

/// The companion's portrait: bundled art when present
/// (Assets/Art/<companionID>.png), emoji until then. Breathes while idle,
/// glows brighter and bounces word-by-word while speaking — so she can SEE
/// her friend talking as the words are read aloud.
struct CompanionAvatarView: View {
    let companion: Companion
    @ObservedObject var narrator: Narrator
    var size: CGFloat = 130
    let theme: Theme

    @State private var breathing = false
    @State private var wordPulse = false

    private var image: UIImage? {
        let url = Bundle.main.url(forResource: companion.id, withExtension: "png",
                                  subdirectory: "Assets/Art")
            ?? Bundle.main.url(forResource: companion.id, withExtension: "png")
        return url.flatMap { UIImage(contentsOfFile: $0.path) }
    }

    private var emoji: String {
        switch companion.species.lowercased() {
        case "fox": return "🦊"
        case "butterfly": return "🦋"
        case "bunny", "rabbit": return "🐰"
        default: return "✨"
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(emoji)
                    .font(.system(size: size * 0.62))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(breathing ? 1.03 : 0.98)
        .scaleEffect(wordPulse ? 1.07 : 1.0)
        .rotationEffect(.degrees(breathing ? 1.6 : -1.6), anchor: .bottom)
        .shadow(color: theme.accent.opacity(narrator.isSpeaking ? 0.85 : 0.35),
                radius: narrator.isSpeaking ? 24 : 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .onChange(of: narrator.highlightRange) { _, _ in
            guard narrator.isSpeaking else { return }
            withAnimation(.spring(response: 0.12, dampingFraction: 0.45)) {
                wordPulse = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) {
                    wordPulse = false
                }
            }
        }
        .accessibilityHidden(true)
    }
}
