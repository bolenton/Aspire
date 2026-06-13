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
    @AppStorage("brain.provider") private var brainProviderRaw = BrainProviderChoice.auto.rawValue
    @State private var brainTestResult: String?
    @State private var testingBrain = false
    @State private var personalVoiceEnabled = VoiceDirector.shared.personalVoiceAuthorized
    @State private var availableVoiceIdentifiers: [String] = []
    @State private var voiceNames: [String: String] = [:]
    @State private var voiceOverrides: [String: String] = [:]

    /// API keys are Keychain-backed (not @AppStorage): a mirror @State holds
    /// the SecureField text, and edits write straight through to the Keychain.
    @State private var brainAPIKeyField = ""

    // Premium voices
    @AppStorage("tts.provider") private var ttsProviderRaw = TTSProviderChoice.system.rawValue
    @AppStorage("tts.elevenlabs.model") private var ttsElevenLabsModel = ""
    @AppStorage("tts.openai.endpoint") private var ttsOpenAIEndpoint = ""
    @AppStorage("tts.openai.model") private var ttsOpenAIModel = ""
    @State private var elevenLabsKeyField = ""
    @State private var openAIKeyField = ""
    @State private var cloudVoices: [TTSVoice] = []
    @State private var cloudVoiceSelections: [String: String] = [:]
    @State private var loadingVoices = false
    @State private var voiceListError: String?
    @State private var voiceTestResult: String?
    @State private var testingVoice = false
    @State private var cacheSizeText = ""

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
                    labeledSlider("Voice volume", value: $appModel.vault.calibration.narrationVolume,
                                  range: 0.4...1.0, theme: theme)
                    labeledSlider("World sounds", value: $appModel.vault.calibration.worldVolume,
                                  range: 0.1...1.0, theme: theme)

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
                        SecureField("API key (only for cloud gateways)", text: $brainAPIKeyField)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: brainAPIKeyField) { _, newValue in
                                KeychainStore.set(newValue, for: KeychainStore.Key.brain)
                            }
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

                premiumVoiceSection(theme)

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
                    // A just-changed provider or voice takes effect now.
                    appModel.reinstallTTSProvider()
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
            let ids = appModel.availableCompanions.map(\.id) + [VoiceDirector.narratorID]
            for id in ids {
                voiceOverrides[id] = VoiceDirector.shared.overrideIdentifier(for: id) ?? ""
                cloudVoiceSelections[id] = VoiceDirector.shared.cloudVoiceID(for: id) ?? ""
            }
            brainAPIKeyField = appModel.brainAPIKey
            elevenLabsKeyField = KeychainStore.get(KeychainStore.Key.elevenLabs) ?? ""
            openAIKeyField = KeychainStore.get(KeychainStore.Key.openAI) ?? ""
            cacheSizeText = formattedCacheSize()
            loadCloudVoicesIfPossible()
        }
    }

    private func refreshVoices() {
        let ranked = VoiceDirector.shared.rankedVoices()
        availableVoiceIdentifiers = ranked.map(\.identifier)
        voiceNames = Dictionary(uniqueKeysWithValues: ranked.map {
            ($0.identifier, VoiceDirector.shared.displayName($0))
        })
    }

    // MARK: - Premium voices

    private var ttsChoice: TTSProviderChoice {
        TTSProviderChoice(rawValue: ttsProviderRaw) ?? .system
    }

    @ViewBuilder
    private func premiumVoiceSection(_ theme: Theme) -> some View {
        section("Premium voices (optional)", theme) {
            Text("Works fully offline without this — Apple's built-in voices are always available. Add a neural-TTS service for richer, more lifelike companions. Lines are cached on the device so each one plays instantly the next time, even with no signal.")
                .font(.system(size: 14))
                .foregroundColor(theme.text.opacity(0.7))

            ThemedSegments(theme: theme,
                           options: TTSProviderChoice.allCases.map { ($0.label, $0.rawValue) },
                           selection: $ttsProviderRaw)

            Text(appModel.ttsStatusDescription)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.highlight)

            if ttsChoice == .elevenLabs {
                SecureField("ElevenLabs API key", text: $elevenLabsKeyField)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: elevenLabsKeyField) { _, newValue in
                        KeychainStore.set(newValue, for: KeychainStore.Key.elevenLabs)
                    }
                TextField("Model (default eleven_flash_v2_5)", text: $ttsElevenLabsModel)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else if ttsChoice == .openAICompatible {
                TextField("Server address, e.g. https://api.openai.com", text: $ttsOpenAIEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Model (default gpt-4o-mini-tts)", text: $ttsOpenAIModel)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("API key (leave blank for a keyless local server)", text: $openAIKeyField)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: openAIKeyField) { _, newValue in
                        KeychainStore.set(newValue, for: KeychainStore.Key.openAI)
                    }
            }

            if ttsChoice != .system {
                HStack {
                    Button(loadingVoices ? "Loading voices…" : "Refresh voice list") {
                        loadCloudVoicesIfPossible(force: true)
                    }
                    .disabled(loadingVoices)
                    .buttonStyle(.bordered)
                    .tint(theme.accent)
                    Spacer()
                }

                if let voiceListError {
                    Text(voiceListError)
                        .font(.system(size: 13))
                        .foregroundColor(theme.text.opacity(0.85))
                }

                cloudVoiceRow(id: VoiceDirector.narratorID, name: "Narrator", theme: theme)
                ForEach(appModel.availableCompanions) { companion in
                    cloudVoiceRow(id: companion.id, name: companion.name, theme: theme)
                }

                Button(testingVoice ? "Speaking…" : "Test the premium voice") {
                    testingVoice = true
                    voiceTestResult = nil
                    Task {
                        appModel.reinstallTTSProvider()
                        voiceTestResult = await appModel.testVoice()
                        testingVoice = false
                    }
                }
                .disabled(testingVoice)
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)

                if let voiceTestResult {
                    Text(voiceTestResult)
                        .font(.system(size: 14))
                        .foregroundColor(theme.text.opacity(0.85))
                }
            }

            HStack {
                Text("Voice cache: \(cacheSizeText)")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Clear voice cache") {
                    appModel.narrator.cache.clear()
                    cacheSizeText = formattedCacheSize()
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)
            }
        }
    }

    /// One cloud-voice picker row. ElevenLabs voices come from listVoices();
    /// the OpenAI-compatible provider also offers a free-text field so a local
    /// server's custom voice names can be entered directly.
    @ViewBuilder
    private func cloudVoiceRow(id: String, name: String, theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Menu {
                Picker("Premium voice for \(name)", selection: cloudVoiceBinding(for: id)) {
                    Text("None (Apple's voice)").tag("")
                    ForEach(cloudVoices) { voice in
                        Text(voice.detail.map { "\(voice.name) — \($0)" } ?? voice.name)
                            .tag(voice.id)
                    }
                }
            } label: {
                HStack {
                    Text(currentCloudVoiceName(for: id))
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
                .background(RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.accent.opacity(0.5), lineWidth: 2))
            }

            if ttsChoice == .openAICompatible {
                TextField("…or type a voice name", text: cloudVoiceBinding(for: id))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 14))
            }
        }
        .padding(.vertical, 4)
    }

    private func currentCloudVoiceName(for id: String) -> String {
        let chosen = cloudVoiceSelections[id] ?? ""
        if chosen.isEmpty { return "None (Apple's voice)" }
        if let match = cloudVoices.first(where: { $0.id == chosen }) { return match.name }
        return chosen
    }

    private func cloudVoiceBinding(for id: String) -> Binding<String> {
        Binding(
            get: { cloudVoiceSelections[id] ?? "" },
            set: { newValue in
                cloudVoiceSelections[id] = newValue
                VoiceDirector.shared.setCloudVoiceID(newValue.isEmpty ? nil : newValue, for: id)
            })
    }

    /// Fetches the provider's voice catalog when a key is configured. Honest:
    /// a failure shows the service's own error, not a silent empty list.
    private func loadCloudVoicesIfPossible(force: Bool = false) {
        guard ttsChoice != .system else {
            cloudVoices = []
            return
        }
        guard let provider = appModel.makeTTSProvider() else {
            if force { voiceListError = "Add the API key (or server address) first." }
            return
        }
        if loadingVoices { return }
        if !cloudVoices.isEmpty && !force { return }
        loadingVoices = true
        voiceListError = nil
        Task {
            do {
                let voices = try await provider.listVoices()
                cloudVoices = voices
                voiceListError = voices.isEmpty ? "The service returned no voices." : nil
            } catch {
                cloudVoices = []
                voiceListError = "Couldn't load voices: \(error.localizedDescription)"
            }
            loadingVoices = false
        }
    }

    private func formattedCacheSize() -> String {
        ByteCountFormatter.string(fromByteCount: Int64(appModel.narrator.cache.totalSize),
                                  countStyle: .file)
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
