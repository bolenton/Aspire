using System;
using System.Runtime.InteropServices;
using Lantern.Core.Gameplay;
using Newtonsoft.Json;
using UnityEngine;

namespace Lantern.Unity.Platform
{
    public sealed class AppleSpeech : MonoBehaviour
    {
        private sealed class Message { public string kind; public string text; public int request; }
        private int request;
        public bool IsListening { get; private set; }
        public bool IsSpeaking { get; private set; }
        public event Action<string> Recognized, Partial, Failed;
        public event Action<bool> BusyChanged;
        public bool Available => Application.platform == RuntimePlatform.IPhonePlayer;
        private CalibrationProfile profile;
        public void Initialize(CalibrationProfile calibration)
        {
            profile = calibration;
            gameObject.name = "Lantern Apple speech";
#if UNITY_IOS && !UNITY_EDITOR
            LanternSpeechInitialize(gameObject.name);
#endif
        }
        public void Speak(string text)
        {
            Stop();
            if (!Available) return;
            IsSpeaking = true; BusyChanged?.Invoke(true);
#if UNITY_IOS && !UNITY_EDITOR
            LanternSpeak(text, (float)profile.SpeechRate, (float)profile.SpeechPitch, (float)profile.NarrationVolume, request);
#endif
        }
        public void Listen()
        {
            Stop();
            if (!Available) { Failed?.Invoke("Voice is available in the iPhone and iPad build. You can use the buttons here."); return; }
            IsListening = true; BusyChanged?.Invoke(true);
#if UNITY_IOS && !UNITY_EDITOR
            LanternListen(request);
#endif
        }
        public void Stop()
        {
            request++;
#if UNITY_IOS && !UNITY_EDITOR
            LanternSpeechStop();
#endif
            IsListening = IsSpeaking = false;
            BusyChanged?.Invoke(false);
        }
        // Native callbacks are delivered on Unity's main thread. Old speech cannot revive old UI.
        public void OnSpeechMessage(string json)
        {
            var message = JsonConvert.DeserializeObject<Message>(json);
            if (message == null || message.request != request) return;
            if (message.kind == "partial") { Partial?.Invoke(message.text); return; }
            IsListening = IsSpeaking = false; BusyChanged?.Invoke(false);
            if (message.kind == "recognized") Recognized?.Invoke(message.text);
            else if (message.kind == "error") Failed?.Invoke(message.text);
        }
        private void OnApplicationPause(bool paused) { if (paused) Stop(); }
        private void OnDestroy() => Stop();
#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")] private static extern void LanternSpeechInitialize(string receiver);
        [DllImport("__Internal")] private static extern void LanternSpeak(string text, float rate, float pitch, float volume, int request);
        [DllImport("__Internal")] private static extern void LanternListen(int request);
        [DllImport("__Internal")] private static extern void LanternSpeechStop();
#endif
    }
}
