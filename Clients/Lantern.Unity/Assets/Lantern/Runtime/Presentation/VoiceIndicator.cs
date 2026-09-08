using UnityEngine;

namespace Lantern.Unity.Presentation
{
    public enum VoiceState { Idle, Listening, Thinking, Speaking }
    public sealed class VoiceIndicator : MonoBehaviour
    {
        private VoiceOrbGraphic orb;
        private AccessibleAction accessible;
        private Transform microphone;
        private RectTransform control;
        private bool activeMode;
        public VoiceState State {get;private set;}
        internal void Initialize(HudElements ui,WorldPalette palette,AccessibleAction action)
        {
            accessible=action;control=(RectTransform)transform;microphone=transform.Find("Symbol");
            var rect=ui.Rect("Active voice orb",transform,new Vector2(-.16f,-.16f),new Vector2(1.16f,1.16f));
            orb=rect.gameObject.AddComponent<VoiceOrbGraphic>();orb.raycastTarget=false;
            Set(VoiceState.Idle,false);
        }
        public void Set(VoiceState state,bool mode)
        {
            if(orb==null)return;
            State=state;activeMode=mode;
            orb.gameObject.SetActive(mode);microphone.gameObject.SetActive(!mode);
            control.sizeDelta=Vector2.one*(mode ? 108:88);
            orb.State=state;
            accessible.Label.text=!mode ? "Voice mode off. Tap to turn on." : state switch
            {
                VoiceState.Listening=>"Voice mode on. Listening to you. Tap to turn off.",
                VoiceState.Thinking=>"Voice mode on. Ember is getting an answer ready. Tap to turn off.",
                VoiceState.Speaking=>"Voice mode on. Ember is speaking. Tap to turn off.",
                _=>"Voice mode on. Ready for our next turn. Tap to turn off."
            };
        }
        public void SetLevel(float value){if(activeMode&&orb!=null)orb.Level=value;}
    }
}
