import SwiftUI
import StoryEngine

/// Kids-category parent gate: hold three seconds, then answer a math
/// question — then the settings open.
struct ParentGateView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var heldLongEnough = false
    @State private var solved = false
    @State private var lhs = Int.random(in: 6...9)
    @State private var rhs = Int.random(in: 3...7)

    var body: some View {
        let theme = appModel.theme
        ZStack {
            theme.background.ignoresSafeArea()
            if solved {
                SettingsView()
                    .environmentObject(appModel)
            } else if heldLongEnough {
                mathQuestion(theme)
            } else {
                holdStep(theme)
            }
        }
    }

    private func holdStep(_ theme: Theme) -> some View {
        VStack(spacing: 30) {
            Text("Grown-ups only")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(theme.accent)
            Text("Press and hold the button for three seconds.")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(theme.text)
            Text("Hold me")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(theme.background)
                .padding(.vertical, 26)
                .padding(.horizontal, 60)
                .background(RoundedRectangle(cornerRadius: 24).fill(theme.accent))
                .onLongPressGesture(minimumDuration: 3) {
                    heldLongEnough = true
                }
        }
        .padding(40)
    }

    private func mathQuestion(_ theme: Theme) -> some View {
        let answer = lhs * rhs
        let options = [answer - lhs, answer, answer + rhs].sorted()
        return VStack(spacing: 30) {
            Text("What is \(lhs) × \(rhs)?")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(theme.accent)
            HStack(spacing: 20) {
                ForEach(options, id: \.self) { option in
                    Button("\(option)") {
                        if option == answer {
                            solved = true
                        } else {
                            heldLongEnough = false
                            lhs = Int.random(in: 6...9)
                            rhs = Int.random(in: 3...7)
                        }
                    }
                    .buttonStyle(GiantButtonStyle(theme: theme, filled: false))
                }
            }
        }
        .padding(40)
    }
}

struct SettingsView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("brain.endpoint") private var brainEndpoint = ""
    @AppStorage("brain.model") private var brainModel = ""
    @AppStorage("brain.apiKey") private var brainAPIKey = ""

    var body: some View {
        let theme = appModel.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Lantern Settings")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(theme.accent)

                section("Child", theme) {
                    TextField("Child's name", text: $appModel.vault.calibration.childName)
                        .textFieldStyle(.roundedBorder)

                    labeledSlider("Text size", value: $appModel.vault.calibration.textScale,
                                  range: 1.0...4.0, theme: theme)
                    labeledSlider("Narration speed", value: $appModel.vault.calibration.speechRate,
                                  range: 0.6...1.5, theme: theme)

                    Picker("Colors", selection: $appModel.vault.calibration.contrastTheme) {
                        Text("Glow on dark").tag(ContrastTheme.lightOnDark)
                        Text("Dark on light").tag(ContrastTheme.darkOnLight)
                        Text("Yellow on black").tag(ContrastTheme.highContrastYellow)
                    }
                    .pickerStyle(.segmented)

                    Picker("Help level", selection: $appModel.vault.calibration.hintAggressiveness) {
                        Text("Let her explore").tag(HintAggressiveness.gentle)
                        Text("Balanced").tag(HintAggressiveness.standard)
                        Text("Help early").tag(HintAggressiveness.eager)
                    }
                    .pickerStyle(.segmented)
                }

                section("Companion AI (optional)", theme) {
                    Text("Works fully offline without this. Point it at any OpenAI-compatible server — Ollama or LM Studio on your Mac, or a cloud gateway — and the companion gets smarter. If it's ever unreachable, the built-in companion takes over seamlessly.")
                        .font(.system(size: 14))
                        .foregroundColor(theme.text.opacity(0.7))
                    TextField("Endpoint, e.g. http://my-mac.local:11434/v1", text: $brainEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Model, e.g. gemma3:4b", text: $brainModel)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("API key (only for cloud gateways)", text: $brainAPIKey)
                        .textFieldStyle(.roundedBorder)
                }

                Button("Done") {
                    appModel.saveVault()
                    dismiss()
                }
                .buttonStyle(GiantButtonStyle(theme: theme))
            }
            .padding(36)
        }
        .background(theme.background.ignoresSafeArea())
        .foregroundColor(theme.text)
    }

    private func section(_ title: String, _ theme: Theme,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(theme.accent)
            content()
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 20).stroke(theme.accent.opacity(0.5), lineWidth: 2))
    }

    private func labeledSlider(_ label: String, value: Binding<Double>,
                               range: ClosedRange<Double>, theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label): \(value.wrappedValue, specifier: "%.1f")")
                .font(.system(size: 16, weight: .semibold))
            Slider(value: value, in: range)
                .tint(theme.accent)
        }
    }
}
