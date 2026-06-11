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
        material.roughness = 0.9
        material.metallic = 0.0
        return material
    }

    static func haloMaterial(_ color: UIColor, opacity: Float) -> PhysicallyBasedMaterial {
        var material = glowMaterial(color, emissive: 1.5)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    static func ground() -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: 90, depth: 90)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.05, green: 0.09, blue: 0.07, alpha: 1))
        material.emissiveColor = .init(color: UIColor(red: 0.04, green: 0.10, blue: 0.07, alpha: 1))
        material.emissiveIntensity = 0.35
        material.roughness = 1.0
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = SIMD3<Float>(0, 0, 0)
        return entity
    }

    /// One world object: the bold shape plus a soft additive halo shell.
    /// The halo radius carries the calibrated/adaptive glow boost.
    static func build(_ resolved: ResolvedEntity, companionName: String,
                      glowBoost: Double) -> Entity {
        let root = Entity()
        let entity = resolved.entity
        root.position = SIMD3<Float>(Float(entity.position.x),
                                     Float(entity.position.y),
                                     Float(entity.position.z))

        if resolved.isAnonymousTease {
            // A faint shimmer: something is there, but not what.
            let wisp = ModelEntity(mesh: .generateSphere(radius: 0.35),
                                   materials: [haloMaterial(UIColor(white: 0.75, alpha: 1), opacity: 0.18)])
            wisp.position.y = 0.8
            root.addChild(wisp)
            return root
        }

        let spec = entity.visual ?? VisualSpec(shape: "sphere", colorHex: "#FFD24A")
        let tint = color(hex: spec.colorHex)
        let scale = Float(spec.scale)
        let body = shape(spec.shape, tint: tint, scale: scale)
        root.addChild(body)

        let glow = Float(spec.glow * glowBoost)
        if glow > 0.1 {
            let halo = ModelEntity(mesh: .generateSphere(radius: 0.9 * scale),
                                   materials: [haloMaterial(tint, opacity: min(0.3, 0.12 * glow))])
            halo.position.y = body.position.y
            halo.scale = SIMD3<Float>(repeating: 0.9 + 0.35 * glow)
            halo.name = "halo"
            root.addChild(halo)
        }
        return root
    }

    private static func shape(_ kind: String, tint: UIColor, scale: Float) -> ModelEntity {
        let material = glowMaterial(tint, emissive: 2.0)
        switch kind {
        case "tree":
            let trunk = ModelEntity(mesh: .generateBox(width: 0.35 * scale, height: 2.2 * scale, depth: 0.35 * scale),
                                    materials: [glowMaterial(tint, emissive: 1.2)])
            trunk.position.y = 1.1 * scale
            let canopy = ModelEntity(mesh: .generateSphere(radius: 1.1 * scale),
                                     materials: [glowMaterial(UIColor(red: 0.45, green: 0.85, blue: 0.45, alpha: 1), emissive: 1.6)])
            canopy.position.y = 2.6 * scale
            trunk.addChild(canopy)
            return trunk
        case "door":
            let door = ModelEntity(mesh: .generateBox(width: 1.1 * scale, height: 1.8 * scale, depth: 0.25 * scale, cornerRadius: 0.1),
                                   materials: [material])
            door.position.y = 0.9 * scale
            return door
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
            return left
        case "ribbon":
            let ribbon = ModelEntity(mesh: .generateBox(width: 2.2 * scale, height: 0.06, depth: 7.0 * scale, cornerRadius: 0.03),
                                     materials: [glowMaterial(tint, emissive: 1.4)])
            ribbon.position.y = 0.03
            return ribbon
        case "mound":
            let mound = ModelEntity(mesh: .generateSphere(radius: 0.8 * scale), materials: [material])
            mound.scale = SIMD3<Float>(1.0, 0.45, 1.0)
            mound.position.y = 0.2 * scale
            return mound
        case "nest":
            let nest = ModelEntity(mesh: .generateSphere(radius: 0.5 * scale), materials: [material])
            nest.scale = SIMD3<Float>(1.0, 0.55, 1.0)
            return nest
        default: // "sphere" and anything unknown
            let orb = ModelEntity(mesh: .generateSphere(radius: 0.6 * scale), materials: [material])
            orb.position.y = 0.8 * scale
            return orb
        }
    }

    static func firefly() -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: 0.05),
                    materials: [glowMaterial(UIColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 1), emissive: 4.0)])
    }
}
