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
        // The contour is a subtitle-style rim around the glyph — opposite
        // polarity so the icon's edge stays defined even where chip and glyph
        // luminance converge under bloom. High contrast skips it: those chips
        // are already at maximum contrast and must stay visually pure.
        let chip: UIColor
        let ring: UIColor
        let glyph: UIColor
        let contour: UIColor?
        switch (isQuestTarget, highContrast) {
        case (true, true):
            chip = .white; ring = .white; glyph = UIColor(white: 0.05, alpha: 1)
            contour = nil
        case (true, false):
            chip = UIColor(red: 1.0, green: 0.82, blue: 0.29, alpha: 1)
            ring = .white; glyph = UIColor(white: 0.10, alpha: 1)
            contour = .white
        case (false, true):
            chip = UIColor(white: 0.04, alpha: 1); ring = .white; glyph = .white
            contour = nil
        case (false, false):
            chip = UIColor(white: 0.10, alpha: 1)
            ring = UIColor(red: 0.35, green: 0.78, blue: 0.94, alpha: 1); glyph = .white
            contour = UIColor(white: 0.0, alpha: 1)
        }

        var material = UnlitMaterial(color: chip)
        // Mipmaps matter here: the tick scales chips with distance, and
        // without a mip chain a high-resolution texture shimmers when it
        // minifies — trading one artifact for another.
        var textureOptions = TextureResource.CreateOptions(semantic: .color)
        textureOptions.mipmapsMode = .allocateAndGenerateAll
        if let image = renderChip(symbol: symbol, chip: chip, ring: ring, glyph: glyph,
                                  contour: contour).cgImage,
           let texture = try? TextureResource(image: image, options: textureOptions) {
            material.color = .init(tint: .white, texture: .init(texture))
        }
        // Texture failure leaves the plain-colored chip: a worse marker
        // still beats no marker.
        materialCache[key] = material
        return material
    }

    private static func renderChip(symbol: String, chip: UIColor, ring: UIColor,
                                   glyph: UIColor, contour: UIColor?) -> UIImage {
        // 512pt at the display's scale (capped at 2× — past that the chip
        // plane never covers enough screen to show more pixels) — up to
        // 1024², sixteen times the pixels of the original 256² @1× raster.
        // Every metric derives from `side` so the design is unchanged.
        let side: CGFloat = 512
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(UIScreen.main.scale, 2)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
                                               format: format)
        return renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            chip.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: side * 0.1875).fill()

            let ringInset = side * 0.047
            let ringPath = UIBezierPath(roundedRect: rect.insetBy(dx: ringInset, dy: ringInset),
                                        cornerRadius: side * 0.156)
            ringPath.lineWidth = side * 0.047
            ring.setStroke()
            ringPath.stroke()

            let config = UIImage.SymbolConfiguration(pointSize: side * 0.51, weight: .bold)
            guard let image = UIImage(systemName: symbol, withConfiguration: config) else { return }
            let inset = side * 0.203
            let target = rect.insetBy(dx: inset, dy: inset)
            let scale = min(target.width / image.size.width, target.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale,
                                  height: image.size.height * scale)
            let drawRect = CGRect(x: rect.midX - drawSize.width / 2,
                                  y: rect.midY - drawSize.height / 2,
                                  width: drawSize.width, height: drawSize.height)
            if let contour {
                let contourImage = image.withTintColor(contour, renderingMode: .alwaysOriginal)
                let offset = side * 0.008
                for dx: CGFloat in [-offset, 0, offset] {
                    for dy: CGFloat in [-offset, 0, offset] where dx != 0 || dy != 0 {
                        contourImage.draw(in: drawRect.offsetBy(dx: dx, dy: dy))
                    }
                }
            }
            image.withTintColor(glyph, renderingMode: .alwaysOriginal).draw(in: drawRect)
        }
    }
}
