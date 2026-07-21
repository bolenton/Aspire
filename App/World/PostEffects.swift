import Metal
import MetalPerformanceShaders
import RealityKit

/// The world's screen-space post stack: multi-scale bloom plus a
/// depth-discontinuity outline, so her emissive glows halo *around* shapes
/// while every object keeps a crisp drawn contour — the two halves of
/// "readable at a glance" for low vision. Bloom used to be a single wide
/// gaussian that smeared the very edges it was meant to celebrate; now a
/// tight half-res tap keeps the bright core sharp while a quarter-res tap
/// supplies the soft aura, and the outline is drawn last so edges survive
/// the glow.
///
/// Two non-negotiables shape the whole class. RealityKit treats the
/// post-process callback as the only thing that fills the screen: once
/// registered, *every* frame must end with the drawable's color living in
/// `targetColorTexture`, or the screen goes black. And the drawable's pixel
/// format is the device's call, not ours — we read it off the context and
/// never assume. So the stack degrades in layers: full chain → MPS-only
/// bloom (if the composite shader can't load) → plain blit (if anything
/// else can't run). A frame without effects is invisible to her; a black
/// frame is the failure mode this design exists to prevent.
final class WorldPostEffects {
    /// Matches `CompositeUniforms` in PostShaders.metal — field order and
    /// the trailing pads keep the Swift stride identical to Metal's 48-byte
    /// constant-buffer layout.
    private struct CompositeUniforms {
        var outlineColor: SIMD4<Float>
        var edgeThreshold: Float
        var outlineRadius: Float
        var tightWeight: Float
        var wideWeight: Float
        var outlineEnabled: UInt32
        var pad0: UInt32 = 0
        var pad1: UInt32 = 0
        var pad2: UInt32 = 0
    }

    /// White contour lines in high-contrast mode (light edges on the
    /// near-black world), near-black ink everywhere else. Set from the view
    /// when the calibration theme changes; read on the render thread — a
    /// frame of staleness is invisible.
    var highContrast = false
    /// The adaptive support level thickens outlines the same way it enlarges
    /// markers: more help means heavier edges.
    var glowBoost: Float = 1

    private let device: MTLDevice
    private let threshold: MPSImageThresholdToZero
    private let blurTight: MPSImageGaussianBlur
    private let blurWide: MPSImageGaussianBlur
    private let add: MPSImageAdd
    private let bilinearScale: MPSImageBilinearScale
    /// nil when the app's metallib or the kernel is unavailable — the stack
    /// then runs the MPS-only bloom path (no outlines) instead of dying.
    private let compositePipeline: MTLComputePipelineState?

    /// Full-resolution bright pass, reused as the upscaled blur in the
    /// MPS-only fallback path. Kept at the source's pixel format.
    private var brightTexture: MTLTexture?
    /// Half-resolution downsample of the bright pass.
    private var halfTexture: MTLTexture?
    /// Tightly blurred half-res result — the sharp bloom core.
    private var halfBlurTexture: MTLTexture?
    /// Quarter-resolution cascade of the tight blur.
    private var quarterTexture: MTLTexture?
    /// Widely blurred quarter-res result — the soft outer aura.
    private var quarterBlurTexture: MTLTexture?
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
        self.blurTight = MPSImageGaussianBlur(device: device, sigma: 4)
        self.blurWide = MPSImageGaussianBlur(device: device, sigma: 10)
        self.add = MPSImageAdd(device: device)
        self.bilinearScale = MPSImageBilinearScale(device: device)
        // Let the bright pass and blurs clamp at the frame edge rather than
        // read out of bounds.
        self.threshold.edgeMode = .clamp
        self.blurTight.edgeMode = .clamp
        self.blurWide.edgeMode = .clamp

        // The composite kernel is an upgrade, never a requirement: if the
        // metallib is missing or the pipeline won't build, bloom still runs
        // on pure MPS and outlines simply don't happen.
        if let library = device.makeDefaultLibrary(),
           let function = library.makeFunction(name: "postComposite") {
            self.compositePipeline = try? device.makeComputePipelineState(function: function)
        } else {
            self.compositePipeline = nil
        }
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
    /// `targetColorTexture`; bloom and outlines are added when the chain
    /// can run.
    private func process(_ context: ARView.PostProcessContext) {
        let source = context.sourceColorTexture
        let target = context.targetColorTexture
        let depth = context.sourceDepthTexture

        if !didLogFirstCallback {
            didLogFirstCallback = true
            // First-fire probe: confirms the post-process pass runs, reports
            // the drawable resolution (sharpness debugging), and says whether
            // the outline kernel loaded.
            print("[WorldPostEffects] postProcess fired — "
                  + "source \(source.width)x\(source.height) "
                  + "format \(source.pixelFormat.rawValue), "
                  + "depth \(depth.width)x\(depth.height), "
                  + "composite kernel \(compositePipeline == nil ? "unavailable" : "loaded")")
        }

        // The chain needs the target to share the source's extent and format
        // (both composite paths write source + bloom straight into target);
        // anything else falls through to the guaranteed plain copy below.
        let canRun = target.width == source.width
            && target.height == source.height
            && target.pixelFormat == source.pixelFormat
            && ensureScratch(matching: source)

        guard canRun,
              let bright = brightTexture,
              let half = halfTexture,
              let halfBlur = halfBlurTexture,
              let quarter = quarterTexture,
              let quarterBlur = quarterBlurTexture else {
            // Guaranteed path: copy the rendered frame into the target unchanged
            // so the screen is never left empty.
            blit(from: source, to: target, commandBuffer: context.commandBuffer)
            return
        }

        let commandBuffer = context.commandBuffer
        // 1. Keep only pixels above 0.85; everything dimmer goes to zero.
        threshold.encode(commandBuffer: commandBuffer, sourceTexture: source,
                         destinationTexture: bright)
        // 2. Half resolution, tight blur: the bloom's sharp bright core.
        bilinearScale.encode(commandBuffer: commandBuffer, sourceTexture: bright,
                             destinationTexture: half)
        blurTight.encode(commandBuffer: commandBuffer, sourceTexture: half,
                         destinationTexture: halfBlur)
        // 3. Cascade to quarter resolution, wide blur: the soft outer aura.
        bilinearScale.encode(commandBuffer: commandBuffer, sourceTexture: halfBlur,
                             destinationTexture: quarter)
        blurWide.encode(commandBuffer: commandBuffer, sourceTexture: quarter,
                        destinationTexture: quarterBlur)

        // 4. Composite. The custom kernel samples both bloom taps and draws
        //    depth outlines in one pass; without it, fall back to upscale +
        //    MPS add — yesterday's bloom, still never a black frame.
        if let pipeline = compositePipeline,
           depth.width == source.width, depth.height == source.height,
           encodeComposite(pipeline: pipeline, commandBuffer: commandBuffer,
                           source: source, tight: halfBlur, wide: quarterBlur,
                           depth: depth, target: target) {
            return
        }
        bilinearScale.encode(commandBuffer: commandBuffer, sourceTexture: halfBlur,
                             destinationTexture: bright)
        add.encode(commandBuffer: commandBuffer, primaryTexture: source,
                   secondaryTexture: bright, destinationTexture: target)
    }

    /// Encodes the composite kernel; returns false (having encoded nothing)
    /// if the encoder can't be created, so the caller can take the MPS path.
    private func encodeComposite(pipeline: MTLComputePipelineState,
                                 commandBuffer: MTLCommandBuffer,
                                 source: MTLTexture, tight: MTLTexture,
                                 wide: MTLTexture, depth: MTLTexture,
                                 target: MTLTexture) -> Bool {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }

        let outlineColor: SIMD4<Float> = highContrast
            ? SIMD4<Float>(1.0, 1.0, 1.0, 0.9)
            : SIMD4<Float>(0.02, 0.02, 0.04, 0.65)
        var uniforms = CompositeUniforms(
            outlineColor: outlineColor,
            edgeThreshold: 0.08,
            outlineRadius: min(4, 2 + 2 * max(0, glowBoost - 1)),
            tightWeight: 0.6,
            wideWeight: 0.5,
            outlineEnabled: 1)

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(tight, index: 1)
        encoder.setTexture(wide, index: 2)
        encoder.setTexture(depth, index: 3)
        encoder.setTexture(target, index: 4)
        encoder.setBytes(&uniforms, length: MemoryLayout<CompositeUniforms>.stride, index: 0)

        let group = MTLSize(width: 16, height: 16, depth: 1)
        let groups = MTLSize(width: (target.width + group.width - 1) / group.width,
                             height: (target.height + group.height - 1) / group.height,
                             depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: group)
        encoder.endEncoding()
        return true
    }

    /// Plain GPU copy: the fallback target write for any frame the chain
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
           quarterTexture != nil, quarterBlurTexture != nil,
           cachedWidth == source.width, cachedHeight == source.height,
           cachedFormat == source.pixelFormat {
            return true
        }

        let halfWidth = max(1, source.width / 2)
        let halfHeight = max(1, source.height / 2)
        let quarterWidth = max(1, source.width / 4)
        let quarterHeight = max(1, source.height / 4)

        func descriptor(width: Int, height: Int) -> MTLTextureDescriptor {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: source.pixelFormat, width: width,
                height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            return descriptor
        }

        guard let bright = device.makeTexture(descriptor: descriptor(width: source.width,
                                                                     height: source.height)),
              let half = device.makeTexture(descriptor: descriptor(width: halfWidth,
                                                                   height: halfHeight)),
              let halfBlur = device.makeTexture(descriptor: descriptor(width: halfWidth,
                                                                       height: halfHeight)),
              let quarter = device.makeTexture(descriptor: descriptor(width: quarterWidth,
                                                                      height: quarterHeight)),
              let quarterBlur = device.makeTexture(descriptor: descriptor(width: quarterWidth,
                                                                          height: quarterHeight)) else {
            brightTexture = nil
            halfTexture = nil
            halfBlurTexture = nil
            quarterTexture = nil
            quarterBlurTexture = nil
            cachedWidth = 0
            cachedHeight = 0
            cachedFormat = .invalid
            return false
        }
        brightTexture = bright
        halfTexture = half
        halfBlurTexture = halfBlur
        quarterTexture = quarter
        quarterBlurTexture = quarterBlur
        cachedWidth = source.width
        cachedHeight = source.height
        cachedFormat = source.pixelFormat
        return true
    }
}
