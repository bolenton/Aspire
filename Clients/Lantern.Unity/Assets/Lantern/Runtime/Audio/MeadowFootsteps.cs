using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;

namespace Lantern.Unity.Audio
{
    public sealed class MeadowFootsteps : MonoBehaviour
    {
        private readonly List<AudioClip> clips = new List<AudioClip>();
        private AudioSource source;
        private Vector3 previous;
        private float distance;
        private int next;

        public async Task InitializeAsync()
        {
            source = gameObject.AddComponent<AudioSource>();
            source.spatialBlend = .3f; source.volume = .38f; source.dopplerLevel = 0;
            for (var i=0;i<4;i++)
            {
                var clip = await MeadowAudioClip.LoadAsync("Footstep"+i+".wav");
                if (this == null) { Destroy(clip); return; }
                clips.Add(clip);
            }
            previous = transform.position;
        }
        private void Update()
        {
            if (clips.Count < 4) return;
            var moved = Vector3.Distance(transform.position,previous);
            previous = transform.position;
            if (moved > .5f) { distance = 0; return; }
            distance += moved;
            if (distance < .68f) return;
            distance = 0;
            source.PlayOneShot(clips[next++%clips.Count]);
        }
        private void OnDestroy() { foreach (var clip in clips) Destroy(clip); }
    }
}
