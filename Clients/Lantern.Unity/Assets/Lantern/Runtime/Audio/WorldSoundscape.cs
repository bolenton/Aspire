using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using Lantern.Core.Content;
using Lantern.Core.Gameplay;
using Lantern.Unity.Platform;
using UnityEngine;
using UnityEngine.Networking;

namespace Lantern.Unity.Audio
{
    public sealed class WorldSoundscape : MonoBehaviour
    {
        private readonly Dictionary<string, AudioSource> unitySources = new Dictionary<string, AudioSource>();
        private readonly HashSet<string> activeIDs = new HashSet<string>();
        private readonly Dictionary<string, float> volumes = new Dictionary<string, float>();
        private readonly List<AudioClip> clips = new List<AudioClip>();
        private bool native, busy;
        private float worldVolume = 1;
        public event Action<string> AssetFailed;
        public void Initialize(SceneDefinition scene, float volume)
        {
            worldVolume = Mathf.Clamp01(volume);
            native = SpatialAudioBridge.Start();
            if (scene.Id == "fox_hollow")
            {
                AddMeadow("ambience_birds", "Birds.wav", .52f, transform, false);
                AddMeadow("ambience_music", "MeadowScore.mp3", .32f, transform, false);
                var river = new GameObject("Recorded river ambience").transform;
                river.SetParent(transform); river.position = new Vector3(12,0,6);
                AddMeadow("ambience_river", "River.wav", .7f, river, true);
            }

        }
        private void AddMeadow(string id, string file, float volume, Transform anchor, bool spatial)
        {
            activeIDs.Add(id);
            volumes[id] = volume * worldVolume;
            var spec = new SoundSpec { Asset = file, Loops = true, NearRadius = 2, FarRadius = 20 };
            var path = Path.Combine(Application.streamingAssetsPath,"Meadow",file);
            if (native && spatial && SpatialAudioBridge.Add(id,path,anchor.position,volumes[id],20,true)) return;
            StartCoroutine(LoadUnity(id,path,spec,anchor,spatial));
        }
        public void Refresh(SceneDefinition scene, GameProgress progress, IReadOnlyDictionary<string, Transform> anchors, string targetID)
        {
            foreach (var entity in scene.Entities)
            {
                if (entity.Sound == null || !anchors.TryGetValue(entity.Id, out var anchor)) continue;
                var audible = entity.Id == targetID && progress.IsAvailable(entity) && !progress.Inventory.Contains(entity.Id);
                if (audible && !activeIDs.Contains(entity.Id))
                {
                    if (entity.Id == "old_oak") AddMeadow(entity.Id,"Oak.wav",.28f,anchor,true);
                    else if (entity.Id == "glowing_acorn") AddMeadow(entity.Id,"Acorn.wav",.35f,anchor,true);
                    else if (entity.Sound.Asset == "Bell.wav" || entity.Sound.Asset == "Oak.wav" || entity.Sound.Asset == "Acorn.wav")
                        AddMeadow(entity.Id,entity.Sound.Asset,.25f,anchor,true);
                    // Only the current destination sounds; the ambient river remains separate.
                }
                if (!audible && activeIDs.Contains(entity.Id)) Remove(entity.Id);
            }
        }
        private IEnumerator LoadUnity(string id, string path, SoundSpec spec, Transform anchor, bool spatial)
        {
            var type = path.EndsWith(".mp3", StringComparison.OrdinalIgnoreCase) ? AudioType.MPEG : AudioType.WAV;
            using (var request = UnityWebRequestMultimedia.GetAudioClip(new Uri(path).AbsoluteUri, type))
            {
                yield return request.SendWebRequest();
                if (request.result != UnityWebRequest.Result.Success)
                { Debug.LogError("Lantern audio missing: " + spec.Asset); AssetFailed?.Invoke(spec.Asset); yield break; }
                var clip = DownloadHandlerAudioClip.GetContent(request); clips.Add(clip);
                if (!activeIDs.Contains(id) || anchor == null) yield break;
                var source = anchor.gameObject.AddComponent<AudioSource>();
                source.clip = clip; source.loop = spec.Loops;
                source.spatialBlend = spatial ? 1 : 0;
                source.dopplerLevel = 0;
                source.minDistance = (float)spec.NearRadius; source.maxDistance = (float)spec.FarRadius;
                source.rolloffMode = AudioRolloffMode.Linear;
                source.volume = volumes[id] * DuckFactor(id);
                unitySources[id] = source;
                source.Play();
            }
        }
        public void Duck(bool speaking)
        {
            busy = speaking;
            SpatialAudioBridge.Duck(busy ? .28f : 1);
            foreach (var (id, source) in unitySources) if (source != null) source.volume = volumes[id] * DuckFactor(id);
        }
        private float DuckFactor(string id) => !busy ? 1 : id.StartsWith("ambience_") ? .1f : .28f;
        public void Pose(Vector3 position, float yaw) { if (native) SpatialAudioBridge.Pose(position + Vector3.up * 1.5f, yaw); }
        private void Remove(string id)
        {
            activeIDs.Remove(id); SpatialAudioBridge.Remove(id);
            if (unitySources.TryGetValue(id, out var source)) { Destroy(source); unitySources.Remove(id); }
        }
        private void OnApplicationPause(bool paused)
        {
            SpatialAudioBridge.Pause(paused);
            foreach (var source in unitySources.Values) if (source != null) { if (paused) source.Pause(); else source.UnPause(); }
        }
        private void OnDestroy()
        {
            SpatialAudioBridge.Stop();
            foreach (var clip in clips) Destroy(clip);
        }
    }
}
