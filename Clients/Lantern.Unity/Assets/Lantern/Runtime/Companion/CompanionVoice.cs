using System;
using System.Net.Http;
using System.Threading.Tasks;
using Lantern.Core.Gameplay;
using Lantern.Unity.Platform;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace Lantern.Unity.Companion
{
    // A voice mode owns one warm microphone session; individual turns only gate its input.
    public sealed class CompanionVoice : MonoBehaviour
    {
        private AppleSpeech fallback;
        private CompanionConnection connection;
        private ServerMicrophone microphone;
        private SpeechPlayback playback;
        private long active;
        private bool waitingAudio, listening, preparing, transcribing, reportedBusy, modeActive;
        private string reuseReply;
        public bool IsListening => listening || fallback.IsListening;
        public bool IsSpeaking => waitingAudio || preparing || playback.Playing || fallback.IsSpeaking;
        public bool Audible => playback.Playing || fallback.IsSpeaking;
        public bool Processing => (waitingAudio || preparing) && !playback.Playing;
        public float SpeechLevel => playback.Level;
        public float InputLevel => microphone.Level;
        public long MicrophoneFrames => microphone.Frames;
        public event Action<string> Recognized, Partial, Failed;
        public event Action<bool> BusyChanged;

        public void Initialize(AppleSpeech native, CompanionConnection server, CalibrationProfile profile)
        {
            fallback = native; connection = server;
            microphone = new GameObject("Microphone").AddComponent<ServerMicrophone>();
            microphone.transform.SetParent(transform);
            playback = gameObject.AddComponent<SpeechPlayback>();
            playback.SetVolume((float)profile.NarrationVolume);
            playback.Failed+=Failure;
            fallback.Recognized += words => Recognized?.Invoke(words);
            fallback.Partial += words => Partial?.Invoke(words);
            fallback.Failed += words => Failed?.Invoke(words);
            fallback.BusyChanged += _ => RefreshBusy();
            microphone.Chunk += (id, pcm) => connection.Send(new { type = "audio", id, pcm });
            microphone.Ready += id => { if(id == active) { preparing=false; listening=true; RefreshBusy(); } };
            microphone.Failed += Failure;
            connection.Message += Receive;
            connection.ConnectionChanged += connected =>
            {
                if(!connected && active != 0) { Stop(); Failed?.Invoke("The connection paused. Voice mode will try again."); }
            };
        }
        public void SetMode(bool value)
        {
            modeActive=value;
            if(!value) { Stop(); microphone.CloseSession(); }
        }
        public void Listen()
        {
            Stop();
            if(!connection.Connected) { microphone.CloseSession(); fallback.Listen(); return; }
            active=connection.NextId(); preparing=true;
            connection.Send(new { type="listen", id=active });
            microphone.StartListening(active);
            RefreshBusy();
        }
        public void Speak(string text)
        {
            if(reuseReply == text) { reuseReply=null; RefreshBusy(); return; }
            Stop();
            if(!connection.Connected) { microphone.CloseSession(); fallback.Speak(text); return; }
            active=connection.NextId(); waitingAudio=true; RefreshBusy();
            _ = NarrateAsync(active,text);
        }
        private async Task NarrateAsync(long id, string text)
        {
            try { await connection.RequestAsync(id,"speak",text,destroyCancellationToken); }
            catch(Exception error) when(error is OperationCanceledException || error is HttpRequestException)
            {
                if(id != active) return;
                waitingAudio=false; playback.Stop(); microphone.CloseSession(); fallback.Speak(text);
            }
        }
        public void BeginReply(long id) { Stop(); active=id; waitingAudio=true; RefreshBusy(); }
        public void ReuseReply(string text) => reuseReply=text;
        public void Stop()
        {
            if(active != 0) connection.Cancel(active);
            active=0; waitingAudio=listening=preparing=transcribing=false; reuseReply=null;
            microphone?.Stop(); playback?.Stop(); fallback?.Stop(); RefreshBusy();
        }
        private void Receive(JObject value)
        {
            var id=value.Value<long?>("id") ?? 0;
            if(id != active) return;
            switch(value.Value<string>("type"))
            {
                case "transcribing":
                    transcribing=true; microphone.Stop(); listening=preparing=false; waitingAudio=true; break;
                case "transcript":
                    transcribing=false; microphone.Stop(); listening=waitingAudio=preparing=false;
                    RefreshBusy(); Recognized?.Invoke(value.Value<string>("text") ?? ""); break;
                case "audio":
                    playback.Enqueue(value.Value<string>("wav"), id); break;
                case "done": waitingAudio=false; break;
                case "idle": Stop(); break; // Silence ends a turn, never the user's voice mode.
                case "cancelled": Stop(); break;
                case "error":
                    var inputFailed=listening || preparing || transcribing;
                    waitingAudio=transcribing=preparing=listening=false; microphone.Stop();
                    if(inputFailed) Failed?.Invoke(value.Value<string>("text") ?? "I'm still here. Please try again.");
                    break;
            }
            RefreshBusy();
        }
        private void Failure(string message) { Stop(); Failed?.Invoke(message); }
        private void RefreshBusy()
        {
            if(fallback == null || playback == null) return;
            var busy=IsListening || IsSpeaking;
            if(busy != reportedBusy) { reportedBusy=busy; BusyChanged?.Invoke(busy); }
        }
        private void Update() => RefreshBusy();
        private void OnApplicationPause(bool paused) { if(paused) { Stop(); microphone.CloseSession(); } }
        private void OnDestroy()
        {
            if(connection != null) connection.Message-=Receive;
            Stop(); microphone?.CloseSession();
        }
    }
}
