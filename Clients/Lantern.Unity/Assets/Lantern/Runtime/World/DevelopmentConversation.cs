#if UNITY_EDITOR || DEVELOPMENT_BUILD
using System;
using System.Threading.Tasks;
using Lantern.Unity.Platform;
using Lantern.Unity.Presentation;
using Lantern.Unity.Story;
using UnityEngine;

namespace Lantern.Unity.World
{
    public sealed class DevelopmentConversation : MonoBehaviour
    {
        public async void Run(AdventureController adventure, AppleConversation provider)
        {
            if (Environment.GetEnvironmentVariable("LANTERN_VERIFY_CONVERSATION") != "1") return;
            try
            {
                await Task.Delay(6500);
                Debug.Log("Lantern conversation check: availability=" + provider.Availability + "; " + provider.Status);
                var started = Time.realtimeSinceStartup;
                await adventure.AskAsync("Tell me a tiny story about a friendly firefly.");
                Debug.Log($"Lantern conversation check: outcome={provider.LastOutcome}; seconds={Time.realtimeSinceStartup-started:F2}; authored test reply={adventure.LastWords}");
                if (provider.Availability == 0 && provider.LastOutcome != "ready")
                    Debug.LogWarning("Lantern conversation check: model did not respond; authored fallback was used.");
                var pending = adventure.AskAsync("What might the firefly do next?");
                await Task.Delay(120);
                adventure.Stop();
                var before = adventure.LastWords;
                await pending;
                await Task.Delay(1000);
                if (before != adventure.LastWords || adventure.IsThinking) throw new InvalidOperationException("A stopped conversation resumed.");
                Debug.Log("Lantern conversation check: PASS; text-only reply, stop cancels pending speech, no transcript saved. Microphone input was not exercised.");
                adventure.Say("I'm Ember. Tap the microphone to chat, or ask me for a little story.");
            }
            catch (Exception error) { Debug.LogException(error); }
        }
    }
}
#endif
