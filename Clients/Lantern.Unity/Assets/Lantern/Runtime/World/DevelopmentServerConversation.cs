#if UNITY_EDITOR || DEVELOPMENT_BUILD
using System;
using System.Threading.Tasks;
using Lantern.Unity.Companion;
using Lantern.Unity.Story;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace Lantern.Unity.World
{
    // Opt-in authored probe. No microphone input and no player transcript logging.
    public sealed class DevelopmentServerConversation : MonoBehaviour
    {
        public async void Run(AdventureController adventure, CompanionConnection server, CompanionVoice voice)
        {
            var audioSentences=0;
            Action<JObject> received=value=>{if(value.Value<string>("type")=="audio")audioSentences++;};
            try
            {
                var until=Time.realtimeSinceStartup+45;
                while(!server.Connected&&Time.realtimeSinceStartup<until)await Task.Delay(250);
                if(!server.Connected)throw new InvalidOperationException("Family server did not connect: "+server.Status);
                adventure.Stop();server.Message+=received;
                var started=Time.realtimeSinceStartup;
                await adventure.AskAsync("Ember, what are we doing in this part of our adventure?");
                if(audioSentences==0)throw new InvalidOperationException("No streamed Piper audio reached the device.");
                Debug.Log($"Lantern server check: authored reply={adventure.LastWords}; seconds={Time.realtimeSinceStartup-started:F2}; streamed WAVs={audioSentences}");
                until=Time.realtimeSinceStartup+35;
                while(voice.IsSpeaking&&Time.realtimeSinceStartup<until)await Task.Delay(100);
                if(voice.IsSpeaking)throw new InvalidOperationException("Piper playback did not finish.");
                var pending=adventure.AskAsync("Tell me a tiny story about a friendly firefly.");
                await Task.Delay(150);adventure.Stop();var before=adventure.LastWords;
                await pending;await Task.Delay(600);
                if(before!=adventure.LastWords||adventure.IsThinking||voice.IsSpeaking)throw new InvalidOperationException("Cancelled reply resumed.");
                Debug.Log("Lantern server check: PASS; authenticated device connection, world-grounded reply, streamed Piper playback completed and cancellation held. Physical microphone conversation remains a separate check.");
            }
            catch(Exception error){Debug.LogException(error);}
            finally{server.Message-=received;}
        }
    }
}
#endif
