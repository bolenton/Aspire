import Foundation
import PHASE
import simd
import StoryEngine

/// PHASE wrapper: every entity with a SoundSpec becomes a looping spatial
/// source; the listener follows the player's pose. Missing audio assets are
/// skipped gracefully (the curated sound pass lands separately), so the game
/// is playable at every stage of asset production.
final class SpatialAudioEngine {
    private let engine = PHASEEngine(updateMode: .automatic)
    private var listener: PHASEListener?
    private var spatialPipeline: PHASESpatialPipeline?
    private var soundEvents: [String: PHASESoundEvent] = [:]
    private var sources: [String: PHASESource] = [:]
    private(set) var isRunning = false

    /// Calibrated master level for the world (parent settings). Applied
    /// together with each sound's authored volume when sources are created.
    var worldVolume: Float = 1.0

    func start() {
        guard !isRunning else { return }
        do {
            let listener = PHASEListener(engine: engine)
            listener.transform = matrix_identity_float4x4
            try engine.rootObject.addChild(listener)
            self.listener = listener
            spatialPipeline = PHASESpatialPipeline(flags: [.directPathTransmission])

            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    /// Loads a scene: clears old sources, adds one looping source per
    /// resolved, audible-capable entity.
    func loadScene(_ scene: StoryEngine.Scene, resolved: [ResolvedEntity]) {
        removeAllSources()
        for item in resolved {
            guard !item.isAnonymousTease, let sound = item.entity.sound else { continue }
            addLoopingSource(id: item.entity.id, sound: sound, position: item.entity.position)
        }
        for (index, ambient) in scene.ambience.enumerated() {
            addLoopingSource(id: "ambience_\(index)", sound: ambient,
                             position: Vec3(x: 0, y: 0, z: 0))
        }
    }

    func addLoopingSource(id: String, sound: SoundSpec, position: Vec3) {
        guard isRunning, let spatialPipeline, let listener else { return }
        guard let url = assetURL(for: sound.asset) else { return }
        do {
            let assetID = "\(id)_asset"
            let eventID = "\(id)_event"
            try engine.assetRegistry.registerSoundAsset(
                url: url, identifier: assetID, assetType: .resident,
                channelLayout: nil, normalizationMode: .dynamic)

            // Per-source mixer so the authored volume and the calibrated
            // world level actually apply — full-blast ambience drowned the
            // narration otherwise.
            let mixer = PHASESpatialMixerDefinition(spatialPipeline: spatialPipeline)
            let distanceModel = PHASEGeometricSpreadingDistanceModelParameters()
            distanceModel.fadeOutParameters = PHASEDistanceModelFadeOutParameters(
                cullDistance: max(24, sound.farRadius * 1.3))
            mixer.distanceModelParameters = distanceModel
            mixer.gain = Double(max(0, min(1, Float(sound.volume) * worldVolume)))

            let sampler = PHASESamplerNodeDefinition(
                soundAssetIdentifier: assetID, mixerDefinition: mixer)
            sampler.playbackMode = sound.loops ? .looping : .oneShot
            try engine.assetRegistry.registerSoundEventAsset(rootNode: sampler, identifier: eventID)

            let source = PHASESource(engine: engine)
            source.transform = Self.translation(position)
            try engine.rootObject.addChild(source)

            let mixerParameters = PHASEMixerParameters()
            mixerParameters.addSpatialMixerParameters(
                identifier: mixer.identifier, source: source, listener: listener)
            let event = try PHASESoundEvent(engine: engine, assetIdentifier: eventID,
                                            mixerParameters: mixerParameters)
            event.start()
            sources[id] = source
            soundEvents[id] = event
        } catch {
            // Asset missing or malformed — skip; the manifest tracks status.
        }
    }

    func updateListener(pose: PlayerPose) {
        guard let listener else { return }
        let yaw = Float(-pose.headingDegrees * .pi / 180)
        let rotation = simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)))
        var transform = rotation
        transform.columns.3 = SIMD4<Float>(Float(pose.position.x), Float(pose.position.y),
                                           Float(pose.position.z), 1)
        listener.transform = transform
    }

    /// Freeze-and-explain: the world gently pauses while the companion talks.
    func setFrozen(_ frozen: Bool) {
        for event in soundEvents.values {
            if frozen { event.pause() } else { event.resume() }
        }
    }

    func removeSource(id: String) {
        soundEvents[id]?.stopAndInvalidate()
        soundEvents[id] = nil
        if let source = sources[id] {
            engine.rootObject.removeChild(source)
            sources[id] = nil
        }
    }

    func removeAllSources() {
        for id in Array(soundEvents.keys) {
            removeSource(id: id)
            engine.assetRegistry.unregisterAsset(identifier: "\(id)_event")
            engine.assetRegistry.unregisterAsset(identifier: "\(id)_asset")
        }
    }

    private func assetURL(for assetName: String) -> URL? {
        let base = (assetName as NSString).deletingPathExtension
        let ext = (assetName as NSString).pathExtension
        return Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Assets/Audio")
            ?? Bundle.main.url(forResource: base, withExtension: ext)
    }

    private static func translation(_ position: Vec3) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(Float(position.x), Float(position.y), Float(position.z), 1)
        return matrix
    }
}
