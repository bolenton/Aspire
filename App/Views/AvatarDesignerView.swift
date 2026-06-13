import Combine
import RealityKit
import StoryEngine
import SwiftUI
import UIKit

/// The hero ceremony: she designs herself before the adventure starts.
/// Audio-first like everything else — every tap is named out loud, the
/// preview spins slowly so the shape reads from every side, and there is
/// no wrong answer anywhere on this screen.
struct AvatarDesignerView: View {
    @EnvironmentObject var appModel: AppModel
    let slotID: String

    private var avatar: AvatarSpec { appModel.vault.avatar }

    var body: some View {
        let theme = appModel.theme
        ZStack {
            theme.background.ignoresSafeArea()
            HStack(alignment: .top, spacing: 26) {
                VStack(spacing: 18) {
                    Text("This is you!")
                        .font(.system(size: theme.fontSize(32), weight: .heavy, design: .rounded))
                        .foregroundColor(theme.accent)

                    AvatarPreviewView(spec: avatar, background: UIColor(theme.background))
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(theme.accent, lineWidth: 4))

                    Button("All done — let's go!") {
                        appModel.finishAvatarDesign(slotID: slotID)
                    }
                    .buttonStyle(GiantButtonStyle(theme: theme))
                }
                .frame(maxWidth: 380)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        section("Who are you?", theme) {
                            HStack(spacing: 14) {
                                chip("Boy", selected: avatar.body == .boy, theme) {
                                    update(spokenName: AvatarSpec.BodyStyle.boy.spokenName) { $0.body = .boy }
                                }
                                chip("Girl", selected: avatar.body == .girl, theme) {
                                    update(spokenName: AvatarSpec.BodyStyle.girl.spokenName) { $0.body = .girl }
                                }
                            }
                        }

                        section("Your skin", theme) {
                            swatchRow(AvatarPalette.skinTones, selectedID: avatar.skinToneID, theme) { option in
                                update(spokenName: "\(option.spokenName) skin") { $0.skinToneID = option.id }
                            }
                        }

                        section("Your hair", theme) {
                            // Two rows so every style stays a big target.
                            let styles = AvatarSpec.HairStyle.allCases
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach([Array(styles.prefix(3)), Array(styles.dropFirst(3))], id: \.first) { row in
                                    HStack(spacing: 12) {
                                        ForEach(row, id: \.self) { style in
                                            chip(label(for: style), selected: avatar.hairStyle == style, theme) {
                                                update(spokenName: style.spokenName) { $0.hairStyle = style }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if avatar.hairStyle != .bald {
                            section("Hair color", theme) {
                                swatchRow(AvatarPalette.hairColors, selectedID: avatar.hairColorID, theme) { option in
                                    update(spokenName: "\(option.spokenName) hair") { $0.hairColorID = option.id }
                                }
                            }
                        }

                        section("Your outfit", theme) {
                            swatchRow(AvatarPalette.outfitColors, selectedID: avatar.outfitColorID, theme) { option in
                                update(spokenName: "\(option.spokenName) clothes") { $0.outfitColorID = option.id }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .padding(32)
        }
        .onAppear {
            appModel.narrator.speak(
                "Time to make YOU, \(appModel.childName)! Tap the choices to build your hero — I'll say each one out loud. Right now you're \(avatar.spokenDescription). When you love how you look, tap All done.")
        }
    }

    /// Every change speaks its name and shows instantly on the spinning hero.
    private func update(spokenName: String, _ change: (inout AvatarSpec) -> Void) {
        change(&appModel.vault.avatar)
        appModel.narrator.speak(spokenName)
    }

    private func label(for style: AvatarSpec.HairStyle) -> String {
        switch style {
        case .short: return "Short"
        case .long: return "Long"
        case .curly: return "Curly"
        case .braids: return "Braids"
        case .bald: return "None"
        }
    }

    private func section(_ title: String, _ theme: Theme,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: theme.fontSize(24), weight: .bold, design: .rounded))
                .foregroundColor(theme.accent)
            content()
        }
    }

    private func chip(_ label: String, selected: Bool, _ theme: Theme,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: theme.fontSize(20), weight: .bold, design: .rounded))
                .foregroundColor(selected ? theme.background : theme.text)
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(selected ? theme.accent : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.accent, lineWidth: 4))
                )
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func swatchRow(_ options: [AvatarColorOption], selectedID: String, _ theme: Theme,
                           onPick: @escaping (AvatarColorOption) -> Void) -> some View {
        HStack(spacing: 14) {
            ForEach(options) { option in
                Button {
                    onPick(option)
                } label: {
                    Circle()
                        .fill(Color(WorldBuilder.color(hex: option.hex)))
                        .frame(width: theme.fontSize(54), height: theme.fontSize(54))
                        .overlay(
                            Circle().stroke(option.id == selectedID ? theme.highlight : theme.accent.opacity(0.45),
                                            lineWidth: option.id == selectedID ? 6 : 3)
                        )
                        .shadow(color: theme.accent.opacity(option.id == selectedID ? 0.7 : 0),
                                radius: 10)
                }
                .accessibilityLabel(option.spokenName)
                .accessibilityAddTraits(option.id == selectedID ? .isSelected : [])
            }
        }
    }
}

/// A tiny non-AR RealityKit stage: just her hero, a light, and a slow spin.
private struct AvatarPreviewView: UIViewRepresentable {
    var spec: AvatarSpec
    var background: UIColor

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.isUserInteractionEnabled = false
        arView.environment.background = .color(background)

        let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
        arView.scene.addAnchor(anchor)

        let light = DirectionalLight()
        light.light.intensity = 1400
        light.orientation = simd_quatf(angle: -.pi / 3, axis: SIMD3<Float>(1, 0, 0))
        light.position = SIMD3<Float>(0, 3, 2)
        anchor.addChild(light)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 50
        camera.position = SIMD3<Float>(0, 1.2, 2.7)
        camera.look(at: SIMD3<Float>(0, 0.78, 0), from: camera.position, relativeTo: nil)
        anchor.addChild(camera)

        context.coordinator.anchor = anchor
        context.coordinator.attach(arView: arView)
        context.coordinator.show(spec: spec)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        uiView.environment.background = .color(background)
        context.coordinator.show(spec: spec)
    }

    final class Coordinator {
        var anchor: AnchorEntity?
        private var hero: RealityKit.Entity?
        private var shownSpec: AvatarSpec?
        private var spin: Cancellable?
        private var angle: Float = 0

        func attach(arView: ARView) {
            spin = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                guard let self, let hero = self.hero else { return }
                self.angle += Float(event.deltaTime) * 0.6
                hero.orientation = simd_quatf(angle: self.angle, axis: SIMD3<Float>(0, 1, 0))
            }
        }

        /// Swap-in rebuild on any change; the spin angle carries over so the
        /// hero never visibly "resets".
        func show(spec: AvatarSpec) {
            guard spec != shownSpec, let anchor else { return }
            shownSpec = spec
            let next = VoxelWorld.playerAvatar(spec: spec)
            next.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
            anchor.addChild(next)
            hero?.removeFromParent()
            hero = next
        }
    }
}
