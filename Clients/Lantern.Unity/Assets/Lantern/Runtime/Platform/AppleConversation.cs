using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Lantern.Core.Companion;
using Lantern.Core.Content;
using Lantern.Core.Gameplay;
using Newtonsoft.Json;
using UnityEngine;

namespace Lantern.Unity.Platform
{
    public sealed class AppleConversation : MonoBehaviour, IConversationProvider
    {
        private sealed class Message { public int request; public string status; public string text; }
        private readonly List<ConversationExchange> recent = new List<ConversationExchange>();
        private CalibrationProfile settings;
        private TaskCompletionSource<string> pending;
        private int requestID;
        private long revision = -1;
        public string LastOutcome { get; private set; } = "idle";
        public void Initialize(CalibrationProfile profile) { settings = profile; gameObject.name = "Lantern conversation"; }
        public int Availability
        {
            get
            {
#if UNITY_IOS && !UNITY_EDITOR
                return LanternConversationAvailability();
#else
                return 1;
#endif
            }
        }
        public string Status => Availability switch
        {
            0 => "On-device conversation is ready.",
            1 => "On-device conversation needs iOS 26 or later on a supported device.",
            2 => "This device supports Ember's built-in stories and guidance.",
            3 => "Turn on Apple Intelligence in the iPad or iPhone settings to enable on-device conversation.",
            4 => "Apple's language model is still getting ready. Built-in stories and guidance work now.",
            _ => "On-device conversation is unavailable for this language. Built-in stories and guidance work now."
        };

        public async Task<string> ReplyAsync(string utterance, CompanionDefinition companion, WorldObservation world, CancellationToken cancellation)
        {
            cancellation.ThrowIfCancellationRequested();
            if (!settings.OnDeviceConversation || Availability != 0) { LastOutcome = "unavailable"; return ""; }
            Cancel();
            if (revision != world.Revision) { recent.Clear(); revision = world.Revision; }
            var id = ++requestID;
            var completion = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            pending = completion;
            LastOutcome = "thinking";
            using var registration = cancellation.Register(() =>
            {
                completion.TrySetCanceled();
#if UNITY_IOS && !UNITY_EDITOR
                LanternConversationCancel(id);
#endif
            });
            try
            {
                var payload = JsonConvert.SerializeObject(new { instructions = ConversationPrompt.Instructions, prompt = ConversationPrompt.Create(utterance, companion, world, recent) });
#if UNITY_IOS && !UNITY_EDITOR
                LanternConversationReply(gameObject.name, payload, id);
#else
                completion.TrySetResult("");
#endif
                var reply = await completion.Task;
                cancellation.ThrowIfCancellationRequested();
                if (reply.Length > 0)
                {
                    recent.Add(new ConversationExchange { Player = utterance.Length > 500 ? utterance.Substring(0,500) : utterance, Companion = reply });
                    if (recent.Count > 4) recent.RemoveAt(0);
                }
                return reply;
            }
            catch (OperationCanceledException) { LastOutcome = "cancelled"; throw; }
            finally { if (ReferenceEquals(pending, completion)) pending = null; }
        }
        public void OnConversationMessage(string json)
        {
            var message = JsonConvert.DeserializeObject<Message>(json);
            if (message == null || message.request != requestID || pending == null) return;
            LastOutcome = message.status;
            // Excessive output is rejected rather than cutting speech in the middle of a sentence.
            var words = message.text ?? "";
            pending.TrySetResult(message.status == "ready" && words.Length <= 650 ? words.Trim() : "");
        }
        public void ForgetConversation() { Cancel(); recent.Clear(); }
        private void Cancel()
        {
#if UNITY_IOS && !UNITY_EDITOR
            LanternConversationCancel(requestID);
#endif
            requestID++;
            pending?.TrySetCanceled(); pending = null;
        }
        private void OnApplicationPause(bool paused) { if (paused) ForgetConversation(); }
        private void OnDestroy() => ForgetConversation();
#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")] private static extern int LanternConversationAvailability();
        [DllImport("__Internal")] private static extern void LanternConversationReply(string receiver, string payload, int request);
        [DllImport("__Internal")] private static extern void LanternConversationCancel(int request);
#endif
    }
}
