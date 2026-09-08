#if UNITY_EDITOR || DEVELOPMENT_BUILD
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Lantern.Unity.Companion;
using Lantern.Unity.Presentation;
using Lantern.Unity.Story;
using UnityEngine;
using UnityEngine.AI;
using UnityEngine.EventSystems;

namespace Lantern.Unity.World
{
    // A separate verification save; logs timing/frame counts, never microphone content.
    public sealed class DevelopmentVoiceMode : MonoBehaviour
    {
        private readonly Dictionary<string,List<float>> samples=new Dictionary<string,List<float>>();
        private string phase;
        private bool suspended;
        private void Update()
        {
            if(phase==null || suspended)return;
            if(!samples.TryGetValue(phase,out var frames))samples[phase]=frames=new List<float>();
            frames.Add(Time.unscaledDeltaTime*1000);
        }
        private void OnApplicationPause(bool paused)=>suspended=paused;
        public async void Run(AdventureController adventure,CompanionConnection server,CompanionVoice voice,FoxHollowScene world,AdventureHud hud)
        {
            var start=world.Player.transform.position;var rotation=world.Player.transform.rotation;
            try
            {
                await Until(()=>server.Connected,40,"Family server did not connect");
                adventure.Stop();phase="baseline";await Task.Delay(3000);
                phase="voice activation";var began=Time.realtimeSinceStartup;
                adventure.SetVoiceMode(true);
                await Until(()=>voice.IsListening && voice.MicrophoneFrames>=5,25,"Native microphone did not produce PCM frames; check microphone permission");
                Debug.Log($"Lantern voice mode: microphone ready and streaming in {Time.realtimeSinceStartup-began:F2}s; frames={voice.MicrophoneFrames}");
                phase=null;ScreenCapture.CaptureScreenshot("lantern-voice-listening.png");await Task.Delay(500);
                phase="voice and movement";
                var movementStart=world.Player.transform.position;
                var touch=hud.GetComponentInChildren<TouchMovement>();
                var pointer=new PointerEventData(EventSystem.current){pointerId=81,position=new Vector2(Screen.width*.25f,Screen.height*.35f)};
                touch.OnPointerDown(pointer);pointer.position+=Vector2.down*Screen.height*.06f;touch.OnDrag(pointer);
                await Task.Delay(700);touch.OnPointerUp(pointer);
                var distance=Vector3.Distance(movementStart,world.Player.transform.position);
                if(distance<.25f || !adventure.VoiceModeActive)throw new InvalidOperationException("Movement failed or turned voice mode off");
                adventure.Stop();
                if(!adventure.VoiceModeActive)throw new InvalidOperationException("Stopping movement turned voice mode off");
                phase="reply and resume";
                adventure.Say("Voice mode is still on. I'll listen again after this sentence.");
                await Until(()=>!voice.IsSpeaking,30,"Piper playback did not finish");
                var before=voice.MicrophoneFrames;began=Time.realtimeSinceStartup;
                await Until(()=>voice.IsListening && voice.MicrophoneFrames>before+4,10,"Listening did not resume automatically");
                Debug.Log($"Lantern voice mode: warm microphone resumed in {Time.realtimeSinceStartup-began:F2}s; movement={distance:F2}m; mode remained on");
                phase=null;ScreenCapture.CaptureScreenshot("lantern-voice-resumed.png");await Task.Delay(500);
                phase="voice active";await Task.Delay(5000);
                adventure.SetVoiceMode(false);phase="voice off";
                before=voice.MicrophoneFrames;await Task.Delay(1200);
                if(adventure.VoiceModeActive || voice.IsListening || voice.MicrophoneFrames!=before)throw new InvalidOperationException("Voice mode continued recording after explicit off");
                Debug.Log("Lantern voice mode: PASS; native PCM capture, movement while active, reply-to-listening continuation and explicit-off capture shutdown. Recorded words were not logged.");
            }
            catch(Exception error){Debug.LogException(error);}
            finally
            {
                phase=null;adventure.SetVoiceMode(false);world.Player.Stop();
                world.Player.GetComponent<NavMeshAgent>().Warp(start);world.Player.transform.rotation=rotation;
                foreach(var item in samples)
                {
                    var sorted=item.Value.OrderBy(x=>x).ToArray();if(sorted.Length==0)continue;
                    Debug.Log($"Lantern voice frame sample: {item.Key}; median={sorted[sorted.Length/2]:F2}ms; p95={sorted[Math.Min(sorted.Length-1,(int)(sorted.Length*.95))]:F2}ms; max={sorted[^1]:F2}ms; over50ms={sorted.Count(x=>x>50)}; frames={sorted.Length}. Development main-thread sample only.");
                }
            }
        }
        private static async Task Until(Func<bool> ready,float seconds,string failure)
        {
            var until=Time.realtimeSinceStartup+seconds;
            while(!ready() && Time.realtimeSinceStartup<until)await Task.Delay(50);
            if(!ready())throw new InvalidOperationException(failure);
        }
    }
}
#endif
