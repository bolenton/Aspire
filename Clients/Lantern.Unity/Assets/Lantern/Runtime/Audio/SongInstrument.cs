using System.Collections;
using System.Collections.Generic;
using System.Threading.Tasks;
using Lantern.Core.Content;
using UnityEngine;

namespace Lantern.Unity.Audio
{
    public sealed class SongInstrument : MonoBehaviour
    {
        public event System.Action<SolfegeNote> NotePlayed;
        private AudioSource source;
        private AudioClip bell;
        public bool IsPlaying=>source!=null && source.isPlaying;
        // The new recorded bell's dominant resonance was measured from its FFT.
        private const float RecordedPitch = 239.6f;
        private static readonly float[] Frequencies = { 261.63f,293.66f,329.63f,349.23f,392,440,493.88f };

        public async Task InitializeAsync()
        {
            source = gameObject.AddComponent<AudioSource>();
            source.spatialBlend = 0; source.volume = .55f;
            var clip = await MeadowAudioClip.LoadAsync("Bell.wav");
            if (this == null) { Destroy(clip); return; }
            bell = clip;
        }
        public void Play(SolfegeNote note)
        {
            StopAllCoroutines(); source.Stop(); PlayNote(note);
        }
        private void PlayNote(SolfegeNote note)
        {
            NotePlayed?.Invoke(note);
            source.pitch = Frequencies[(int)note]/RecordedPitch;
            source.PlayOneShot(bell);
        }
        public void Demonstrate(IReadOnlyList<SolfegeNote> melody)
        {
            StopAllCoroutines(); source.Stop(); StartCoroutine(PlayMelody(melody));
        }
        private IEnumerator PlayMelody(IReadOnlyList<SolfegeNote> melody)
        {
            foreach (var note in melody) { PlayNote(note); yield return new WaitForSeconds(.95f); }
        }
        public void Stop() { StopAllCoroutines(); if (source != null) source.Stop(); }
        private void OnDestroy() { if (bell != null) Destroy(bell); }
    }
}
