using System;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Lantern.Core.Gameplay;
using Lantern.Unity.Platform;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace Lantern.Unity.Companion
{
    // One speech owner coordinates server audio, microphone capture and the offline native fallback.
    public sealed class CompanionVoice : MonoBehaviour
    {
        private AppleSpeech fallback;
        private CompanionConnection connection;
        private ServerMicrophone microphone;
        private SpeechPlayback playback;
        private long active;
        private bool waitingAudio, listening, transcribing, reportedBusy;
        private string reuseReply;
        private CalibrationProfile settings;
        public bool IsListening=>listening||fallback.IsListening;
        public bool IsSpeaking=>waitingAudio||playback.Playing||fallback.IsSpeaking;
        public float SpeechLevel=>playback.Level;
        public bool Audible=>playback.Playing||fallback.IsSpeaking;
        public bool Processing=>waitingAudio&&!playback.Playing;
        public event Action<string> Recognized,Partial,Failed;
        public event Action<bool> BusyChanged;
        public void Initialize(AppleSpeech native,CompanionConnection server,CalibrationProfile profile)
        {
            fallback=native;connection=server;settings=profile;
            microphone=new GameObject("Microphone").AddComponent<ServerMicrophone>();microphone.transform.SetParent(transform);
            playback=gameObject.AddComponent<SpeechPlayback>();playback.SetVolume((float)profile.NarrationVolume);
            fallback.Recognized+=words=>Recognized?.Invoke(words);fallback.Partial+=words=>Partial?.Invoke(words);fallback.Failed+=words=>Failed?.Invoke(words);fallback.BusyChanged+=_=>RefreshBusy();
            microphone.Chunk+=(id,pcm)=>connection.Send(new{type="audio",id,pcm});microphone.Failed+=Failure;
            connection.Message+=Receive;
            connection.ConnectionChanged+=connected=>{if(!connected&&active!=0){Stop();Failed?.Invoke("Ember's server connection paused. You can still explore and use the local voice.");}};
        }
        public void Listen()
        {
            Stop();
            if(!connection.Connected){fallback.Listen();return;}
            active=connection.NextId();listening=true;connection.Send(new{type="listen",id=active});microphone.StartListening(active);RefreshBusy();
        }
        public void Speak(string text)
        {
            if(reuseReply==text){reuseReply=null;RefreshBusy();return;}
            Stop();
            if(!connection.Connected){fallback.Speak(text);return;}
            active=connection.NextId();waitingAudio=true;RefreshBusy();_ = NarrateAsync(active,text);
        }
        private async Task NarrateAsync(long id,string text)
        {
            try {await connection.RequestAsync(id,"speak",text,destroyCancellationToken);}
            catch(OperationCanceledException){if(id==active){waitingAudio=false;playback.Stop();fallback.Speak(text);}}
            catch(HttpRequestException){if(id==active){waitingAudio=false;playback.Stop();fallback.Speak(text);}}
        }
        public void BeginReply(long id){Stop();active=id;waitingAudio=true;RefreshBusy();}
        public void ReuseReply(string text){reuseReply=text;}
        public void Stop()
        {
            if(active!=0)connection.Cancel(active);
            active=0;waitingAudio=listening=transcribing=false;reuseReply=null;microphone?.Stop();playback?.Stop();fallback?.Stop();RefreshBusy();
        }
        private void Receive(JObject value)
        {
            var id=value.Value<long?>("id")??0;if(id!=active)return;
            switch(value.Value<string>("type"))
            {
                case "transcribing":transcribing=true;microphone.Stop();listening=false;waitingAudio=true;break;
                case "transcript":transcribing=false;microphone.Stop();listening=waitingAudio=false;RefreshBusy();Recognized?.Invoke(value.Value<string>("text")??"");break;
                case "audio":
                    try {playback.Enqueue(Convert.FromBase64String(value.Value<string>("wav")));}
                    catch(Exception error)when(error is FormatException||error is System.IO.InvalidDataException){Failure("I couldn't play that answer. Please try again.");}break;
                case "done":waitingAudio=false;break;
                case "idle":Stop();Failed?.Invoke("I'm here when you're ready. Tap my microphone to talk again.");break;
                case "cancelled":Stop();break;
                case "error":
                    var wasListening=listening||transcribing;waitingAudio=transcribing=false;microphone.Stop();listening=false;
                    if(wasListening)Failed?.Invoke(value.Value<string>("text")??"Please tap my microphone and try again.");break;
            }
            RefreshBusy();
        }
        private void Failure(string message){Stop();Failed?.Invoke(message);}
        private void RefreshBusy(){if(fallback==null||playback==null)return;var busy=IsListening||IsSpeaking;if(busy!=reportedBusy){reportedBusy=busy;BusyChanged?.Invoke(busy);}}
        private void Update()=>RefreshBusy();
        private void OnApplicationPause(bool paused){if(paused)Stop();}
        private void OnDestroy(){if(connection!=null)connection.Message-=Receive;Stop();}
    }
}
