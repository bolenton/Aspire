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
        /// Sky-dome gradient: zenith fading to a horizon band. The flat
        /// `skyColor` stays set behind the dome as the fallback and is all
        /// high contrast ever shows (that mode gets no dome at all).
        let skyTop: UIColor
        let skyHorizon: UIColor
        let baseColor: UIColor
        /// Ground tile palette, varied per-tile like Minecraft grass.
        let groundColors: [UIColor]
        let hillColor: UIColor
        /// Deliberately dim: the floor must sit well below interactable glow
        /// so the things she can touch own the bright end of the range.
        let groundEmissive: Float
        let lightIntensity: Float
    }

    static func biome(for environment: String?, highContrast: Bool = false) -> Biome {
        if highContrast {
            // Near-black everywhere: in this mode recognition comes entirely
            // from the forced-yellow interactables and white markers, so the
            // world itself must not compete for her eyes at all.
            return Biome(
                skyColor: UIColor(white: 0.0, alpha: 1),
                skyTop: UIColor(white: 0.0, alpha: 1),
                skyHorizon: UIColor(white: 0.0, alpha: 1),
                baseColor: UIColor(white: 0.03, alpha: 1),
                groundColors: [
                    UIColor(white: 0.055, alpha: 1),
                    UIColor(white: 0.06, alpha: 1),
                    UIColor(white: 0.07, alpha: 1),
                ],
                hillColor: UIColor(white: 0.10, alpha: 1),
                groundEmissive: 0.05,
                lightIntensity: 900)
        }
        switch environment {
        case "cave":
            return Biome(
                skyColor: UIColor(red: 0.015, green: 0.015, blue: 0.045, alpha: 1),
                skyTop: UIColor(red: 0.004, green: 0.004, blue: 0.018, alpha: 1),
                skyHorizon: UIColor(red: 0.06, green: 0.03, blue: 0.12, alpha: 1),
                baseColor: UIColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 1),
                groundColors: [
                    UIColor(red: 0.16, green: 0.17, blue: 0.24, alpha: 1),
                    UIColor(red: 0.13, green: 0.14, blue: 0.21, alpha: 1),
                    UIColor(red: 0.19, green: 0.18, blue: 0.28, alpha: 1),
                ],
                hillColor: UIColor(red: 0.10, green: 0.11, blue: 0.18, alpha: 1),
                groundEmissive: 0.21,
                lightIntensity: 700)
        case "castle":
            return Biome(
                skyColor: UIColor(red: 0.09, green: 0.05, blue: 0.14, alpha: 1),
                skyTop: UIColor(red: 0.05, green: 0.02, blue: 0.10, alpha: 1),
                skyHorizon: UIColor(red: 0.18, green: 0.10, blue: 0.15, alpha: 1),
                baseColor: UIColor(red: 0.11, green: 0.09, blue: 0.13, alpha: 1),
                groundColors: [
                    UIColor(red: 0.38, green: 0.34, blue: 0.32, alpha: 1),
                    UIColor(red: 0.33, green: 0.30, blue: 0.29, alpha: 1),
                    UIColor(red: 0.42, green: 0.37, blue: 0.33, alpha: 1),
                ],
                hillColor: UIColor(red: 0.26, green: 0.23, blue: 0.24, alpha: 1),
                groundEmissive: 0.27,
                lightIntensity: 1400)
        default: // forest
            return Biome(
                skyColor: UIColor(red: 0.03, green: 0.04, blue: 0.11, alpha: 1),
                skyTop: UIColor(red: 0.012, green: 0.018, blue: 0.07, alpha: 1),
                skyHorizon: UIColor(red: 0.06, green: 0.11, blue: 0.20, alpha: 1),
                baseColor: UIColor(red: 0.04, green: 0.08, blue: 0.06, alpha: 1),
                groundColors: [
                    UIColor(red: 0.18, green: 0.42, blue: 0.22, alpha: 1),
                    UIColor(red: 0.15, green: 0.36, blue: 0.19, alpha: 1),
                    UIColor(red: 0.21, green: 0.46, blue: 0.24, alpha: 1),
                ],
                hillColor: UIColor(red: 0.12, green: 0.26, blue: 0.16, alpha: 1),
                groundEmissive: 0.33,
                lightIntensity: 1200)
        }
    }

    /// An unlit inside-out sphere carrying the biome's vertical gradient —
    /// sky with depth instead of a flat color, far beyond the terrain (base
    /// plane corners reach ~92 m) yet inside the camera's far plane. Unlit
    /// keeps it out of the lighting and (being dim) out of the bloom, and the
    /// negative-X scale flips the winding so the inside faces render.
    /// Returns nil if the gradient texture can't be built — callers keep the
    /// flat background color, which is always set anyway.
    static func skyDome(biome: Biome) -> ModelEntity? {
        guard let cgImage = gradientImage(top: biome.skyTop, horizon: biome.skyHorizon).cgImage,
              let texture = try? TextureResource(image: cgImage,
                                                 options: .init(semantic: .color)) else {
            return nil
        }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        let dome = ModelEntity(mesh: .generateSphere(radius: 140), materials: [material])
        dome.scale = SIMD3<Float>(-1, 1, 1)
        return dome
    }

    /// Tall thin vertical gradient: zenith color at the top, easing into the
    /// horizon band above the equator, constant below it (terrain hides the
    /// lower half anyway). Equirectangular V maps straight onto this.
    private static func gradientImage(top: UIColor, horizon: UIColor) -> UIImage {
        let size = CGSize(width: 4, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [top.cgColor, horizon.cgColor, horizon.cgColor] as CFArray
            let locations: [CGFloat] = [0.0, 0.55, 1.0]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: locations) else {
                top.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                return
            }
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size.height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
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
    static func terrain(environment: String?, seedKey: String,
                        highContrast: Bool = false) -> RealityKit.Entity {
        let biome = biome(for: environment, highContrast: highContrast)
        let root = RealityKit.Entity()
        var rng = SeededRandom(seed: seedKey)

        let base = ModelEntity(mesh: .generatePlane(width: 130, depth: 130),
                               materials: [solid(biome.baseColor, emissive: 0.2)])
        base.position.y = -0.06
        root.addChild(base)

        // Tiles batch into one mesh per palette color: ~729 entities collapse
        // to at most four draw calls, the headroom this look runs on. The RNG
        // consumption below matches the historical per-tile loop EXACTLY
        // (same calls, same xi/zi order), so every world she already knows
        // keeps its exact colors.
        let palette = biome.groundColors + [biome.hillColor]
        let hillIndex = biome.groundColors.count
        let groundIndices = Array(biome.groundColors.indices)
        var buckets = Array(repeating: TileMesh(), count: palette.count)

        for xi in -tileSpan...tileSpan {
            for zi in -tileSpan...tileSpan {
                let x = Double(xi) * tileGrid
                let z = Double(zi) * tileGrid
                let height = tileHeight(x: x, z: z)
                let raised = height > 0.01
                var colorIndex = raised ? hillIndex : rng.pick(groundIndices)
                if raised, rng.chance(0.3) {
                    colorIndex = rng.pick(groundIndices)
                }
                let boxHeight = Float(1.0 + height)
                buckets[colorIndex].addBox(
                    center: SIMD3<Float>(Float(x), Float(height) - boxHeight / 2, Float(z)),
                    size: SIMD3<Float>(Float(tileGrid) - 0.12, boxHeight, Float(tileGrid) - 0.12))
            }
        }
        for (index, bucket) in buckets.enumerated() where !bucket.isEmpty {
            guard let mesh = bucket.meshResource() else { continue }
            let tiles = ModelEntity(mesh: mesh,
                                    materials: [solid(palette[index], emissive: biome.groundEmissive)])
            root.addChild(tiles)
        }

        switch environment {
        case "cave":
            scatterCave(into: root, rng: &rng, highContrast: highContrast)
        case "castle":
            buildCastleWalls(into: root, highContrast: highContrast)
        default:
            scatterForest(into: root, rng: &rng, highContrast: highContrast)
        }
        return root
    }

    /// Accumulates axis-aligned boxes — minus their never-visible bottom
    /// faces — into a single mesh, so the whole tiled floor renders as a
    /// handful of entities instead of hundreds.
    private struct TileMesh {
        private var positions: [SIMD3<Float>] = []
        private var normals: [SIMD3<Float>] = []
        private var indices: [UInt32] = []

        var isEmpty: Bool { positions.isEmpty }

        mutating func addBox(center: SIMD3<Float>, size: SIMD3<Float>) {
            let minP = center - size / 2
            let maxP = center + size / 2
            addQuad([SIMD3(minP.x, maxP.y, minP.z), SIMD3(minP.x, maxP.y, maxP.z),
                     SIMD3(maxP.x, maxP.y, maxP.z), SIMD3(maxP.x, maxP.y, minP.z)],
                    normal: SIMD3(0, 1, 0))
            addQuad([SIMD3(maxP.x, minP.y, maxP.z), SIMD3(maxP.x, minP.y, minP.z),
                     SIMD3(maxP.x, maxP.y, minP.z), SIMD3(maxP.x, maxP.y, maxP.z)],
                    normal: SIMD3(1, 0, 0))
            addQuad([SIMD3(minP.x, minP.y, minP.z), SIMD3(minP.x, minP.y, maxP.z),
                     SIMD3(minP.x, maxP.y, maxP.z), SIMD3(minP.x, maxP.y, minP.z)],
                    normal: SIMD3(-1, 0, 0))
            addQuad([SIMD3(minP.x, minP.y, maxP.z), SIMD3(maxP.x, minP.y, maxP.z),
                     SIMD3(maxP.x, maxP.y, maxP.z), SIMD3(minP.x, maxP.y, maxP.z)],
                    normal: SIMD3(0, 0, 1))
            addQuad([SIMD3(maxP.x, minP.y, minP.z), SIMD3(minP.x, minP.y, minP.z),
                     SIMD3(minP.x, maxP.y, minP.z), SIMD3(maxP.x, maxP.y, minP.z)],
                    normal: SIMD3(0, 0, -1))
        }

        private mutating func addQuad(_ corners: [SIMD3<Float>], normal: SIMD3<Float>) {
            let base = UInt32(positions.count)
            positions.append(contentsOf: corners)
            normals.append(contentsOf: [normal, normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }

        func meshResource() -> MeshResource? {
            var descriptor = MeshDescriptor(name: "tiles")
            descriptor.positions = MeshBuffer(positions)
            descriptor.normals = MeshBuffer(normals)
            descriptor.primitives = .triangles(indices)
            return try? MeshResource.generate(from: [descriptor])
        }
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

    /// Scenery material: in high-contrast mode every prop collapses to a
    /// faint gray silhouette — shape stays for orientation, but nothing
    /// competes with the yellow interactables for her eyes. Callers still
    /// draw colors from the RNG so world determinism is untouched.
    private static func scenery(_ color: UIColor, emissive: Float,
                                highContrast: Bool) -> PhysicallyBasedMaterial {
        highContrast ? solid(UIColor(white: 0.12, alpha: 1), emissive: 0.08)
                     : solid(color, emissive: emissive)
    }

    /// A deterministic ring position outside the story entities' area.
    private static func ringSpot(_ rng: inout SeededRandom) -> SIMD3<Float> {
        let angle = rng.range(0...(2 * .pi))
        let radius = rng.range(20...36)
        let x = Float(cos(angle) * radius)
        let z = Float(sin(angle) * radius)
        return SIMD3<Float>(x, Float(tileHeight(x: Double(x), z: Double(z))), z)
    }

    private static func scatterForest(into root: RealityKit.Entity, rng: inout SeededRandom,
                                      highContrast: Bool) {
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
                                    materials: [scenery(trunkBrown, emissive: 0.4, highContrast: highContrast)])
            trunk.position.y = height / 2
            let leaves = ModelEntity(
                mesh: .generateBox(width: 2.4, height: 2.0, depth: 2.4, cornerRadius: 0.1),
                materials: [scenery(rng.pick(leafGreens), emissive: 0.7, highContrast: highContrast)])
            leaves.position.y = height + 0.9
            let cap = ModelEntity(mesh: .generateBox(width: 1.3, height: 0.9, depth: 1.3),
                                  materials: [scenery(rng.pick(leafGreens), emissive: 0.8, highContrast: highContrast)])
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
                                     materials: [scenery(rng.pick(petalColors), emissive: 1.6, highContrast: highContrast)])
            flower.position = SIMD3<Float>(Float(cos(angle) * radius), 0.15, Float(sin(angle) * radius))
            root.addChild(flower)
        }
    }

    private static func scatterCave(into root: RealityKit.Entity, rng: inout SeededRandom,
                                    highContrast: Bool) {
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
                                        materials: [scenery(stone, emissive: 0.35, highContrast: highContrast)])
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
                materials: [scenery(rng.pick(crystalColors), emissive: 2.2, highContrast: highContrast)])
            crystal.position = spot + SIMD3<Float>(0, 0.6, 0)
            crystal.orientation = simd_quatf(angle: Float(rng.range(-0.4...0.4)),
                                             axis: SIMD3<Float>(1, 0, 1))
            root.addChild(crystal)
        }
    }

    private static func buildCastleWalls(into root: RealityKit.Entity, highContrast: Bool) {
        let stone = UIColor(red: 0.45, green: 0.41, blue: 0.40, alpha: 1)
        let wallMaterial = scenery(stone, emissive: 0.5, highContrast: highContrast)
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

    /// Her blocky adventurer, built from the hero she designed: her body,
    /// her skin, her hair, her outfit — plus the boots, the bright face with
    /// eyes, and the tiny lantern on the belt that make the figure readable
    /// from the third-person camera.
    static func playerAvatar(spec: AvatarSpec = AvatarSpec()) -> RealityKit.Entity {
        let root = RealityKit.Entity()
        let outfit = WorldBuilder.color(hex: AvatarPalette.outfitColor(id: spec.outfitColorID).hex)
        let skin = WorldBuilder.color(hex: AvatarPalette.skinTone(id: spec.skinToneID).hex)
        let hair = WorldBuilder.color(hex: AvatarPalette.hairColor(id: spec.hairColorID).hex)
        let boots = UIColor(red: 0.30, green: 0.22, blue: 0.16, alpha: 1)

        switch spec.body {
        case .boy:
            for side: Float in [-0.14, 0.14] {
                let leg = block(0.18, 0.34, 0.2, boots)
                leg.position = SIMD3<Float>(side, 0.17, 0)
                root.addChild(leg)
            }
        case .girl:
            // A flared skirt over short boots — the silhouette change that
            // reads at a glance from the camera distance.
            for side: Float in [-0.13, 0.13] {
                let leg = block(0.16, 0.2, 0.18, boots)
                leg.position = SIMD3<Float>(side, 0.1, 0)
                root.addChild(leg)
            }
            let skirt = block(0.64, 0.28, 0.42, outfit)
            skirt.position.y = 0.32
            root.addChild(skirt)
        }

        let body = block(0.52, 0.6, 0.32, outfit)
        body.position.y = 0.64
        root.addChild(body)

        let head = block(0.42, 0.4, 0.4, skin, emissive: 1.1)
        head.position.y = 1.16
        root.addChild(head)
        // A face: eyes are the single biggest "that's a person" cue.
        let eyeColor = UIColor(white: 0.07, alpha: 1)
        for side: Float in [-0.10, 0.10] {
            let eye = block(0.07, 0.08, 0.05, eyeColor, emissive: 0.05)
            eye.position = SIMD3<Float>(side, 1.20, -0.20)
            root.addChild(eye)
        }

        switch spec.hairStyle {
        case .short:
            let cap = block(0.44, 0.14, 0.42, hair)
            cap.position.y = 1.39
            root.addChild(cap)
        case .long:
            let cap = block(0.44, 0.14, 0.42, hair)
            cap.position.y = 1.39
            root.addChild(cap)
            let fall = block(0.44, 0.52, 0.12, hair)
            fall.position = SIMD3<Float>(0, 1.1, 0.22)
            root.addChild(fall)
        case .curly:
            let cloud = block(0.52, 0.24, 0.5, hair)
            cloud.position.y = 1.42
            root.addChild(cloud)
            for side: Float in [-0.26, 0.26] {
                let puff = block(0.14, 0.16, 0.3, hair)
                puff.position = SIMD3<Float>(side, 1.26, 0)
                root.addChild(puff)
            }
        case .braids:
            let cap = block(0.44, 0.14, 0.42, hair)
            cap.position.y = 1.39
            root.addChild(cap)
            for side: Float in [-0.25, 0.25] {
                let braid = block(0.1, 0.44, 0.1, hair)
                braid.position = SIMD3<Float>(side, 1.02, 0.1)
                root.addChild(braid)
            }
        case .bald:
            break
        }

        let lantern = block(0.14, 0.18, 0.14, UIColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 1),
                            emissive: 3.0)
        lantern.position = SIMD3<Float>(0.32, 0.62, 0.12)
        root.addChild(lantern)
        root.addChild(WorldBuilder.blobShadow(radius: 0.5))
        return root
    }

    /// A companion as a chunky voxel critter, by species. Slightly larger
    /// than life (×1.3) and given simple dark eyes — a face is the single
    /// biggest "that's a creature" cue for low vision.
    static func critter(species: String, tint: UIColor) -> RealityKit.Entity {
        let root = RealityKit.Entity()
        let white = UIColor(red: 0.98, green: 0.95, blue: 0.9, alpha: 1)
        let eyeColor = UIColor(white: 0.07, alpha: 1)
        func eye(_ x: Float, _ y: Float, _ z: Float) -> ModelEntity {
            let eye = block(0.08, 0.08, 0.06, eyeColor, emissive: 0.05)
            eye.position = SIMD3<Float>(x, y, z)
            return eye
        }
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
            for (sx, sz) in [(Float(-0.16), Float(-0.26)), (0.16, -0.26), (-0.16, 0.26), (0.16, 0.26)] {
                let leg = block(0.15, 0.3, 0.15, tint)
                leg.position = SIMD3<Float>(sx, 0.15, sz)
                root.addChild(leg)
            }
            let tail = block(0.2, 0.2, 0.5, tint)
            tail.position = SIMD3<Float>(0, 0.55, 0.6)
            let tip = block(0.16, 0.16, 0.16, white)
            tip.position = SIMD3<Float>(0, 0.55, 0.88)
            root.addChild(body); root.addChild(head); root.addChild(snout)
            root.addChild(tail); root.addChild(tip)
            root.addChild(eye(-0.10, 0.84, -0.71)); root.addChild(eye(0.10, 0.84, -0.71))
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
            let nose = block(0.09, 0.07, 0.05, UIColor.systemPink, emissive: 1.2)
            nose.position = SIMD3<Float>(0, 0.71, -0.50)
            root.addChild(body); root.addChild(head); root.addChild(puff); root.addChild(nose)
            root.addChild(eye(-0.09, 0.80, -0.50)); root.addChild(eye(0.09, 0.80, -0.50))
        case "butterfly":
            let body = block(0.12, 0.4, 0.12, UIColor(red: 0.25, green: 0.2, blue: 0.3, alpha: 1))
            body.position.y = 0.9
            for side: Float in [-0.3, 0.3] {
                let wing = block(0.45, 0.5, 0.05, tint, emissive: 1.8)
                wing.position = SIMD3<Float>(side, 0.95, 0)
                wing.name = "wing"
                // Two-tone panel: a pale inner patch so the wings read as
                // wings, not floating slabs. Child of the wing — it flaps too.
                let panel = block(0.26, 0.3, 0.07, white, emissive: 1.2)
                panel.position = SIMD3<Float>(side > 0 ? 0.06 : -0.06, 0, 0)
                wing.addChild(panel)
                root.addChild(wing)
            }
            root.addChild(body)
        default:
            let body = block(0.5, 0.5, 0.5, tint, emissive: 1.6)
            body.position.y = 0.5
            root.addChild(body)
            root.addChild(eye(-0.11, 0.58, -0.26)); root.addChild(eye(0.11, 0.58, -0.26))
        }
        root.scale = SIMD3<Float>(repeating: 1.3)
        root.addChild(WorldBuilder.blobShadow(radius: 0.45))
        return root
    }
}
