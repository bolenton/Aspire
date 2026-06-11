import SwiftUI
import StoryEngine

struct GameView: View {
    @EnvironmentObject var appModel: AppModel
    @StateObject private var model: GameViewModel
    @StateObject private var listener = SpeechListener()

    init(model: GameViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        let theme = appModel.theme
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 16) {
                header(theme)

                ScrollView {
                    NarrationTextView(narrator: model.narrator, theme: theme)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
                .frame(maxHeight: .infinity)

                if let nearby = model.nearbyEntity {
                    Button(actionLabel(for: nearby)) {
                        model.interactWithNearby()
                    }
                    .buttonStyle(GiantButtonStyle(theme: theme))
                }

                controls(theme)
            }
            .padding(28)

            if model.currentDialogue != nil {
                dialogueOverlay(theme)
            }
            if model.activeSongSpell != nil {
                songOverlay(theme)
            }
        }
        .onAppear {
            SpeechListener.requestPermissions()
            appModel.activeGame = model
            model.begin()
        }
        .onDisappear {
            appModel.activeGame = nil
            model.audio.removeAllSources()
            model.persist()
        }
    }

    private func actionLabel(for resolved: ResolvedEntity) -> String {
        let name = resolved.entity.id == StoryConventions.companionPlaceholder
            ? model.companion.name : resolved.entity.name
        switch resolved.entity.kind {
        case .companion, .character: return "Talk to \(name)"
        case .item: return "Pick up the \(name)"
        case .portal: return "Go through the \(name)"
        case .landmark: return "Visit the \(name)"
        }
    }

    private func header(_ theme: Theme) -> some View {
        HStack {
            Button {
                appModel.route = .home
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: theme.fontSize(22)))
                    .foregroundColor(theme.text.opacity(0.7))
                    .padding(14)
            }
            .accessibilityLabel("Home")

            Spacer()
            VStack(spacing: 4) {
                Text(model.scene?.name ?? "Lantern")
                    .font(.system(size: theme.fontSize(30), weight: .heavy, design: .rounded))
                    .foregroundColor(theme.accent)
                if let quest = model.slot.progress.activeQuest(in: model.pack) {
                    Text(quest.title)
                        .font(.system(size: theme.fontSize(16), weight: .semibold, design: .rounded))
                        .foregroundColor(theme.text.opacity(0.8))
                }
            }
            Spacer()

            Button {
                model.requestHint()
            } label: {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: theme.fontSize(22)))
                    .foregroundColor(theme.accent)
                    .padding(14)
            }
            .accessibilityLabel("Hint")
        }
    }

    private func controls(_ theme: Theme) -> some View {
        HStack(spacing: 18) {
            controlButton(theme, system: "arrow.turn.up.left", label: "Turn left") {
                model.turn(degrees: -45)
            }
            controlButton(theme, system: "arrow.up", label: "Walk") {
                model.walk()
            }
            controlButton(theme, system: "arrow.turn.up.right", label: "Turn right") {
                model.turn(degrees: 45)
            }

            Spacer()

            Button {
                if listener.isListening {
                    SoundBank.shared.play("earcon_listen_stop.wav")
                    listener.finishAndSend()
                } else {
                    model.narrator.stop()
                    SoundBank.shared.play("earcon_listen_start.wav")
                    listener.start { utterance in
                        model.ask(utterance)
                    }
                }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: listener.isListening ? "ear.fill" : "mic.fill")
                        .font(.system(size: theme.fontSize(30)))
                    Text(listener.isListening ? "I'm listening..." : "Talk to \(model.companion.name)")
                        .font(.system(size: theme.fontSize(15), weight: .bold, design: .rounded))
                }
                .foregroundColor(listener.isListening ? theme.background : theme.accent)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(listener.isListening ? theme.highlight : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.accent, lineWidth: 4))
                )
            }
            .accessibilityLabel(listener.isListening ? "Done talking" : "Talk to \(model.companion.name)")
        }
    }

    private func controlButton(_ theme: Theme, system: String, label: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: system)
                    .font(.system(size: theme.fontSize(32), weight: .bold))
                Text(label)
                    .font(.system(size: theme.fontSize(14), weight: .bold, design: .rounded))
            }
            .foregroundColor(theme.text)
            .frame(width: theme.fontSize(86), height: theme.fontSize(86))
            .background(RoundedRectangle(cornerRadius: 22).stroke(theme.accent, lineWidth: 4))
        }
        .accessibilityLabel(label)
    }

    private func dialogueOverlay(_ theme: Theme) -> some View {
        VStack(spacing: 24) {
            if let dialogue = model.currentDialogue {
                Text(dialogue.resolvedSpeaker(companion: model.companion))
                    .font(.system(size: theme.fontSize(22), weight: .heavy, design: .rounded))
                    .foregroundColor(theme.accent)
                Text(dialogue.line.resolved(for: model.companion.id))
                    .font(.system(size: theme.fontSize(26), weight: .semibold, design: .rounded))
                    .foregroundColor(theme.text)
                    .multilineTextAlignment(.center)

                let choices = dialogue.choices.filter {
                    $0.requiresCompanion == nil || $0.requiresCompanion == model.companion.id
                }
                if choices.isEmpty {
                    Button("Okay!") { model.choose(DialogueChoice(id: "_done", text: "Okay!")) }
                        .buttonStyle(GiantButtonStyle(theme: theme))
                } else {
                    ForEach(choices, id: \.id) { choice in
                        Button(choice.text.resolved(for: model.companion.id)) {
                            model.choose(choice)
                        }
                        .buttonStyle(GiantButtonStyle(theme: theme))
                    }
                }
            }
        }
        .padding(44)
        .background(
            RoundedRectangle(cornerRadius: 34)
                .fill(theme.background)
                .overlay(RoundedRectangle(cornerRadius: 34).stroke(theme.accent, lineWidth: 5))
                .shadow(color: theme.accent.opacity(0.5), radius: 30)
        )
        .padding(50)
        .onAppear {
            if let dialogue = model.currentDialogue {
                model.narrator.speak(dialogue.line.resolved(for: model.companion.id),
                                     voice: model.companion.voice)
            }
        }
    }

    private func songOverlay(_ theme: Theme) -> some View {
        VStack(spacing: 28) {
            if let spell = model.activeSongSpell {
                Text(spell.name)
                    .font(.system(size: theme.fontSize(28), weight: .heavy, design: .rounded))
                    .foregroundColor(theme.accent)

                HStack(spacing: 12) {
                    ForEach(0..<max(model.targetNotes.count, 1), id: \.self) { index in
                        Circle()
                            .fill(index < model.sungNotes.count ? theme.accent : theme.text.opacity(0.25))
                            .frame(width: 26, height: 26)
                    }
                }

                HStack(spacing: 18) {
                    ForEach(SolfegeNote.allCases.prefix(offeredNoteCount), id: \.self) { note in
                        Button(note.rawValue.capitalized) {
                            model.sing(note: note)
                        }
                        .buttonStyle(GiantButtonStyle(theme: theme, filled: false))
                    }
                }

                Button("Hear it again") {
                    model.playTargetMelody()
                }
                .buttonStyle(GiantButtonStyle(theme: theme))
            }
        }
        .padding(44)
        .background(
            RoundedRectangle(cornerRadius: 34)
                .fill(theme.background)
                .overlay(RoundedRectangle(cornerRadius: 34).stroke(theme.accent, lineWidth: 5))
                .shadow(color: theme.accent.opacity(0.5), radius: 30)
        )
        .padding(50)
    }

    /// Offer one extra note beyond the melody's highest, so there's a real
    /// (but gentle) choice.
    private var offeredNoteCount: Int {
        let highest = model.targetNotes.compactMap { SolfegeNote.allCases.firstIndex(of: $0) }.max() ?? 2
        return min(highest + 2, SolfegeNote.allCases.count)
    }
}
