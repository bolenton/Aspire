#nullable enable
using System;
using System.Linq;
using System.Text.RegularExpressions;

namespace Lantern.Core.Companion
{
    // All actions are resolved against the live world before a language model is considered.
    public static class CompanionCommands
    {
        public static string Normalize(string words) => Regex.Replace(Regex.Replace(words.ToLowerInvariant(), "[^a-z ]", " "), @"\s+", " ").Trim();
        public static bool Contains(string words, string phrase) => (" " + words + " ").Contains(" " + Normalize(phrase) + " ");

        public static CompanionReply? Resolve(string utterance, WorldObservation world)
        {
            var words = Normalize(utterance);
            bool Has(string phrase) => Contains(words, phrase);
            if (Has("stop") || Has("pause") || Has("wait")) return new CompanionReply("Stopped. We can take our time.", CompanionAction.Stop);
            var named = world.Entities.FirstOrDefault(e => Has(e.Name) || e.Aliases.Any(Has));
            var target = named ?? world.Target;
            var guide = Has("take me") || Has("guide me") || Has("go to") || Has("walk me") || Has("bring me") || Has("can we visit") || Has("let us visit") || Has("help me walk");
            var direction = Has("where") || Has("direction") || Has("which way") || Has("how do i get") || Has("how do we get");
            // An unknown explicit destination must never silently send the child somewhere else.
            var explicitPlace = Regex.IsMatch(words, @"\b(?:to|where is|where s) (?:the )?\w+") && !Has("to go") && !Has("to do");
            if ((guide || direction) && named == null && explicitPlace)
                return new CompanionReply("I don't know that place in our meadow. Try the oak, river bell, garden, orchard, or Ember.");
            if (guide)
            {
                if (target == null) return new CompanionReply("Let's choose somewhere to explore first.");
                return new CompanionReply(Guidance.DescribeRoute(world, target), target.Available && target.Route == RouteStatus.Reachable ? CompanionAction.GuideToTarget : CompanionAction.None, target.Id);
            }
            if (direction) return new CompanionReply(target == null ? $"We're in {world.SceneName}." : Guidance.DescribeRoute(world, target));
            if (Has("help") || Has("hint") || Has("what next") || Has("what should i do")) return new CompanionReply(world.Hint);
            if (Has("quest") || Has("what are we doing")) return new CompanionReply(world.Quest);
            if (Has("pick it up") || Has("collect it") || Has("sing together") || Has("interact"))
                return new CompanionReply("Let's try it together.", world.Target != null ? CompanionAction.Interact : CompanionAction.None);
            if (Has("look") || Has("listen") || Has("around"))
            {
                var nearby = world.Entities.Where(e => e.Available && e.InAwarenessRange).OrderBy(e => e.Position.DistanceTo(world.PlayerPosition)).Take(3).ToArray();
                return new CompanionReply($"We're in {world.SceneName}. " + (nearby.Length == 0 ? "It's quiet here." : string.Join(". ", nearby.Select(e => e.SoundDescription.Length > 0 ? $"I hear {e.SoundDescription}" : $"{e.Name} is nearby")) + "."));
            }
            return null;
        }
    }
}
