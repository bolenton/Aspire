import SwiftUI
import StoryEngine

struct HomeView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var showParentGate = false

    var body: some View {
        let theme = appModel.theme
        ZStack {
            theme.background.ignoresSafeArea()
            VStack(spacing: 30) {
                Spacer()
                Text("Lantern")
                    .font(.system(size: theme.fontSize(64), weight: .heavy, design: .rounded))
                    .foregroundColor(theme.accent)
                    .shadow(color: theme.accent.opacity(0.7), radius: 20)
                Text(appModel.pack.title)
                    .font(.system(size: theme.fontSize(28), weight: .semibold, design: .rounded))
                    .foregroundColor(theme.text)
                Spacer()

                if let slot = appModel.latestSlot,
                   let companion = appModel.availableCompanions.first(where: { $0.id == slot.companionID }) {
                    Button("Keep playing with \(companion.name)") {
                        appModel.route = .game(slotID: slot.id)
                    }
                    .buttonStyle(GiantButtonStyle(theme: theme))
                }

                Button("Start a new adventure") {
                    appModel.startNewAdventure()
                }
                .buttonStyle(GiantButtonStyle(theme: theme, filled: appModel.latestSlot == nil))

                Spacer()

                Button {
                    showParentGate = true
                } label: {
                    Label("Grown-ups", systemImage: "gearshape.fill")
                        .font(.system(size: theme.fontSize(16), weight: .medium))
                        .foregroundColor(theme.text.opacity(0.6))
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 60)
        }
        .sheet(isPresented: $showParentGate) {
            ParentGateView()
                .environmentObject(appModel)
        }
        .onAppear {
            let greeting = appModel.vault.calibration.childName.isEmpty
                ? "Welcome to Lantern! Ask a grown-up to help you start your first adventure."
                : "Welcome back to Lantern, \(appModel.childName)!"
            let musicVolume = Float(appModel.vault.calibration.musicVolume)
            appModel.narrator.speak(greeting) {
                SoundBank.shared.playMusic("song1.mp3", volume: musicVolume)
            }
        }
        .onDisappear {
            SoundBank.shared.stopMusic()
        }
    }
}
