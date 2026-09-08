#nullable enable
using Lantern.Core.Content;

namespace Lantern.Core.Companion
{
    public static class CompanionSmallTalk
    {
        public static string Reply(string utterance, CompanionDefinition friend, WorldObservation world)
        {
            var words = CompanionCommands.Normalize(utterance);
            bool Has(string phrase) => CompanionCommands.Contains(words, phrase);
            if (Has("scared") || Has("worried") || Has("afraid")) return "We can stop right here. There is no hurry, and you can ask your grown-up to join us whenever you like.";
            if (Has("frustrated") || Has("hard") || Has("sad")) return "It's okay to take a break. When you're ready, we can try one little step together.";
            if (Has("joke") || Has("funny")) return "What does a fox put on toast? A little jam and a lot of paw prints!";
            if (Has("story")) return "Once a tiny lantern thought its light was too small. Then a lost firefly saw it and found the way home. Even a little light can help.";
            if (Has("thank you") || Has("thanks")) return "You're welcome! Exploring together is lovely.";
            if (Has("hello") || Has("hi") || Has("hey")) return $"Hello! I'm {friend.Name}. Shall we listen to the meadow or find our next little adventure?";
            if (Has("name") || Has("who are you")) return $"I'm {friend.Name}, your {friend.Species} friend in Lantern. I like little adventures with plenty of time to explore.";
            return $"{friend.SpeechStyle.Exclamation} We can share a little story or a joke, or explore together. {world.Hint}";
        }
    }
}
