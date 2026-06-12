import Foundation
import RealityKit
import StoryEngine
import UIKit

/// Deterministic xorshift RNG seeded from a string, so every scene's world
/// is identical on every launch and every device — a place, not a shuffle.
struct SeededRandom {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        state = hash == 0 ? 0x9E3779B97F4A7C15 : hash
    }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }

    mutating func range(_ bounds: ClosedRange<Double>) -> Double {
        bounds.lowerBound + next() * (bounds.upperBound - bounds.lowerBound)
    }

    mutating func chance(_ probability: Double) -> Bool {
        next() < probability
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[min(Int(next() * Double(items.count)), items.count - 1)]
    }
}

/// Chunky Lego/Minecraft-style biomes: a tiled blocky ground that stays
/// flat across the playable area and rises into block-stepped hills (or
/// walls, or crystal fields) around its edge, plus biome scatter. All
/// deterministic from the scene id.
enum VoxelWorld {
    struct Biome {
        let skyColor: UIColor
        let baseColor: UIColor
        /// Ground tile palette, varied per-tile like Minecraft grass.
        let groundColors: [UIColor]
        let hillColor: UIColor
        let groundEmissive: Float
        let lightIntensity: Float
    }

    static func biome(for environment: String?) -> Biome {
        switch environment {
        case "cave":
            return Biome(
                skyColor: UIColor(red: 0.015, green: 0.015, blue: 0.045, alpha: 1),
                baseColor: UIColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 1),
                groundColors: [
                    UIColor(red: 0.16, green: 0.17, blue: 0.24, alpha: 1),
                    UIColor(red: 0.13, green: 0.14, blue: 0.21, alpha: 1),
                    UIColor(red: 0.19, green: 0.18, blue: 0.28, alpha: 1),
                ],
                hillColor: UIColor(red: 0.10, green: 0.11, blue: 0.18, alpha: 1),
                groundEmissive: 0.35,
                lightIntensity: 700)
        case "castle":
            return Biome(
                skyColor: UIColor(red: 0.09, green: 0.05, blue: 0.14, alpha: 1),
                baseColor: UIColor(red: 0.11, green: 0.09, blue: 0.13, alpha: 1),
                groundColors: [
                    UIColor(red: 0.38, green: 0.34, blue: 0.32, alpha: 1),
                    UIColor(red: 0.33, green: 0.30, blue: 0.29, alpha: 1),
                    UIColor(red: 0.42, green: 0.37, blue: 0.33, alpha: 1),
                ],
                hillColor: UIColor(red: 0.26, green: 0.23, blue: 0.24, alpha: 1),
                groundEmissive: 0.45,
                lightIntensity: 1400)
        default: // forest
            return Biome(
                skyColor: UIColor(red: 0.03, green: 0.04, blue: 0.11, alpha: 1),
                baseColor: UIColor(red: 0.04, green: 0.08, blue: 0.06, alpha: 1),
                groundColors: [
                    UIColor(red: 0.18, green: 0.42, blue: 0.22, alpha: 1),
                    UIColor(red: 0.15, green: 0.36, blue: 0.19, alpha: 1),
                    UIColor(red: 0.21, green: 0.46, blue: 0.24, alpha: 1),
                ],
                hillColor: UIColor(red: 0.12, green: 0.26, blue: 0.16, alpha: 1),
                groundEmissive: 0.55,
                lightIntensity: 1200)
        }
    }

    private static func solid(_ color: UIColor, emissive: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = emissive
        material.roughness = 1.0
        material.metallic = 0.0
        return material
    }

    // MARK: - Terrain

    private static let tileGrid = 3.0   // meters per tile
    private static let tileSpan = 13    // tiles each direction → ±39 m
    private static let flatRadius = 25.0
    private static let stepHeight = 0.7

    /// The whole biome floor: a dark base plane, chunky tiles with a slight
    /// gap (the "Lego baseplate" grid), block-stepped hills ringing the
    /// playable flat, and biome scatter.
    static func terrain(environment: String?, seedKey: String) -> RealityKit.Entity {
        let biome = biome(for: environment)
        let root = RealityKit.Entity()
        var rng = SeededRandom(seed: seedKey)

        let base = ModelEntity(mesh: .generatePlane(width: 130, depth: 130),
                               materials: [solid(biome.baseColor, emissive: 0.2)])
        base.position.y = -0.06
        root.addChild(base)

        for xi in -tileSpan...tileSpan {
            for zi in -tileSpan...tileSpan {
                let x = Double(xi) * tileGrid
                let z = Double(zi) * tileGrid
                let height = tileHeight(x: x, z: z)
                let raised = height > 0.01
                var color = raised ? biome.hillColor : rng.pick(biome.groundColors)
                if raised, rng.chance(0.3) {
                    color = rng.pick(biome.groundColors)
                }
                let boxHeight = Float(1.0 + height)
                let tile = ModelEntity(
                    mesh: .generateBox(width: Float(tileGrid) - 0.12,
                                       height: boxHeight,
                                       depth: Float(tileGrid) - 0.12,
                                       cornerRadius: 0.05),
                    materials: [solid(color, emissive: biome.groundEmissive)])
                tile.position = SIMD3<Float>(Float(x), Float(height) - boxHeight / 2, Float(z))
                root.addChild(tile)
            }
        }

        switch environment {
        case "cave":
            scatterCave(into: root, rng: &rng)
        case "castle":
            buildCastleWalls(into: root)
        default:
            scatterForest(into: root, rng: &rng)
        }
        return root
    }

    /// Flat across the playable area, rising in quantized block steps beyond.
    private static func tileHeight(x: Double, z: Double) -> Double {
        let distance = (x * x + z * z).squareRoot()
        guard distance > flatRadius else { return 0 }
        let rise = min(1.0, (distance - flatRadius) / 12.0)
        let noise = (sin(x * 0.55) + cos(z * 0.47) + sin((x + z) * 0.31) + 3.0) / 6.0
        let steps = (noise * 4.0 * rise).rounded(.down)
        return steps * stepHeight
    }

    /// A deterministic ring position outside the story entities' area.
    private static func ringSpot(_ rng: inout SeededRandom) -> SIMD3<Float> {
        let angle = rng.range(0...(2 * .pi))
        let radius = rng.range(20...36)
        let x = Float(cos(angle) * radius)
        let z = Float(sin(angle) * radius)
        return SIMD3<Float>(x, Float(tileHeight(x: Double(x), z: Double(z))), z)
    }

    private static func scatterForest(into root: RealityKit.Entity, rng: inout SeededRandom) {
        let leafGreens = [
            UIColor(red: 0.30, green: 0.62, blue: 0.30, alpha: 1),
            UIColor(red: 0.24, green: 0.55, blue: 0.27, alpha: 1),
            UIColor(red: 0.42, green: 0.68, blue: 0.30, alpha: 1),
        ]
        let trunkBrown = UIColor(red: 0.36, green: 0.25, blue: 0.16, alpha: 1)
        for _ in 0..<22 {
            let spot = ringSpot(&rng)
            let height = Float(rng.range(1.6...2.6))
            let tree = RealityKit.Entity()
            let trunk = ModelEntity(mesh: .generateBox(width: 0.5, height: height, depth: 0.5),
                                    materials: [solid(trunkBrown, emissive: 0.4)])
            trunk.position.y = height / 2
            let leaves = ModelEntity(
                mesh: .generateBox(width: 2.4, height: 2.0, depth: 2.4, cornerRadius: 0.1),
                materials: [solid(rng.pick(leafGreens), emissive: 0.7)])
            leaves.position.y = height + 0.9
            let cap = ModelEntity(mesh: .generateBox(width: 1.3, height: 0.9, depth: 1.3),
                                  materials: [solid(rng.pick(leafGreens), emissive: 0.8)])
            cap.position.y = height + 2.3
            tree.addChild(trunk)
            tree.addChild(leaves)
            tree.addChild(cap)
            tree.position = spot
            root.addChild(tree)
        }
        // Tiny glowing flowers sprinkled inside the playable meadow.
        let petalColors = [UIColor.systemPink, UIColor.systemYellow, UIColor.systemTeal]
        for _ in 0..<26 {
            let angle = rng.range(0...(2 * .pi))
            let radius = rng.range(5...22)
            let flower = ModelEntity(mesh: .generateBox(width: 0.16, height: 0.3, depth: 0.16),
                                     materials: [solid(rng.pick(petalColors), emissive: 1.6)])
            flower.position = SIMD3<Float>(Float(cos(angle) * radius), 0.15, Float(sin(angle) * radius))
            root.addChild(flower)
        }
    }

    private static func scatterCave(into root: RealityKit.Entity, rng: inout SeededRandom) {
        let stone = UIColor(red: 0.22, green: 0.23, blue: 0.33, alpha: 1)
        let crystalColors = [
            UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1),
            UIColor(red: 0.75, green: 0.60, blue: 1.0, alpha: 1),
            UIColor(red: 0.50, green: 1.0, blue: 0.90, alpha: 1),
        ]
        for _ in 0..<14 {
            let spot = ringSpot(&rng)
            let stalagmite = RealityKit.Entity()
            var y: Float = 0
            for layer in 0..<3 {
                let side = Float(1.5 - Double(layer) * 0.45) * Float(rng.range(0.7...1.1))
                let block = ModelEntity(mesh: .generateBox(width: side, height: 1.0, depth: side),
                                        materials: [solid(stone, emissive: 0.35)])
                block.position.y = y + 0.5
                stalagmite.addChild(block)
                y += 1.0
            }
            stalagmite.position = spot
            root.addChild(stalagmite)
        }
        for _ in 0..<16 {
            let spot = ringSpot(&rng)
            let crystal = ModelEntity(
                mesh: .generateBox(width: 0.5, height: Float(rng.range(1.0...2.4)), depth: 0.5),
                materials: [solid(rng.pick(crystalColors), emissive: 2.2)])
            crystal.position = spot + SIMD3<Float>(0, 0.6, 0)
            crystal.orientation = simd_quatf(angle: Float(rng.range(-0.4...0.4)),
                                             axis: SIMD3<Float>(1, 0, 1))
            root.addChild(crystal)
        }
    }

    private static func buildCastleWalls(into root: RealityKit.Entity) {
        let stone = UIColor(red: 0.45, green: 0.41, blue: 0.40, alpha: 1)
        let wallMaterial = solid(stone, emissive: 0.5)
        let span: Float = 29
        let segments: [(position: SIMD3<Float>, size: SIMD3<Float>)] = [
            (SIMD3<Float>(0, 1.6, -span), SIMD3<Float>(span * 2, 3.2, 1.2)),
            (SIMD3<Float>(0, 1.6, span), SIMD3<Float>(span * 2, 3.2, 1.2)),
            (SIMD3<Float>(-span, 1.6, 0), SIMD3<Float>(1.2, 3.2, span * 2)),
            (SIMD3<Float>(span, 1.6, 0), SIMD3<Float>(1.2, 3.2, span * 2)),
        ]
        for segment in segments {
            let wall = ModelEntity(
                mesh: .generateBox(width: segment.size.x, height: segment.size.y, depth: segment.size.z),
                materials: [wallMaterial])
            wall.position = segment.position
            root.addChild(wall)
        }
        // Crenellations along the walls and chunky corner towers.
        for offset in stride(from: -24.0, through: 24.0, by: 8.0) {
            for (x, z) in [(Float(offset), -span), (Float(offset), span),
                           (-span, Float(offset)), (span, Float(offset))] {
                let merlon = ModelEntity(mesh: .generateBox(width: 1.4, height: 1.1, depth: 1.4),
                                         materials: [wallMaterial])
                merlon.position = SIMD3<Float>(x, 3.7, z)
                root.addChild(merlon)
            }
        }
        for (x, z) in [(-span, -span), (-span, span), (span, -span), (span, span)] {
            let tower = ModelEntity(mesh: .generateBox(width: 4, height: 7, depth: 4),
                                    materials: [wallMaterial])
            tower.position = SIMD3<Float>(x, 3.5, z)
            let cap = ModelEntity(mesh: .generateBox(width: 5, height: 1.2, depth: 5),
                                  materials: [wallMaterial])
            cap.position = SIMD3<Float>(x, 7.4, z)
            root.addChild(tower)
            root.addChild(cap)
        }
    }

    // MARK: - Voxel characters

    private static func block(_ width: Float, _ height: Float, _ depth: Float,
                              _ color: UIColor, emissive: Float = 0.9) -> ModelEntity {
        ModelEntity(mesh: .generateBox(width: width, height: height, depth: depth, cornerRadius: 0.03),
                    materials: [solid(color, emissive: emissive)])
    }

    /// Her blocky adventurer: little boots, a warm tunic, a bright face, and
    /// a tiny lantern on her belt — readable from the third-person camera.
    static func playerAvatar() -> RealityKit.Entity {
        let root = RealityKit.Entity()
        let tunic = UIColor(red: 0.85, green: 0.32, blue: 0.25, alpha: 1)
        let skin = UIColor(red: 0.98, green: 0.86, blue: 0.70, alpha: 1)
        let boots = UIColor(red: 0.30, green: 0.22, blue: 0.16, alpha: 1)

        for side: Float in [-0.14, 0.14] {
            let leg = block(0.18, 0.34, 0.2, boots)
            leg.position = SIMD3<Float>(side, 0.17, 0)
            root.addChild(leg)
        }
        let body = block(0.52, 0.6, 0.32, tunic)
        body.position.y = 0.64
        root.addChild(body)
        let head = block(0.42, 0.4, 0.4, skin, emissive: 1.1)
        head.position.y = 1.16
        root.addChild(head)
        let lantern = block(0.14, 0.18, 0.14, UIColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 1),
                            emissive: 3.0)
        lantern.position = SIMD3<Float>(0.32, 0.62, 0.12)
        root.addChild(lantern)
        root.addChild(WorldBuilder.blobShadow(radius: 0.5))
        return root
    }

    /// A companion as a chunky voxel critter, by species.
    static func critter(species: String, tint: UIColor) -> RealityKit.Entity {
        let root = RealityKit.Entity()
        let white = UIColor(red: 0.98, green: 0.95, blue: 0.9, alpha: 1)
        switch species.lowercased() {
        case "fox":
            let body = block(0.5, 0.42, 0.85, tint)
            body.position.y = 0.45
            let head = block(0.42, 0.38, 0.4, tint)
            head.position = SIMD3<Float>(0, 0.78, -0.5)
            let snout = block(0.18, 0.14, 0.18, white)
            snout.position = SIMD3<Float>(0, 0.70, -0.74)
            for side: Float in [-0.13, 0.13] {
                let ear = block(0.12, 0.24, 0.06, tint)
                ear.position = SIMD3<Float>(side, 1.04, -0.5)
                root.addChild(ear)
            }
            let tail = block(0.2, 0.2, 0.5, tint)
            tail.position = SIMD3<Float>(0, 0.55, 0.6)
            let tip = block(0.16, 0.16, 0.16, white)
            tip.position = SIMD3<Float>(0, 0.55, 0.88)
            root.addChild(body); root.addChild(head); root.addChild(snout)
            root.addChild(tail); root.addChild(tip)
        case "bunny", "rabbit":
            let body = block(0.46, 0.42, 0.6, tint)
            body.position.y = 0.4
            let head = block(0.38, 0.34, 0.34, tint)
            head.position = SIMD3<Float>(0, 0.74, -0.32)
            for side: Float in [-0.11, 0.11] {
                let ear = block(0.1, 0.48, 0.08, tint)
                ear.position = SIMD3<Float>(side, 1.12, -0.32)
                root.addChild(ear)
            }
            let puff = block(0.18, 0.18, 0.18, white)
            puff.position = SIMD3<Float>(0, 0.42, 0.36)
            root.addChild(body); root.addChild(head); root.addChild(puff)
        case "butterfly":
            let body = block(0.12, 0.4, 0.12, UIColor(red: 0.25, green: 0.2, blue: 0.3, alpha: 1))
            body.position.y = 0.9
            for side: Float in [-0.3, 0.3] {
                let wing = block(0.45, 0.5, 0.05, tint, emissive: 1.8)
                wing.position = SIMD3<Float>(side, 0.95, 0)
                wing.name = "wing"
                root.addChild(wing)
            }
            root.addChild(body)
        default:
            let body = block(0.5, 0.5, 0.5, tint, emissive: 1.6)
            body.position.y = 0.5
            root.addChild(body)
        }
        root.addChild(WorldBuilder.blobShadow(radius: 0.45))
        return root
    }
}
