using System;
using System.Runtime.InteropServices;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace Lantern.Unity.Companion
{
    public sealed class ServerMicrophone : MonoBehaviour
    {
        private long request;
        public event Action<long,string> Chunk;
        public event Action<string> Failed;
        private void Awake()
        {
            gameObject.name="Lantern server microphone";
#if UNITY_IOS && !UNITY_EDITOR
            LanternMicrophoneInitialize(gameObject.name);
#endif
        }
        public void StartListening(long id)
        {
            request=id;
#if UNITY_IOS && !UNITY_EDITOR
            LanternMicrophoneStart((int)id);
#else
            Failed?.Invoke("Microphone streaming is available in the iPhone and iPad build.");
#endif
        }
        public void Stop()
        {
            request=-1;
#if UNITY_IOS && !UNITY_EDITOR
            LanternMicrophoneStop();
#endif
        }
        public void OnMicrophoneMessage(string json)
        {
            var value=JObject.Parse(json);var id=value.Value<long>("id");if(id!=request)return;
            if(value.Value<string>("type")=="pcm")Chunk?.Invoke(id,value.Value<string>("pcm"));
            else Failed?.Invoke(value.Value<string>("text")??"The microphone paused.");
        }
        private void OnApplicationPause(bool paused){if(paused)Stop();}
        private void OnDestroy()=>Stop();
#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")]private static extern void LanternMicrophoneInitialize(string receiver);
        [DllImport("__Internal")]private static extern void LanternMicrophoneStart(int request);
        [DllImport("__Internal")]private static extern void LanternMicrophoneStop();
#endif
    }
}
