using UnityEngine;

namespace Lantern.Unity.Presentation
{
    public enum VoiceState { Idle, Listening, Thinking, Speaking }

    // A quiet ring around the existing microphone; no new permanent controls or text.
    public sealed class VoiceIndicator : MonoBehaviour
    {
        private ControlGlyph ring;
        private AccessibleAction accessible;
        public VoiceState State { get; private set; }
        internal void Initialize(HudElements ui, WorldPalette palette, AccessibleAction action)
        {
            accessible = action;
            var rect = ui.Rect("Voice activity ring",transform,new Vector2(-.09f,-.09f),new Vector2(1.09f,1.09f));
            ring = rect.gameObject.AddComponent<ControlGlyph>();
            ring.Shape = ControlGlyph.Kind.Ring;
            ring.color = palette.Accent; ring.raycastTarget = false;
            Set(VoiceState.Idle);
        }
        public void Set(VoiceState state)
        {
            State = state;
            if (ring == null) return;
            ring.gameObject.SetActive(state != VoiceState.Idle);
            accessible.Label.text = state switch
            {
                VoiceState.Listening => "Listening. Tap to cancel.",
                VoiceState.Thinking => "Ember is thinking. Tap to cancel.",
                VoiceState.Speaking => "Ember is speaking. Tap to talk.",
                _ => "Talk to Ember"
            };
        }
        private void Update()
        {
            if (ring == null || State == VoiceState.Idle) return;
            var scale = State == VoiceState.Thinking ? 1 + .025f * Mathf.Sin(Time.unscaledTime * 2) : 1;
            ring.transform.localScale = Vector3.one * scale;
        }
    }
}
