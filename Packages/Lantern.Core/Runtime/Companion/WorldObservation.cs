#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using Lantern.Core.Content;

namespace Lantern.Core.Companion
{
    public enum RouteStatus { Unknown, Reachable, Blocked }
    public sealed class ObservedEntity
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public List<string> Aliases { get; set; } = new List<string>();
        public WorldPoint Position { get; set; }
        public bool Available { get; set; }
        public string? LockedExplanation { get; set; }
        public string SoundDescription { get; set; } = "";
        public bool InAwarenessRange { get; set; }
        public RouteStatus Route { get; set; }
        public WorldPoint? NextWaypoint { get; set; }
        public double RouteDistance { get; set; }
    }
    public sealed class WorldObservation
    {
        public long Revision { get; set; }
        public string SceneName { get; set; } = "";
        public WorldPoint PlayerPosition { get; set; }
        public double BodyYawDegrees { get; set; }
        public string Quest { get; set; } = "";
        public string Hint { get; set; } = "";
        public string? TargetID { get; set; }
        public List<ObservedEntity> Entities { get; set; } = new List<ObservedEntity>();
        public ObservedEntity? Target => Entities.FirstOrDefault(e => e.Id == TargetID);
    }
    public static class Guidance
    {
        private static readonly string[] Directions = { "ahead", "ahead and to your right", "to your right", "behind you on the right", "behind you", "behind you on the left", "to your left", "ahead and to your left" };
        public static string Direction(WorldPoint from, WorldPoint to, double bodyYawDegrees)
        {
            var bearing = Math.Atan2(to.X - from.X, to.Z - from.Z) * 180 / Math.PI;
            var relative = ((bearing - bodyYawDegrees) % 360 + 360) % 360;
            return Directions[(int)Math.Floor((relative + 22.5) / 45) % 8];
        }
        public static string DescribeRoute(WorldObservation world, ObservedEntity target)
        {
            if (!target.Available) return target.LockedExplanation ?? $"We cannot use {target.Name} yet.";
            if (target.Route == RouteStatus.Blocked) return $"I cannot find a clear path to {target.Name} from here. Let's stay here and choose another place.";
            if (target.Route != RouteStatus.Reachable) return $"Let me check the path to {target.Name} before we move.";
            if (target.RouteDistance < 2.5) return $"{target.Name} is right here. Tap it when you're ready.";
            var direction = Direction(world.PlayerPosition, target.NextWaypoint ?? target.Position, world.BodyYawDegrees);
            return $"The path to {target.Name} starts {direction}, about {Math.Max(1, (int)Math.Round(target.RouteDistance))} steps away. I can guide you there.";
        }
    }
}
