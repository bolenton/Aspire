import SwiftUI
import StoryEngine

/// The choosing ceremony: each friend introduces itself out loud in its own
/// voice — she picks by ear as much as by eye.
struct CompanionPickerView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var selectedID: String?

    private var selected: Companion? {
        appModel.availableCompanions.first { $0.id == selectedID }
    }

    private func emoji(for companion: Companion) -> String {
        switch companion.species.lowercased() {
        case "fox": return "🦊"
        case "butterfly": return "🦋"
        case "bunny", "rabbit": return "🐰"
        default: return "✨"
        }
    }

    var body: some View {
        let theme = appModel.theme
        ZStack {
            theme.background.ignoresSafeArea()
            VStack(spacing: 26) {
                Text("Who will come with you?")
                    .font(.system(size: theme.fontSize(34), weight: .heavy, design: .rounded))
                    .foregroundColor(theme.accent)
                    .multilineTextAlignment(.center)

                HStack(spacing: 24) {
                    ForEach(appModel.availableCompanions) { companion in
                        Button {
                            selectedID = companion.id
                            appModel.narrator.speak(companion.introduction, voice: companion.voice)
                        } label: {
                            VStack(spacing: 14) {
                                Text(emoji(for: companion))
                                    .font(.system(size: theme.fontSize(64)))
                                Text(companion.name)
                                    .font(.system(size: theme.fontSize(28), weight: .bold, design: .rounded))
                                Text("the \(companion.species)")
                                    .font(.system(size: theme.fontSize(17), weight: .medium, design: .rounded))
                            }
                            .foregroundColor(selectedID == companion.id ? theme.background : theme.text)
                            .padding(28)
                            .frame(maxWidth: .infinity, minHeight: 230)
                            .background(
                                RoundedRectangle(cornerRadius: 28)
                                    .fill(selectedID == companion.id ? theme.accent : .clear)
                                    .overlay(RoundedRectangle(cornerRadius: 28)
                                        .stroke(theme.accent, lineWidth: 4))
                            )
                            .shadow(color: theme.accent.opacity(selectedID == companion.id ? 0.8 : 0.2),
                                    radius: 16)
                        }
                    }
                }

                if let selected {
                    Button("Choose \(selected.name)!") {
                        appModel.createSlot(companion: selected)
                    }
                    .buttonStyle(GiantButtonStyle(theme: theme))
                } else {
                    Text("Tap a friend to hear them say hello")
                        .font(.system(size: theme.fontSize(20), weight: .medium, design: .rounded))
                        .foregroundColor(theme.text.opacity(0.7))
                        .padding(.vertical, 24)
                }
            }
            .padding(40)
        }
        .onAppear {
            appModel.narrator.speak("Three friends are waiting to meet you, \(appModel.childName). Tap each one to hear them say hello, then choose who comes with you.")
        }
    }
}
