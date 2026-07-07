import Foundation
import RealityKit
import StoryEngine
import UIKit

/// Builds the stylized-magical world from content data: few elements, huge
/// bold silhouettes, strong emissive glow on dark ground — visuals that
/// confirm what her ears already said. Everything is procedural primitives
/// for now; commissioned character/environment models replace these shapes
/// without touching the layout logic.
enum WorldBuilder {
    static func color(hex: String) -> UIColor {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        Scanner(string: cleaned).scanHexInt64(&value)
        return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255.0,
                       green: CGFloat((value >> 8) & 0xFF) / 255.0,
                       blue: CGFloat(value & 0xFF) / 255.0,
                       alpha: 1.0)
    }

    static func glowMaterial(_ color: UIColor, emissive: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = emissive
        // 0.7 leaves a hint of directional response now that the light casts
        // real shadows — pure 0.9 matte read as flat cardboard.
        material.roughness = 0.7
        material.metallic = 0.0
        return material
    }

    static func haloMaterial(_ color: UIColor, opacity: Float) -> PhysicallyBasedMaterial {
        var material = glowMaterial(color, emissive: 2.0)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    /// One world object: the bold shape, a soft additive halo shell, and a
    /// billboarded icon marker floating above — silhouette for close range,
    /// chip for across the meadow. The halo radius carries the calibrated/
    /// adaptive glow boost; high contrast collapses every interactable to
    /// loud yellow with white halos and markers.
    static func build(_ resolved: ResolvedEntity, companion: Companion,
                      glowBoost: Double, isQuestTarget: Bool,
                      highContrast: Bool) -> RealityKit.Entity {
        let root = RealityKit.Entity()
        let entity = resolved.entity
        root.position = SIMD3<Float>(Float(entity.position.x),
                                     Float(entity.position.y),
                                     Float(entity.position.z))

        if resolved.isAnonymousTease {
            // A faint shimmer: something is there, but not what. No marker —
            // labelling the mystery would spoil it.
            let wisp = ModelEntity(mesh: .generateSphere(radius: 0.35),
                                   materials: [haloMaterial(UIColor(white: 0.75, alpha: 1), opacity: 0.18)])
            wisp.position.y = 0.8
            root.addChild(wisp)
            return root
        }

        let spec = entity.visual ?? VisualSpec(shape: "sphere", colorHex: "#FFD24A")
        let tint = highContrast ? color(hex: "#FFE000") : color(hex: spec.colorHex)
        let scale = Float(spec.scale)
        let body: RealityKit.Entity
        let topY: Float
        if entity.id == StoryConventions.companionPlaceholder {
            body = VoxelWorld.critter(species: companion.species, tint: tint)
            topY = 1.8 // clears the tallest critter (bunny ears, ×1.3)
        } else if !highContrast, let model = loadArtModel(spec: spec) {
            // Commissioned/generated USDZ art slots in over the procedural
            // silhouette — same graceful-degradation contract as audio: any
            // missing or unloadable asset falls back to the shape below.
            // High contrast always uses procedural shapes; forced-yellow
            // silhouettes are that mode's accessibility contract.
            body = model.entity
            topY = model.topY
        } else {
            let built = shape(spec.shape, tint: tint, scale: scale,
                              highContrast: highContrast)
            body = built.entity
            topY = built.topY
        }
        body.name = "body"
        root.addChild(body)
        root.addChild(blobShadow(radius: 0.7 * scale))

        let glow = Float(spec.glow * glowBoost)
        if glow > 0.1 {
            let haloTint = highContrast ? UIColor.white : tint
            let halo = ModelEntity(mesh: .generateSphere(radius: 0.9 * scale),
                                   materials: [haloMaterial(haloTint, opacity: min(0.3, 0.12 * glow))])
            halo.position.y = body.position.y
            halo.scale = SIMD3<Float>(repeating: 0.9 + 0.35 * glow)
            halo.name = "halo"
            root.addChild(halo)
        }

        // Both chip looks are built up front; WorldView's tick toggles them
        // by the CURRENT quest target so the gold chip stays correct even
        // when the target changes without a world rebuild.
        let marker = RealityKit.Entity()
        marker.name = "marker"
        marker.position.y = topY + 1.1
        let chip = MarkerBuilder.marker(kind: entity.kind, isQuestTarget: false,
                                        highContrast: highContrast)
        chip.name = "chip"
        chip.isEnabled = !isQuestTarget
        let questChip = MarkerBuilder.marker(kind: entity.kind, isQuestTarget: true,
                                             highContrast: highContrast)
        questChip.name = "chipQuest"
        questChip.isEnabled = isQuestTarget
        marker.addChild(chip)
        marker.addChild(questChip)
        root.addChild(marker)
        return root
    }

    /// Loads a real 3D model for entities whose content names one
    /// (`VisualSpec.assetName`): a USDZ in `Assets/Art/Models/`, authored to
    /// the conventions in `Docs/ArtPipeline.md` (1 unit = 1 m, pivot at
    /// ground-center). Returns nil on any failure so the caller falls back
    /// to the procedural silhouette — the shape key stays the semantic
    /// identity, the asset is only ever an upgrade.
    private static func loadArtModel(spec: VisualSpec) -> (entity: ModelEntity, topY: Float)? {
        guard let assetName = spec.assetName,
              let url = Bundle.main.url(forResource: assetName, withExtension: "usdz",
                                        subdirectory: "Assets/Art/Models")
                  ?? Bundle.main.url(forResource: assetName, withExtension: "usdz"),
              let model = try? ModelEntity.loadModel(contentsOf: url) else { return nil }
        model.scale = SIMD3<Float>(repeating: Float(spec.scale))
        let topY = model.visualBounds(relativeTo: nil).max.y
        // A marker glued to the ground reads as a bug; keep it clear of even
        // squat or mis-pivoted models.
        return (model, max(topY, 0.5))
    }

    /// The procedural silhouette library. Returns the body entity plus the
    /// height of its highest point (root-local), where the icon marker
    /// floats. Every silhouette must read at a glance — a door looks
    /// enterable, a character has a face — because her eyes get one chance
    /// before her ears take over. High contrast forces everything to one
    /// loud yellow so recognition rests on shape + marker alone.
    private static func shape(_ kind: String, tint: UIColor, scale: Float,
                              highContrast: Bool) -> (entity: ModelEntity, topY: Float) {
        let bodyEmissive: Float = highContrast ? 3.5 : 3.0
        let material = glowMaterial(tint, emissive: bodyEmissive)
        // Accent parts (canopy greens, dim panels) flatten to the forced
        // yellow in high contrast — one hue, zero ambiguity.
        func accent(_ color: UIColor, emissive: Float) -> PhysicallyBasedMaterial {
            highContrast ? glowMaterial(tint, emissive: bodyEmissive)
                         : glowMaterial(color, emissive: emissive)
        }
        // Eyes stay dark in every mode: a face needs its darkest feature.
        let eyeMaterial = glowMaterial(UIColor(white: 0.07, alpha: 1), emissive: 0.05)

        switch kind {
        case "tree":
            // The story oak: angled branches and a stepped three-tier crown,
            // deliberately unlike the box-on-box scatter trees so "the old
            // oak" is findable among ordinary forest.
            let trunk = ModelEntity(mesh: .generateBox(width: 0.5 * scale, height: 2.4 * scale, depth: 0.5 * scale),
                                    materials: [accent(tint, emissive: 1.8)])
            trunk.position.y = 1.2 * scale
            for index in 0..<3 {
                let yaw = Float(index) * (2 * .pi / 3) + 0.5
                let branch = ModelEntity(
                    mesh: .generateBox(width: 0.2 * scale, height: 1.4 * scale, depth: 0.2 * scale),
                    materials: [accent(tint, emissive: 1.8)])
                branch.position = SIMD3<Float>(sin(yaw) * 0.55 * scale, 1.0 * scale,
                                               cos(yaw) * 0.55 * scale)
                branch.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
                    * simd_quatf(angle: -0.65, axis: SIMD3<Float>(0, 0, 1))
                trunk.addChild(branch)
            }
            let tiers: [(width: Float, height: Float, y: Float, color: UIColor, emissive: Float)] = [
                (2.6, 0.9, 1.6, UIColor(red: 0.38, green: 0.78, blue: 0.40, alpha: 1), 1.6),
                (2.0, 0.8, 2.35, UIColor(red: 0.45, green: 0.85, blue: 0.45, alpha: 1), 1.8),
                (1.2, 0.7, 3.0, UIColor(red: 0.55, green: 0.92, blue: 0.50, alpha: 1), 2.0),
            ]
            for tier in tiers {
                let canopy = ModelEntity(
                    mesh: .generateBox(width: tier.width * scale, height: tier.height * scale,
                                       depth: tier.width * scale, cornerRadius: 0.08),
                    materials: [accent(tier.color, emissive: tier.emissive)])
                canopy.position.y = tier.y * scale
                trunk.addChild(canopy)
            }
            return (trunk, 4.55 * scale)
        case "door":
            // A real door, not a slab: bright jambs framing a recessed dim
            // panel with a glowing knob. The filled panel is what separates
            // "closed thing you open" from the arch's empty walk-through.
            let panel = ModelEntity(
                mesh: .generateBox(width: 1.0 * scale, height: 1.9 * scale, depth: 0.12 * scale, cornerRadius: 0.04),
                materials: [accent(tint, emissive: 1.0)])
            panel.position = SIMD3<Float>(0, 0.95 * scale, -0.06 * scale)
            for side: Float in [-0.62, 0.62] {
                let jamb = ModelEntity(
                    mesh: .generateBox(width: 0.22 * scale, height: 2.2 * scale, depth: 0.3 * scale),
                    materials: [material])
                jamb.position = SIMD3<Float>(side * scale, 0.15 * scale, 0.06 * scale)
                panel.addChild(jamb)
            }
            let lintel = ModelEntity(
                mesh: .generateBox(width: 1.7 * scale, height: 0.3 * scale, depth: 0.3 * scale),
                materials: [material])
            lintel.position = SIMD3<Float>(0, 1.4 * scale, 0.06 * scale)
            panel.addChild(lintel)
            let knob = ModelEntity(
                mesh: .generateBox(width: 0.12 * scale, height: 0.12 * scale, depth: 0.12 * scale, cornerRadius: 0.04),
                materials: [glowMaterial(UIColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 1), emissive: 4.0)])
            knob.position = SIMD3<Float>(0.32 * scale, 0.05 * scale, 0.16 * scale)
            panel.addChild(knob)
            return (panel, 2.55 * scale)
        case "arch":
            let left = ModelEntity(mesh: .generateBox(width: 0.3 * scale, height: 1.4 * scale, depth: 0.3 * scale),
                                   materials: [material])
            left.position = SIMD3<Float>(-0.7 * scale, 0.7 * scale, 0)
            let right = ModelEntity(mesh: .generateBox(width: 0.3 * scale, height: 1.4 * scale, depth: 0.3 * scale),
                                    materials: [material])
            right.position = SIMD3<Float>(0.7 * scale, 0.7 * scale, 0)
            let top = ModelEntity(mesh: .generateBox(width: 1.8 * scale, height: 0.3 * scale, depth: 0.3 * scale),
                                  materials: [material])
            top.position.y = 1.45 * scale
            left.addChild(right)
            left.addChild(top)
            return (left, 1.6 * scale)
        case "character":
            // A person-shape with a face. The two dark eyes are the single
            // biggest "someone to talk to" cue for low vision.
            let body = ModelEntity(
                mesh: .generateBox(width: 0.6 * scale, height: 0.8 * scale, depth: 0.35 * scale, cornerRadius: 0.05),
                materials: [material])
            body.position.y = 0.6 * scale
            let head = ModelEntity(
                mesh: .generateBox(width: 0.46 * scale, height: 0.45 * scale, depth: 0.46 * scale, cornerRadius: 0.05),
                materials: [material])
            head.position.y = 0.65 * scale
            body.addChild(head)
            for side: Float in [-0.10, 0.10] {
                let eye = ModelEntity(
                    mesh: .generateBox(width: 0.09 * scale, height: 0.09 * scale, depth: 0.05 * scale),
                    materials: [eyeMaterial])
                eye.position = SIMD3<Float>(side * scale, 0.70 * scale, -0.26 * scale)
                body.addChild(eye)
            }
            for side: Float in [-0.38, 0.38] {
                let arm = ModelEntity(
                    mesh: .generateBox(width: 0.16 * scale, height: 0.5 * scale, depth: 0.16 * scale, cornerRadius: 0.04),
                    materials: [material])
                arm.position = SIMD3<Float>(side * scale, 0.05 * scale, 0)
                body.addChild(arm)
            }
            return (body, 1.5 * scale)
        case "chest":
            // Treasure box: base, slightly proud lid, and a bright clasp —
            // the universal "open me" silhouette.
            let base = ModelEntity(
                mesh: .generateBox(width: 1.1 * scale, height: 0.6 * scale, depth: 0.75 * scale, cornerRadius: 0.05),
                materials: [material])
            base.position.y = 0.3 * scale
            let lid = ModelEntity(
                mesh: .generateBox(width: 1.18 * scale, height: 0.35 * scale, depth: 0.82 * scale, cornerRadius: 0.1),
                materials: [accent(tint, emissive: 1.6)])
            lid.position.y = 0.45 * scale
            base.addChild(lid)
            let clasp = ModelEntity(
                mesh: .generateBox(width: 0.16 * scale, height: 0.22 * scale, depth: 0.08 * scale, cornerRadius: 0.03),
                materials: [glowMaterial(UIColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 1), emissive: 4.0)])
            clasp.position = SIMD3<Float>(0, 0.18 * scale, -0.40 * scale)
            base.addChild(clasp)
            return (base, 0.85 * scale)
        case "ribbon":
            let ribbon = ModelEntity(mesh: .generateBox(width: 2.2 * scale, height: 0.06, depth: 7.0 * scale, cornerRadius: 0.03),
                                     materials: [accent(tint, emissive: 1.4)])
            ribbon.position.y = 0.03
            return (ribbon, 0.2 * scale)
        case "mound":
            let mound = ModelEntity(
                mesh: .generateBox(width: 1.4 * scale, height: 0.6 * scale, depth: 1.4 * scale, cornerRadius: 0.1),
                materials: [material])
            mound.position.y = 0.3 * scale
            return (mound, 0.6 * scale)
        case "nest":
            let nest = ModelEntity(
                mesh: .generateBox(width: 0.9 * scale, height: 0.45 * scale, depth: 0.9 * scale, cornerRadius: 0.12),
                materials: [material])
            return (nest, 0.3 * scale)
        default: // "sphere" and anything unknown: a chunky floating cube,
                 // spun slowly by the world view — the classic pickup look.
            let cube = ModelEntity(
                mesh: .generateBox(width: 0.9 * scale, height: 0.9 * scale, depth: 0.9 * scale, cornerRadius: 0.06),
                materials: [material])
            cube.position.y = 0.8 * scale
            return (cube, 1.3 * scale)
        }
    }

    static func firefly() -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: 0.05),
                    materials: [glowMaterial(UIColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 1), emissive: 4.0)])
    }

    /// Soft dark disc that grounds an object on the floor — without shadows,
    /// everything reads as floating.
    static func blobShadow(radius: Float) -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .black)
        material.roughness = 1.0
        // Dimmer than it once was: the directional light casts real shadows
        // now, and blob + cast shadow at full strength double-darkened.
        material.blending = .transparent(opacity: .init(floatLiteral: 0.35))
        let shadow = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
        shadow.scale = SIMD3<Float>(1.0, 0.04, 1.0)
        shadow.position.y = 0.03
        return shadow
    }

    /// Tall translucent pillar of light over the quest target — readable from
    /// anywhere in the scene, the classic "go here" cue.
    static func questBeacon() -> ModelEntity {
        let pillar = ModelEntity(
            mesh: .generateBox(width: 0.4, height: 14, depth: 0.4, cornerRadius: 0.2),
            materials: [haloMaterial(UIColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 1), opacity: 0.3)])
        pillar.position.y = 7
        return pillar
    }
}
