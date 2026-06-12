import Combine
import RealityKit
import StoryEngine
import SwiftUI
import UIKit

/// The chunky voxel world, third-person. Each scene builds its biome
/// deterministically (forest meadow, crystal cave, walled courtyard); story
/// entities rebuild when the world changes; her blocky adventurer bobs as
/// she walks; items spin like pickups; the quest beacon stays readable from
/// anywhere. Vision confirms — the audio remains the world.
struct WorldView: UIViewRepresentable {
    @ObservedObject var model: GameViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
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
        coordinator.setScene(id: model.scene?.id, environment: model.scene?.environment)
        if coordinator.builtRevision != model.worldRevision {
            coordinator.rebuildEntities(
                resolved: model.resolvedEntities,
                companion: model.companion,
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
        private var light: DirectionalLight?
        private var playerEntity: RealityKit.Entity?
        private var beacon: ModelEntity?
        private var terrain: RealityKit.Entity?
        private var entityNodes: [String: RealityKit.Entity] = [:]
        private var entityKinds: [String: EntityKind] = [:]
        private var fireflies: [(entity: ModelEntity, phase: Float, radius: Float, center: SIMD3<Float>)] = []
        private var updateSubscription: Cancellable?

        private(set) var builtRevision = -1
        private var builtSceneID: String?
        private var questTargetID: String?
        private var targetPosition = SIMD3<Float>(0, 0, 0)
        private var targetYaw: Float = 0
        private var elapsed: Float = 0
        private var walkPhase: Float = 0

        func attach(to arView: ARView) {
            self.arView = arView

            let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
            arView.scene.addAnchor(anchor)
            worldAnchor = anchor

            let player = VoxelWorld.playerAvatar()
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
            self.light = light

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 70
            camera.position = SIMD3<Float>(0, 5.5, 7.5)
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

        /// Rebuilds the biome when she travels: blocky terrain, scatter, and
        /// the sky color all come from the scene's environment, seeded by
        /// the scene id so each place always looks like itself.
        func setScene(id: String?, environment: String?) {
            guard let id, id != builtSceneID, let worldAnchor else { return }
            builtSceneID = id

            terrain?.removeFromParent()
            let newTerrain = VoxelWorld.terrain(environment: environment, seedKey: id)
            worldAnchor.addChild(newTerrain)
            terrain = newTerrain

            let biome = VoxelWorld.biome(for: environment)
            arView?.environment.background = .color(biome.skyColor)
            light?.light.intensity = biome.lightIntensity
        }

        func rebuildEntities(resolved: [ResolvedEntity], companion: Companion,
                             glowBoost: Double, questTargetID: String?, revision: Int) {
            guard let worldAnchor else { return }
            for node in entityNodes.values {
                node.removeFromParent()
            }
            entityNodes = [:]
            entityKinds = [:]
            for item in resolved {
                let node = WorldBuilder.build(item, companion: companion,
                                              glowBoost: glowBoost)
                worldAnchor.addChild(node)
                entityNodes[item.entity.id] = node
                entityKinds[item.entity.id] = item.entity.kind
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
                let toTarget = targetPosition - SIMD3<Float>(playerEntity.position.x, 0, playerEntity.position.z)
                let isWalking = simd_length(toTarget) > 0.08
                if isWalking {
                    walkPhase += deltaTime * 11
                }
                let bob = isWalking ? abs(sin(walkPhase)) * 0.14 : 0
                var next = playerEntity.position + toTarget * min(1.0, deltaTime * 6.0)
                next.y += (bob - next.y) * min(1.0, deltaTime * 12.0)
                playerEntity.position = next
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

            // Living touches: items spin like pickups, the companion critter
            // hops in place, butterfly wings flap, the quest halo breathes.
            for (id, node) in entityNodes {
                guard let body = node.children.first(where: { $0.name == "body" }) else { continue }
                switch entityKinds[id] {
                case .item:
                    body.orientation = simd_quatf(angle: elapsed * 0.9, axis: SIMD3<Float>(0, 1, 0))
                case .companion:
                    body.position.y = abs(sin(elapsed * 2.2)) * 0.12
                    for wing in body.children where wing.name == "wing" {
                        let flap = sin(elapsed * 9) * 0.6
                        wing.orientation = simd_quatf(angle: wing.position.x > 0 ? flap : -flap,
                                                      axis: SIMD3<Float>(0, 0, 1))
                    }
                default:
                    break
                }
            }
            if let id = questTargetID, let node = entityNodes[id] {
                let pulse = 1.0 + 0.18 * sin(elapsed * 2.4)
                for child in node.children where child.name == "halo" {
                    child.scale = SIMD3<Float>(repeating: pulse)
                }
            }
        }
    }
}
