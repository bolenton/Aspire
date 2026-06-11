import SwiftUI
import StoryEngine

/// The spoken first-launch wizard: she picks what's comfortable by eye and
/// ear, a grown-up helps with the name. Everything re-tunable later behind
/// the parent gate.
struct CalibrationWizardView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var profile = CalibrationProfile()
    @State private var step = 0

    private let sampleSentence = "The fox follows the river."

    var body: some View {
        let theme = Theme(profile: profile)
        ZStack {
            theme.background.ignoresSafeArea()
            VStack(spacing: 28) {
                Text("Step \(step + 1) of 5")
                    .font(.system(size: theme.fontSize(16), weight: .medium))
                    .foregroundColor(theme.text.opacity(0.6))

                Group {
                    switch step {
                    case 0: nameStep(theme)
                    case 1: textSizeStep(theme)
                    case 2: speechRateStep(theme)
                    case 3: contrastStep(theme)
                    default: hintStep(theme)
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 20) {
                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .buttonStyle(GiantButtonStyle(theme: theme, filled: false))
                    }
                    Button(step == 4 ? "All done!" : "Next") {
                        if step == 4 {
                            finish()
                        } else {
                            step += 1
                            speakPrompt()
                        }
                    }
                    .buttonStyle(GiantButtonStyle(theme: theme))
                }
            }
            .padding(50)
        }
        .onAppear {
            profile = appModel.vault.calibration
            speakPrompt()
        }
    }

    private func finish() {
        appModel.vault.calibration = profile
        appModel.saveVault()
        appModel.route = .companionPicker
    }

    private func speakPrompt() {
        let prompts = [
            "Hello! Let's make the game feel just right. First, ask a grown-up to type your name.",
            "Tap the words that are easiest for you to read.",
            "How fast should I talk? Tap each one to hear it, then pick your favorite.",
            "Which colors feel best for your eyes? Tap each one to try it.",
            "Last one — this is for the grown-up. How quickly should the game offer help?",
        ]
        appModel.narrator.profile = profile
        appModel.narrator.speak(prompts[step])
    }

    private func nameStep(_ theme: Theme) -> some View {
        VStack(spacing: 24) {
            Text("What's your name?")
                .font(.system(size: theme.fontSize(34), weight: .bold, design: .rounded))
                .foregroundColor(theme.text)
            TextField("Your name", text: $profile.childName)
                .font(.system(size: theme.fontSize(34), weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 20).stroke(theme.accent, lineWidth: 3))
                .foregroundColor(theme.text)
        }
    }

    private func textSizeStep(_ theme: Theme) -> some View {
        VStack(spacing: 24) {
            ForEach([1.4, 2.2, 3.2], id: \.self) { scale in
                Button {
                    profile.textScale = scale
                } label: {
                    Text(sampleSentence)
                        .font(.system(size: 16 * scale, weight: .bold, design: .rounded))
                        .foregroundColor(profile.textScale == scale ? theme.background : theme.text)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(profile.textScale == scale ? theme.accent : .clear)
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.accent, lineWidth: 3))
                        )
                }
            }
        }
    }

    private func speechRateStep(_ theme: Theme) -> some View {
        let options: [(label: String, rate: Double)] = [
            ("Slow and cozy", 0.8), ("Just right", 1.0), ("Quick!", 1.25),
        ]
        return VStack(spacing: 24) {
            ForEach(0..<3, id: \.self) { index in
                let option = options[index]
                Button(option.label) {
                    profile.speechRate = option.rate
                    appModel.narrator.profile = profile
                    appModel.narrator.speak(sampleSentence)
                }
                .buttonStyle(GiantButtonStyle(theme: theme, filled: profile.speechRate == option.rate))
            }
        }
    }

    private func contrastStep(_ theme: Theme) -> some View {
        VStack(spacing: 24) {
            ForEach(ContrastTheme.allCases, id: \.self) { contrast in
                let preview = Theme(profile: {
                    var p = profile; p.contrastTheme = contrast; return p
                }())
                Button {
                    profile.contrastTheme = contrast
                } label: {
                    Text(sampleSentence)
                        .font(.system(size: theme.fontSize(22), weight: .bold, design: .rounded))
                        .foregroundColor(preview.text)
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(preview.background)
                                .overlay(RoundedRectangle(cornerRadius: 20)
                                    .stroke(profile.contrastTheme == contrast ? theme.accent : theme.text.opacity(0.3),
                                            lineWidth: profile.contrastTheme == contrast ? 5 : 2))
                        )
                }
            }
        }
    }

    private func hintStep(_ theme: Theme) -> some View {
        let options: [(label: String, level: HintAggressiveness)] = [
            ("Let her explore", .gentle), ("Balanced", .standard), ("Help early and often", .eager),
        ]
        return VStack(spacing: 24) {
            ForEach(0..<3, id: \.self) { index in
                let option = options[index]
                Button(option.label) {
                    profile.hintAggressiveness = option.level
                }
                .buttonStyle(GiantButtonStyle(theme: theme, filled: profile.hintAggressiveness == option.level))
            }
        }
    }
}
