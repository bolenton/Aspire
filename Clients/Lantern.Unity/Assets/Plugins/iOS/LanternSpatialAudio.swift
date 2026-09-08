import AVFAudio
import CoreMotion
import Foundation
import PHASE
import simd

/// Native spatial audio stays behind a C ABI; story and renderer types never enter this layer.
private final class LanternSpatialAudio {
    let engine = PHASEEngine(updateMode: .automatic)
    let motion = CMHeadphoneMotionManager()
    var listener: PHASEListener?
    var pipeline: PHASESpatialPipeline?
    var events: [String: PHASESoundEvent] = [:]
    var sources: [String: PHASESource] = [:]
    var gains: [String: PHASENumberMetaParameter] = [:]
    var levels: [String: Double] = [:]
    var baselineYaw: Double?
    var headYaw = 0.0
    var duck = 1.0

    func start() throws {
        let listener = PHASEListener(engine: engine)
        try engine.rootObject.addChild(listener)
        self.listener = listener
        pipeline = PHASESpatialPipeline(flags: [.directPathTransmission])
        try engine.start()
        if motion.isDeviceMotionAvailable {
            motion.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                let yaw = -motion.attitude.yaw * 180 / .pi
                if self.baselineYaw == nil { self.baselineYaw = yaw }
                self.headYaw = yaw - (self.baselineYaw ?? yaw)
            }
        }
    }
    func add(id: String, path: String, x: Float, y: Float, z: Float, volume: Double, far: Double, loops: Bool) throws {
        guard let pipeline, let listener else { return }
        remove(id)
        do {
            try engine.assetRegistry.registerSoundAsset(url: URL(fileURLWithPath: path), identifier: id + "_asset", assetType: .resident, channelLayout: nil, normalizationMode: .dynamic)
            let mixer = PHASESpatialMixerDefinition(spatialPipeline: pipeline)
            let distance = PHASEGeometricSpreadingDistanceModelParameters()
            distance.fadeOutParameters = PHASEDistanceModelFadeOutParameters(cullDistance: max(8, far))
            mixer.distanceModelParameters = distance
            mixer.gainMetaParameterDefinition = PHASENumberMetaParameterDefinition(value: volume * duck, minimum: 0, maximum: 2, identifier: id + "_gain")
            let sampler = PHASESamplerNodeDefinition(soundAssetIdentifier: id + "_asset", mixerDefinition: mixer)
            sampler.playbackMode = loops ? .looping : .oneShot
            try engine.assetRegistry.registerSoundEventAsset(rootNode: sampler, identifier: id + "_event")
            let source = PHASESource(engine: engine)
            var position = matrix_identity_float4x4
            position.columns.3 = SIMD4<Float>(x, y, -z, 1)
            source.transform = position
            try engine.rootObject.addChild(source)
            sources[id] = source
            let parameters = PHASEMixerParameters()
            parameters.addSpatialMixerParameters(identifier: mixer.identifier, source: source, listener: listener)
            let event = try PHASESoundEvent(engine: engine, assetIdentifier: id + "_event", mixerParameters: parameters)
            events[id] = event
            gains[id] = event.metaParameters[id + "_gain"] as? PHASENumberMetaParameter
            levels[id] = volume
            event.start()
        } catch { remove(id); throw error }
    }
    func pose(x: Float, y: Float, z: Float, yaw: Float) {
        let angle = -(yaw + Float(headYaw)) * .pi / 180
        var pose = simd_float4x4(simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0)))
        pose.columns.3 = SIMD4<Float>(x, y, -z, 1)
        listener?.transform = pose
    }
    func setDuck(_ multiplier: Double) {
        duck = min(1, max(0, multiplier))
        for (id, gain) in gains { gain.fade(value: (levels[id] ?? 0) * duck, duration: 0.18) }
    }
    func remove(_ id: String) {
        events.removeValue(forKey: id)?.stopAndInvalidate()
        if let source = sources.removeValue(forKey: id) { engine.rootObject.removeChild(source) }
        gains[id] = nil
        levels[id] = nil
        engine.assetRegistry.unregisterAsset(identifier: id + "_event")
        engine.assetRegistry.unregisterAsset(identifier: id + "_asset")
    }
    func stop() {
        motion.stopDeviceMotionUpdates()
        for id in Array(events.keys) { remove(id) }
        engine.stop()
    }
}

private var audio: LanternSpatialAudio?
@_cdecl("LanternSpatialStart")
func lanternSpatialStart() -> Int32 {
    audio?.stop()
    let next = LanternSpatialAudio()
    do { try next.start(); audio = next; return 1 }
    catch { NSLog("Lantern spatial audio could not start: %@", error.localizedDescription); audio = nil; return 0 }
}
@_cdecl("LanternSpatialAdd")
func lanternSpatialAdd(_ id: UnsafePointer<CChar>, _ path: UnsafePointer<CChar>, _ x: Float, _ y: Float, _ z: Float, _ volume: Float, _ far: Float, _ loops: Int32) -> Int32 {
    guard let audio else { return 0 }
    do {
        try audio.add(id: String(cString: id), path: String(cString: path), x: x, y: y, z: z, volume: Double(volume), far: Double(far), loops: loops != 0)
        return 1
    } catch { NSLog("Lantern sound could not load: %@", error.localizedDescription); return 0 }
}
@_cdecl("LanternSpatialPose")
func lanternSpatialPose(_ x: Float, _ y: Float, _ z: Float, _ yaw: Float) { audio?.pose(x: x, y: y, z: z, yaw: yaw) }
@_cdecl("LanternSpatialDuck")
func lanternSpatialDuck(_ multiplier: Float) { audio?.setDuck(Double(multiplier)) }
@_cdecl("LanternSpatialRemove")
func lanternSpatialRemove(_ id: UnsafePointer<CChar>) { audio?.remove(String(cString: id)) }
@_cdecl("LanternSpatialPause")
func lanternSpatialPause(_ paused: Int32) {
    guard let audio else { return }
    for event in audio.events.values { if paused != 0 { event.pause() } else { event.resume() } }
    audio.baselineYaw = nil
}
@_cdecl("LanternSpatialRecenter")
func lanternSpatialRecenter() { audio?.baselineYaw = nil; audio?.headYaw = 0 }
@_cdecl("LanternSpatialStop")
func lanternSpatialStop() { audio?.stop(); audio = nil }
