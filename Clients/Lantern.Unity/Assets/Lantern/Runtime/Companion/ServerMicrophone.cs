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
        public event Action<long> Ready;
        public float Level {get;private set;}
        public long Frames {get;private set;}
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
            request=-1;Level=0;
#if UNITY_IOS && !UNITY_EDITOR
            LanternMicrophoneStop();
#endif
        }
        public void OnMicrophoneMessage(string json)
        {
            var value=JObject.Parse(json);var id=value.Value<long>("id");if(id!=request)return;
            if(value.Value<string>("type")=="pcm"){Level=value.Value<float>("level");Frames++;Chunk?.Invoke(id,value.Value<string>("pcm"));}
            else if(value.Value<string>("type")=="ready")Ready?.Invoke(id);
            else Failed?.Invoke(value.Value<string>("text")??"The microphone paused.");
        }
        public void CloseSession()
        {
            Stop();
#if UNITY_IOS && !UNITY_EDITOR
            LanternMicrophoneShutdown();
#endif
        }
        private void OnApplicationPause(bool paused){if(paused)CloseSession();}
        private void OnDestroy()=>CloseSession();
#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")]private static extern void LanternMicrophoneInitialize(string receiver);
        [DllImport("__Internal")]private static extern void LanternMicrophoneStart(int request);
        [DllImport("__Internal")]private static extern void LanternMicrophoneStop();
        [DllImport("__Internal")]private static extern void LanternMicrophoneShutdown();
#endif
    }
}
