import Combine
import RealityKit
import StoryEngine
import SwiftUI
import UIKit

/// The glowing first-person world. Non-AR RealityKit camera glides with her
/// pose; entities rebuild when the world changes (collects, unlocks); the
/// quest target's halo breathes; fireflies drift like tiny lanterns.
/// Vision confirms — the audio remains the world.
struct WorldView: UIViewRepresentable {
    @ObservedObject var model: GameViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(UIColor(red: 0.03, green: 0.03, blue: 0.09, alpha: 1))
        arView.isUserInteractionEnabled = false
        context.coordinator.attach(to: arView)
        sync(context.coordinator)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        sync(context.coordinator)
    }

    private func sync(_ coordinator: Coordinator) {
        coordinator.setCameraTarget(pose: model.pose)
        if coordinator.builtRevision != model.worldRevision {
            coordinator.rebuildEntities(
                resolved: model.resolvedEntities,
                companionName: model.companion.name,
                glowBoost: model.slot.difficulty.support.glowBoost,
                questTargetID: model.currentStep?.targetEntityID,
                revision: model.worldRevision)
        } else {
            coordinator.setQuestTarget(model.currentStep?.targetEntityID)
        }
    }

    final class Coordinator {
        private weak var arView: ARView?
        private var worldAnchor: AnchorEntity?
        private var camera: PerspectiveCamera?
        private var playerEntity: RealityKit.Entity?
        private var beacon: ModelEntity?
        private var entityNodes: [String: RealityKit.Entity] = [:]
        private var fireflies: [(entity: ModelEntity, phase: Float, radius: Float, center: SIMD3<Float>)] = []
        private var updateSubscription: Cancellable?

        private(set) var builtRevision = -1
        private var questTargetID: String?
        private var targetPosition = SIMD3<Float>(0, 0, 0)
        private var targetYaw: Float = 0
        private var elapsed: Float = 0

        func attach(to arView: ARView) {
            self.arView = arView

            let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
            arView.scene.addAnchor(anchor)
            worldAnchor = anchor

            anchor.addChild(WorldBuilder.ground())
            anchor.addChild(WorldBuilder.groundDots())

            let player = WorldBuilder.playerMarker()
            anchor.addChild(player)
            playerEntity = player

            let beacon = WorldBuilder.questBeacon()
            beacon.isEnabled = false
            anchor.addChild(beacon)
            self.beacon = beacon

            let light = DirectionalLight()
            light.light.intensity = 1200
            light.orientation = simd_quatf(angle: -.pi / 3, axis: SIMD3<Float>(1, 0, 0))
            light.position = SIMD3<Float>(0, 8, 0)
            anchor.addChild(light)

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 70
            camera.position = targetPosition
            anchor.addChild(camera)
            self.camera = camera

            for _ in 0..<14 {
                let firefly = WorldBuilder.firefly()
                let center = SIMD3<Float>(Float.random(in: -16...16), 0,
                                          Float.random(in: -18...8))
                anchor.addChild(firefly)
                fireflies.append((firefly, Float.random(in: 0...(2 * .pi)),
                                  Float.random(in: 0.6...2.2), center))
            }

            updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                self?.tick(deltaTime: Float(event.deltaTime))
            }
        }

        func setCameraTarget(pose: PlayerPose) {
            targetPosition = SIMD3<Float>(Float(pose.position.x), 0, Float(pose.position.z))
            targetYaw = Float(-pose.headingDegrees * .pi / 180)
        }

        func setQuestTarget(_ id: String?) {
            questTargetID = id
        }

        func rebuildEntities(resolved: [ResolvedEntity], companionName: String,
                             glowBoost: Double, questTargetID: String?, revision: Int) {
            guard let worldAnchor else { return }
            for node in entityNodes.values {
                node.removeFromParent()
            }
            entityNodes = [:]
            for item in resolved {
                let node = WorldBuilder.build(item, companionName: companionName,
                                              glowBoost: glowBoost)
                worldAnchor.addChild(node)
                entityNodes[item.entity.id] = node
            }
            self.questTargetID = questTargetID
            builtRevision = revision
        }

        private func tick(deltaTime: Float) {
            elapsed += deltaTime
            let blend: Float = min(1.0, deltaTime * 4.5)

            // Third-person camera: behind and above her, so she can SEE
            // herself, her companion's world, and where she's headed.
            let headingRad = -targetYaw
            let forward = SIMD3<Float>(sin(headingRad), 0, -cos(headingRad))
            if let camera {
                let goal = targetPosition - forward * 7.5 + SIMD3<Float>(0, 5.5, 0)
                camera.position += (goal - camera.position) * blend
                camera.look(at: targetPosition + forward * 2.5 + SIMD3<Float>(0, 1.0, 0),
                            from: camera.position, relativeTo: nil)
            }

            if let playerEntity {
                playerEntity.position += (targetPosition - playerEntity.position) * min(1.0, deltaTime * 6.0)
                playerEntity.orientation = simd_slerp(
                    playerEntity.orientation,
                    simd_quatf(angle: targetYaw, axis: SIMD3<Float>(0, 1, 0)),
                    min(1.0, deltaTime * 6.0))
            }

            if let beacon {
                if let id = questTargetID, let node = entityNodes[id] {
                    beacon.isEnabled = true
                    beacon.position = SIMD3<Float>(node.position.x, 7, node.position.z)
                    let pulse = 1.0 + 0.1 * sin(elapsed * 2.0)
                    beacon.scale = SIMD3<Float>(pulse, 1.0, pulse)
                } else {
                    beacon.isEnabled = false
                }
            }

            for (firefly, phase, radius, center) in fireflies {
                let t = elapsed * 0.35 + phase
                firefly.position = SIMD3<Float>(
                    center.x + radius * cos(t),
                    1.0 + 0.5 * sin(elapsed * 0.8 + phase * 2),
                    center.z + radius * sin(t))
            }

            // The quest target's halo breathes so her eye can find it.
            if let id = questTargetID, let node = entityNodes[id] {
                let pulse = 1.0 + 0.18 * sin(elapsed * 2.4)
                for child in node.children where child.name == "halo" {
                    child.scale = SIMD3<Float>(repeating: pulse)
                }
            }
        }
    }
}
