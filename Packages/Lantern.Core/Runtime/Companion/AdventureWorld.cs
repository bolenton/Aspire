#nullable enable
using System.Collections.Generic;
using System.Linq;
using Lantern.Core.Content;
using Lantern.Core.Persistence;

namespace Lantern.Core.Companion
{
    public sealed class AdventureEntity
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public string Description { get; set; } = "";
        public bool Available { get; set; }
        public bool Nearby { get; set; }
        public string Route { get; set; } = "";
        public string Guidance { get; set; } = "";
        public string Interaction { get; set; } = "";
    }
    public sealed class AdventureEvent
    {
        public string Id { get; set; } = "";
        public string Text { get; set; } = "";
    }
    public sealed class AdventureWorld
    {
        public long Revision { get; set; }
        public string AdventureId { get; set; } = "";
        public string Scene { get; set; } = "";
        public string Region { get; set; } = "";
        public string Story { get; set; } = "";
        public string Quest { get; set; } = "";
        public string Objective { get; set; } = "";
        public string TargetId { get; set; } = "";
        public string Activity { get; set; } = "";
        public string Hint { get; set; } = "";
        public List<string> Inventory { get; set; } = new List<string>();
        public List<string> Achievements { get; set; } = new List<string>();
        public List<string> Memories { get; set; } = new List<string>();
        public List<AdventureEvent> Events { get; set; } = new List<AdventureEvent>();
        public List<AdventureEntity> Entities { get; set; } = new List<AdventureEntity>();

        public static AdventureWorld Build(StoryPack pack, SaveSlot slot, WorldObservation observed, string region, string activity)
        {
            var scene = pack.Scene(slot.Progress.CurrentSceneID)!;
            var step = slot.Progress.CurrentStep(pack);
            var completed = pack.Quests.SelectMany(q => q.Steps).Where(s => slot.Progress.CompletedStepIDs.Contains(s.Id)).ToArray();
            return new AdventureWorld
            {
                Revision = observed.Revision, AdventureId = slot.Id, Scene = scene.Name, Region = region,
                Story = scene.SpokenDescription.Resolve(slot.CompanionID), Quest = observed.Quest,
                Objective = step?.Intro.Resolve(slot.CompanionID) ?? "Explore together; all current chapters are complete.",
                TargetId = observed.TargetID ?? "", Activity = activity, Hint = observed.Hint,
                Inventory = slot.Progress.Inventory.Select(id => scene.Entities.FirstOrDefault(e => e.Id == id)?.Name ?? id).ToList(),
                Achievements = pack.Quests.Where(slot.Progress.IsComplete).Select(q => q.Title).ToList(),
                Memories = slot.Journal.Events.Where(e => e.SpokenRecap.Length > 0).Reverse().Take(12).Select(e => e.SpokenRecap).ToList(),
                Events = completed.Reverse().Take(8).Select(s => new AdventureEvent { Id = s.Id, Text = s.Celebration.Resolve(slot.CompanionID) }).Reverse().ToList(),
                Entities = observed.Entities.Select(e => new AdventureEntity
                {
                    Id = e.Id, Name = e.Name, Available = e.Available, Nearby = e.InAwarenessRange,
                    Description = scene.Entities.FirstOrDefault(x => x.Id == e.Id)?.Description ?? e.SoundDescription,
                    Route = e.Route.ToString(), Guidance = Guidance.DescribeRoute(observed,e),
                    Interaction = step?.TargetEntityID == e.Id ? step.Goal.ToString() : "Visit and explore"
                }).ToList()
            };
        }
    }
}
