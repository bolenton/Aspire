import AVFAudio
import Foundation
import PHASE
import simd
import StoryEngine

/// Duck groups for live gain control. Ambience is the non-spatial bed
/// (source ids prefixed "ambience_"); everything else is a positional
/// entity loop that carries navigation information, so it ducks less.
enum SourceCategory: CaseIterable {
    case ambience
    case entity
}

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
    /// Live gain handles per source — the only sanctioned way to change a
    /// running event's level; rebuilding a source mid-loop pops audibly.
    private var gainParams: [String: PHASENumberMetaParameter] = [:]
    /// Authored level × world calibration per source; duck multipliers apply
    /// on top so releasing a duck restores exactly the authored mix.
    private var baseGains: [String: Double] = [:]
    /// Last group multiplier per category, remembered so sources created
    /// mid-duck (scene entry during the opening narration) start at the
    /// ducked level instead of popping in loud.
    private var duckFactors: [SourceCategory: Double] = [:]
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
            addAmbienceSource(id: "ambience_\(index)", sound: ambient)
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

            // The level rides a metaparameter, never `mixer.gain` (read-only
            // once the event runs). Whether the metaparameter replaces or
            // multiplies `mixer.gain` is undocumented — leaving the mixer at
            // its default 1.0 and carrying the absolute gain here is correct
            // under either semantics. Entity loops start at full level
            // immediately (they are navigation information), only pre-ducked
            // when a voice currently holds the mix down.
            let baseGain = Double(max(0, min(1, Float(sound.volume) * worldVolume)))
            let gainDef = PHASENumberMetaParameterDefinition(
                value: baseGain * duckFactor(for: id), minimum: 0.0, maximum: 2.0,
                identifier: "\(id)_gain")
            mixer.gainMetaParameterDefinition = gainDef

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
            baseGains[id] = baseGain
            gainParams[id] = event.metaParameters["\(id)_gain"] as? PHASENumberMetaParameter
        } catch {
            // Asset missing or malformed — skip; the manifest tracks status.
        }
    }

    /// Ambience plays as a non-spatial bed routed straight to the output.
    /// A spatial ambience source has to live *somewhere* in the world — and
    /// it used to sit at the origin, exactly where the player spawns, at full
    /// volume in both ears. The bed also enters from silence over 2.5 s so a
    /// scene's opening narration always lands on top of it.
    func addAmbienceSource(id: String, sound: SoundSpec) {
        guard isRunning else { return }
        guard let url = assetURL(for: sound.asset),
              let layout = Self.channelLayout(forAssetAt: url) else { return }
        do {
            let assetID = "\(id)_asset"
            let eventID = "\(id)_event"
            try engine.assetRegistry.registerSoundAsset(
                url: url, identifier: assetID, assetType: .resident,
                channelLayout: layout, normalizationMode: .dynamic)

            let mixer = PHASEChannelMixerDefinition(channelLayout: layout)
            let gainDef = PHASENumberMetaParameterDefinition(
                value: 0.0, minimum: 0.0, maximum: 2.0, identifier: "\(id)_gain")
            mixer.gainMetaParameterDefinition = gainDef

            let sampler = PHASESamplerNodeDefinition(
                soundAssetIdentifier: assetID, mixerDefinition: mixer)
            sampler.playbackMode = sound.loops ? .looping : .oneShot
            try engine.assetRegistry.registerSoundEventAsset(rootNode: sampler, identifier: eventID)

            let event = try PHASESoundEvent(engine: engine, assetIdentifier: eventID)
            event.start()
            soundEvents[id] = event

            let baseGain = Double(max(0, min(1, Float(sound.volume) * worldVolume)))
            baseGains[id] = baseGain
            if let param = event.metaParameters["\(id)_gain"] as? PHASENumberMetaParameter {
                gainParams[id] = param
                param.fade(value: baseGain * duckFactor(for: id), duration: 2.5)
            }
        } catch {
            // Asset missing or malformed — skip; the manifest tracks status.
        }
    }

    // MARK: - Live gain (ducking)

    /// Applies a group multiplier on top of each source's authored base gain.
    /// Remembered per category so sources created while the duck is active
    /// start at the ducked level — releasing restores the authored mix.
    func setGroupGain(category: SourceCategory, multiplier: Double, fade: TimeInterval) {
        duckFactors[category] = multiplier
        for (id, param) in gainParams where Self.category(forSourceID: id) == category {
            guard let base = baseGains[id] else { continue }
            param.fade(value: base * multiplier, duration: fade)
        }
    }

    func setSourceGain(id: String, multiplier: Double, fade: TimeInterval) {
        guard let param = gainParams[id], let base = baseGains[id] else { return }
        param.fade(value: base * multiplier, duration: fade)
    }

    private func duckFactor(for sourceID: String) -> Double {
        duckFactors[Self.category(forSourceID: sourceID)] ?? 1.0
    }

    private static func category(forSourceID id: String) -> SourceCategory {
        id.hasPrefix("ambience_") ? .ambience : .entity
    }

    /// The channel mixer must be built with the asset's own layout. Current
    /// placeholder assets are mono, but reading the file keeps stereo beds
    /// working when curated audio lands.
    private static func channelLayout(forAssetAt url: URL) -> AVAudioChannelLayout? {
        let channelCount = (try? AVAudioFile(forReading: url))?.processingFormat.channelCount ?? 1
        let tag = channelCount >= 2 ? kAudioChannelLayoutTag_Stereo : kAudioChannelLayoutTag_Mono
        return AVAudioChannelLayout(layoutTag: tag)
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
        gainParams[id] = nil
        baseGains[id] = nil
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
