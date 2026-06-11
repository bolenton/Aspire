import AVFoundation
import SwiftUI
import StoryEngine

@main
struct LanternApp: App {
    @StateObject private var appModel = AppModel()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        let theme = appModel.theme
        ZStack {
            switch appModel.route {
            case .home:
                HomeView()
            case .calibration:
                CalibrationWizardView()
            case .companionPicker:
                CompanionPickerView()
            case .game(let slotID):
                if let model = appModel.makeGameViewModel(slotID: slotID) {
                    GameView(model: model)
                        .id(slotID)
                } else {
                    HomeView()
                }
            }

            if appModel.frozen {
                theme.background.opacity(0.55)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                VStack(spacing: 16) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: theme.fontSize(60)))
                    Text("Hold still... I'll explain everything")
                        .font(.system(size: theme.fontSize(24), weight: .bold, design: .rounded))
                }
                .foregroundColor(theme.accent)
                .allowsHitTesting(false)
            }
        }
        .background(
            FreezeGestureView(
                onBegan: { appModel.freezeBegan() },
                onEnded: { appModel.freezeEnded() })
        )
        .animation(.easeInOut(duration: 0.2), value: appModel.frozen)
    }
}
