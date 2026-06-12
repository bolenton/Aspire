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
    @AppStorage("brain.provider") private var brainProviderRaw = BrainProviderChoice.auto.rawValue
    @State private var brainTestResult: String?
    @State private var testingBrain = false
    @State private var personalVoiceEnabled = VoiceDirector.shared.personalVoiceAuthorized
    @State private var availableVoiceIdentifiers: [String] = []
    @State private var voiceNames: [String: String] = [:]
    @State private var voiceOverrides: [String: String] = [:]

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

                    ThemedSegments(theme: theme, options: [
                        ("Glow on dark", ContrastTheme.lightOnDark),
                        ("Dark on light", .darkOnLight),
                        ("Yellow on black", .highContrastYellow),
                    ], selection: $appModel.vault.calibration.contrastTheme)

                    ThemedSegments(theme: theme, options: [
                        ("Let her explore", HintAggressiveness.gentle),
                        ("Balanced", .standard),
                        ("Help early", .eager),
                    ], selection: $appModel.vault.calibration.hintAggressiveness)
                }

                section("Companion voices", theme) {
                    Text("The best installed voices are assigned automatically. For nicer ones: Settings → Accessibility → Spoken Content → Voices → English, and download Premium or Enhanced voices. To add YOUR voice: record it in Settings → Accessibility → Personal Voice, then enable access here and pick it for any companion.")
                        .font(.system(size: 14))
                        .foregroundColor(theme.text.opacity(0.7))

                    if #available(iOS 17.0, *) {
                        Button(personalVoiceEnabled ? "Personal Voice access enabled ✓" : "Enable Personal Voice access") {
                            VoiceDirector.shared.requestPersonalVoiceAccess { granted in
                                personalVoiceEnabled = granted
                                refreshVoices()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(theme.accent)
                    }

                    voiceRow(id: VoiceDirector.narratorID, name: "Narrator", theme: theme) {
                        appModel.narrator.speak("Welcome to Lantern, \(appModel.childName)! I'll be telling the story.")
                    }

                    ForEach(appModel.availableCompanions) { companion in
                        voiceRow(id: companion.id, name: companion.name, theme: theme) {
                            let line = companion.speechStyle.catchphrases.first ?? companion.introduction
                            appModel.narrator.speak("\(line)", voice: companion.resolvedVoice)
                        }
                    }
                }

                section("Companion AI (optional)", theme) {
                    Text("The game works fully offline without any of this. Auto picks the best brain available: a server you configure, then Apple's on-device model (on Apple Intelligence devices), then the built-in storyteller. Anything that fails hands off seamlessly mid-conversation.")
                        .font(.system(size: 14))
                        .foregroundColor(theme.text.opacity(0.7))

                    ThemedSegments(theme: theme,
                                   options: BrainProviderChoice.allCases.map { ($0.label, $0.rawValue) },
                                   selection: $brainProviderRaw)

                    Text(appModel.brainStatusDescription)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.highlight)

                    if brainProviderRaw == BrainProviderChoice.remote.rawValue {
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

                    Button(testingBrain ? "Asking..." : "Test the companion brain") {
                        testingBrain = true
                        brainTestResult = nil
                        Task {
                            brainTestResult = await appModel.testBrain()
                            testingBrain = false
                        }
                    }
                    .disabled(testingBrain)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)

                    if let brainTestResult {
                        Text(brainTestResult)
                            .font(.system(size: 14))
                            .foregroundColor(theme.text.opacity(0.85))
                    }
                }

                section("About Lantern", theme) {
                    Text("Lantern is an audio-first story adventure built for visually impaired kids — made by a dad for his daughter, and shared free in her honor.")
                        .font(.system(size: 14))
                    Text("Privacy: Lantern collects nothing. Progress, names, and memories stay on this device. Voice input runs on-device after an explicit tap. The only data that ever leaves is to an AI server a parent configures above — and that's off by default. Full policy: PRIVACY.md in the project repository.")
                        .font(.system(size: 14))
                        .foregroundColor(theme.text.opacity(0.8))
                    Text("Credits: current sounds are original procedurally generated placeholders (CC0). All assets are ledgered in ASSETS.md; attributions for any future licensed assets will appear here.")
                        .font(.system(size: 14))
                        .foregroundColor(theme.text.opacity(0.8))
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
        .onAppear {
            refreshVoices()
            for id in appModel.availableCompanions.map(\.id) + [VoiceDirector.narratorID] {
                voiceOverrides[id] = VoiceDirector.shared.overrideIdentifier(for: id) ?? ""
            }
        }
    }

    private func refreshVoices() {
        let ranked = VoiceDirector.shared.rankedVoices()
        availableVoiceIdentifiers = ranked.map(\.identifier)
        voiceNames = Dictionary(uniqueKeysWithValues: ranked.map {
            ($0.identifier, VoiceDirector.shared.displayName($0))
        })
    }

    private func currentVoiceName(for companionID: String) -> String {
        let override = voiceOverrides[companionID] ?? ""
        if override.isEmpty { return "Automatic (best installed)" }
        return voiceNames[override] ?? "Chosen voice"
    }

    /// One voice row: who it is + Hear preview, with the picker on its own
    /// line so long voice names never collide with the buttons.
    private func voiceRow(id: String, name: String, theme: Theme,
                          hear: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button("Hear", action: hear)
                    .buttonStyle(.bordered)
                    .tint(theme.accent)
            }
            Menu {
                Picker("Voice for \(name)", selection: voiceBinding(for: id)) {
                    Text("Automatic (best installed)").tag("")
                    ForEach(availableVoiceIdentifiers, id: \.self) { identifier in
                        Text(voiceNames[identifier] ?? identifier).tag(identifier)
                    }
                }
            } label: {
                HStack {
                    Text(currentVoiceName(for: id))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(theme.highlight)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.text.opacity(0.6))
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.accent.opacity(0.5), lineWidth: 2)
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func voiceBinding(for companionID: String) -> Binding<String> {
        Binding(
            get: { voiceOverrides[companionID] ?? "" },
            set: { newValue in
                voiceOverrides[companionID] = newValue
                VoiceDirector.shared.setOverride(newValue.isEmpty ? nil : newValue,
                                                 for: companionID)
            })
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
