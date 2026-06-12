import RealityKit
import StoryEngine
import UIKit

/// Floating icon chips above interactables: an SF Symbol rendered into a
/// texture on an unlit plane. Unlit means the icon ignores scene lighting
/// entirely — maximum contrast for low vision, and it reads straight through
/// any later bloom pass. The chip says *what kind of thing* is there long
/// before she is close enough to resolve the silhouette; the gold variant
/// says "this one is the quest".
enum MarkerBuilder {
    /// One chip per look, shared across every entity that needs it — the
    /// texture render happens once per (symbol, palette) pair.
    private static var materialCache: [String: UnlitMaterial] = [:]
    private static let planeMesh = MeshResource.generatePlane(width: 0.9, height: 0.9,
                                                              cornerRadius: 0.16)

    static func marker(kind: EntityKind, isQuestTarget: Bool, highContrast: Bool) -> ModelEntity {
        ModelEntity(mesh: planeMesh,
                    materials: [material(symbol: symbolName(for: kind),
                                         isQuestTarget: isQuestTarget,
                                         highContrast: highContrast)])
    }

    private static func symbolName(for kind: EntityKind) -> String {
        switch kind {
        case .item: return "sparkles"
        case .companion, .character: return "bubble.left.fill"
        case .portal: return "arrow.right.circle.fill"
        case .landmark: return "star.fill"
        }
    }

    private static func material(symbol: String, isQuestTarget: Bool,
                                 highContrast: Bool) -> UnlitMaterial {
        let key = "\(symbol)|\(isQuestTarget)|\(highContrast)"
        if let cached = materialCache[key] { return cached }

        // Quest targets invert to the accent-gold chip so "go here" pops
        // against every regular marker; high contrast goes white-on-black.
        let chip: UIColor
        let ring: UIColor
        let glyph: UIColor
        switch (isQuestTarget, highContrast) {
        case (true, true):
            chip = .white; ring = .white; glyph = UIColor(white: 0.05, alpha: 1)
        case (true, false):
            chip = UIColor(red: 1.0, green: 0.82, blue: 0.29, alpha: 1)
            ring = .white; glyph = UIColor(white: 0.10, alpha: 1)
        case (false, true):
            chip = UIColor(white: 0.04, alpha: 1); ring = .white; glyph = .white
        case (false, false):
            chip = UIColor(white: 0.10, alpha: 1)
            ring = UIColor(red: 0.35, green: 0.78, blue: 0.94, alpha: 1); glyph = .white
        }

        var material = UnlitMaterial(color: chip)
        if let image = renderChip(symbol: symbol, chip: chip, ring: ring, glyph: glyph).cgImage,
           let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            material.color = .init(tint: .white, texture: .init(texture))
        }
        // Texture failure leaves the plain-colored chip: a worse marker
        // still beats no marker.
        materialCache[key] = material
        return material
    }

    private static func renderChip(symbol: String, chip: UIColor, ring: UIColor,
                                   glyph: UIColor) -> UIImage {
        let side: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
                                               format: format)
        return renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            chip.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 48).fill()

            let ringPath = UIBezierPath(roundedRect: rect.insetBy(dx: 12, dy: 12),
                                        cornerRadius: 40)
            ringPath.lineWidth = 12
            ring.setStroke()
            ringPath.stroke()

            let config = UIImage.SymbolConfiguration(pointSize: 130, weight: .bold)
            guard let image = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(glyph, renderingMode: .alwaysOriginal) else { return }
            let target = rect.insetBy(dx: 52, dy: 52)
            let scale = min(target.width / image.size.width, target.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale,
                                  height: image.size.height * scale)
            image.draw(in: CGRect(x: rect.midX - drawSize.width / 2,
                                  y: rect.midY - drawSize.height / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
    }
}
