import Metal
import MetalPerformanceShaders
import RealityKit

/// Screen-space bloom for the post-process pass, so her emissive glows actually
/// glow instead of stopping flat at the pixel that emits them — the visual half
/// of the recognizability goal for low vision.
///
/// The recipe is the classic four-stage MPS chain: keep only the brightest
/// pixels (threshold), shrink them to half resolution (cheap, and a wider blur
/// for free), gaussian-blur the bright pass, then add it back onto the rendered
/// frame. The whole thing runs on the same command buffer RealityKit hands us,
/// so it costs ~1–2 ms and never stalls the render.
///
/// Two non-negotiables shape the whole class. RealityKit treats the post-process
/// callback as the only thing that fills the screen: once registered, *every*
/// frame must end with the drawable's color living in `targetColorTexture`, or
/// the screen goes black. And the drawable's pixel format is the device's call,
/// not ours — we read it off the context and never assume. So when anything in
/// the MPS chain can't run (a format we didn't expect, an allocation that
/// failed), we fall back to a plain blit that copies source → target. A frame
/// without bloom is invisible to her; a black frame is the failure mode this
/// design exists to prevent.
final class BloomPostProcess {
    private let device: MTLDevice
    private let threshold: MPSImageThresholdToZero
    private let blur: MPSImageGaussianBlur
    private let add: MPSImageAdd
    private let bilinearScale: MPSImageBilinearScale

    /// Full-resolution bright pass, also reused as the upscaled blur on its way
    /// into the add. Kept at the source's pixel format; rebuilt on resize.
    private var brightTexture: MTLTexture?
    /// Half-resolution downsample of the bright pass.
    private var halfTexture: MTLTexture?
    /// Blurred half-resolution result — separate from `halfTexture` so the
    /// gaussian runs out-of-place (no fragile in-place pointer juggling).
    private var halfBlurTexture: MTLTexture?
    private var cachedWidth = 0
    private var cachedHeight = 0
    private var cachedFormat: MTLPixelFormat = .invalid

    private var didLogFirstCallback = false

    /// Fails (returns nil) if MPS is unsupported on this device, in which case
    /// the caller simply never registers us and rendering is untouched.
    init?(device: MTLDevice) {
        self.device = device
        // MPS kernels initialize unconditionally; the meaningful failure mode is
        // a device that doesn't support MPS at all.
        guard MPSSupportsMTLDevice(device) else { return nil }
        self.threshold = MPSImageThresholdToZero(device: device, thresholdValue: 0.85,
                                                 linearGrayColorTransform: nil)
        self.blur = MPSImageGaussianBlur(device: device, sigma: 14)
        self.add = MPSImageAdd(device: device)
        self.bilinearScale = MPSImageBilinearScale(device: device)
        // Let the bright pass and blur clamp at the frame edge rather than read
        // out of bounds.
        self.threshold.edgeMode = .clamp
        self.blur.edgeMode = .clamp
    }

    func register(on arView: ARView) {
        arView.renderCallbacks.postProcess = { [weak self] context in
            self?.process(context)
        }
    }

    func unregister(from arView: ARView) {
        arView.renderCallbacks.postProcess = nil
    }

    /// The per-frame callback. Always leaves the rendered image in
    /// `targetColorTexture`; bloom is added on top when the chain can run.
    private func process(_ context: ARView.PostProcessContext) {
        let source = context.sourceColorTexture
        let target = context.targetColorTexture

        if !didLogFirstCallback {
            didLogFirstCallback = true
            // First-fire probe: confirms RealityKit's nonAR post-process pass
            // actually runs on this platform (the plan's feasibility check).
            print("[BloomPostProcess] postProcess callback fired — "
                  + "source \(source.width)x\(source.height) "
                  + "format \(source.pixelFormat.rawValue), "
                  + "target format \(target.pixelFormat.rawValue)")
        }

        // The MPS chain needs the target to share the source's extent and
        // format (the final add writes source + bloom straight into target);
        // anything else falls through to the guaranteed plain copy below.
        let canBloom = target.width == source.width
            && target.height == source.height
            && target.pixelFormat == source.pixelFormat
            && ensureScratch(matching: source)

        guard canBloom,
              let bright = brightTexture,
              let half = halfTexture,
              let halfBlur = halfBlurTexture else {
            // Guaranteed path: copy the rendered frame into the target unchanged
            // so the screen is never left empty.
            blit(from: source, to: target, commandBuffer: context.commandBuffer)
            return
        }

        let commandBuffer = context.commandBuffer
        // 1. Keep only pixels above 0.85; everything dimmer goes to zero.
        threshold.encode(commandBuffer: commandBuffer, sourceTexture: source,
                         destinationTexture: bright)
        // 2. Drop to half resolution — cheaper blur, and a softer one for free.
        bilinearScale.encode(commandBuffer: commandBuffer, sourceTexture: bright,
                             destinationTexture: half)
        // 3. Blur the half-res bright pass out-of-place.
        blur.encode(commandBuffer: commandBuffer, sourceTexture: half,
                    destinationTexture: halfBlur)
        // 4. Upscale the blur back to full size, then add it onto the original
        //    rendered frame — three distinct textures, so nothing aliases — and
        //    write the composite straight into the target.
        bilinearScale.encode(commandBuffer: commandBuffer, sourceTexture: halfBlur,
                             destinationTexture: bright)
        add.encode(commandBuffer: commandBuffer, primaryTexture: source,
                   secondaryTexture: bright, destinationTexture: target)
    }

    /// Plain GPU copy: the fallback target write for any frame the MPS chain
    /// can't run. If even the blit can't be encoded the frame is lost, but
    /// RealityKit cleared the target first, so the worst case is a flicker.
    private func blit(from source: MTLTexture, to target: MTLTexture,
                      commandBuffer: MTLCommandBuffer) {
        guard source.width == target.width, source.height == target.height,
              let encoder = commandBuffer.makeBlitCommandEncoder() else { return }
        let size = MTLSize(width: source.width, height: source.height, depth: 1)
        let origin = MTLOrigin(x: 0, y: 0, z: 0)
        encoder.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                     sourceOrigin: origin, sourceSize: size,
                     to: target, destinationSlice: 0, destinationLevel: 0,
                     destinationOrigin: origin)
        encoder.endEncoding()
    }

    /// Allocates (or reuses) the scratch textures, rebuilding them whenever the
    /// drawable size or pixel format changes. Returns false on allocation
    /// failure so the caller falls back to the plain blit.
    private func ensureScratch(matching source: MTLTexture) -> Bool {
        if brightTexture != nil, halfTexture != nil, halfBlurTexture != nil,
           cachedWidth == source.width, cachedHeight == source.height,
           cachedFormat == source.pixelFormat {
            return true
        }

        let halfWidth = max(1, source.width / 2)
        let halfHeight = max(1, source.height / 2)

        let fullDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat, width: source.width,
            height: source.height, mipmapped: false)
        fullDescriptor.usage = [.shaderRead, .shaderWrite]
        fullDescriptor.storageMode = .private

        let halfDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat, width: halfWidth,
            height: halfHeight, mipmapped: false)
        halfDescriptor.usage = [.shaderRead, .shaderWrite]
        halfDescriptor.storageMode = .private

        guard let bright = device.makeTexture(descriptor: fullDescriptor),
              let half = device.makeTexture(descriptor: halfDescriptor),
              let halfBlur = device.makeTexture(descriptor: halfDescriptor) else {
            brightTexture = nil
            halfTexture = nil
            halfBlurTexture = nil
            cachedWidth = 0
            cachedHeight = 0
            cachedFormat = .invalid
            return false
        }
        brightTexture = bright
        halfTexture = half
        halfBlurTexture = halfBlur
        cachedWidth = source.width
        cachedHeight = source.height
        cachedFormat = source.pixelFormat
        return true
    }
}
