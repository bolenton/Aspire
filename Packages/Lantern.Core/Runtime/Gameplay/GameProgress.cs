#nullable enable
using System.Collections.Generic;
using System.Linq;
using Lantern.Core.Content;

namespace Lantern.Core.Gameplay
{
    public sealed class GameProgress
    {
        public string StoryPackID { get; set; } = "";
        public string? ChosenCompanionID { get; set; }
        public string CurrentSceneID { get; set; } = "";
        public string? ActiveQuestID { get; set; }
        public List<string> CompletedStepIDs { get; set; } = new List<string>();
        public HashSet<string> Flags { get; set; } = new HashSet<string>();
        public List<string> Inventory { get; set; } = new List<string>();

        public QuestStep? CurrentStep(StoryPack pack) => pack.Quest(ActiveQuestID)?.Steps.FirstOrDefault(s => !CompletedStepIDs.Contains(s.Id));
        public bool IsComplete(QuestDefinition quest) => quest.Steps.All(s => CompletedStepIDs.Contains(s.Id));
        public IEnumerable<QuestDefinition> AvailableQuests(StoryPack pack) => pack.Quests.Where(q =>
            (q.RequiresCompanion == null || q.RequiresCompanion == ChosenCompanionID) &&
            (q.RequiresFlag == null || Flags.Contains(q.RequiresFlag)));
        public bool IsAvailable(EntityDefinition entity) => entity.RequiresFlag == null || Flags.Contains(entity.RequiresFlag);
        public bool IsPerceivable(EntityDefinition entity, CompanionDefinition companion) =>
            (entity.RequiresCompanion == null || entity.RequiresCompanion == companion.Id) &&
            (entity.RequiresAbility == null || companion.HasAbility(entity.RequiresAbility));

        // Physical proximity and song performance are verified by the client before calling this.
        // Explicit goals prevent a reach event from completing a conversation or song.
        public QuestStep? Complete(StoryPack pack, string entityID, QuestGoal goal)
        {
            var step = CurrentStep(pack);
            var entity = pack.Scene(CurrentSceneID)?.Entities.FirstOrDefault(e => e.Id == entityID);
            if (step == null || entity == null || step.TargetEntityID != entityID || step.Goal != goal || !IsAvailable(entity)) return null;
            CompletedStepIDs.Add(step.Id);
            if (step.SetsFlag != null) Flags.Add(step.SetsFlag);
            if (goal == QuestGoal.Collect && !Inventory.Contains(entityID)) Inventory.Add(entityID);
            return step;
        }

        public void SelectNextQuest(StoryPack pack) => ActiveQuestID = AvailableQuests(pack).FirstOrDefault(q => !IsComplete(q))?.Id;

        public bool Travel(StoryPack pack, EntityDefinition portal)
        {
            if (portal.Kind != EntityKind.Portal || !IsAvailable(portal) || portal.DestinationSceneID == null || pack.Scene(portal.DestinationSceneID) == null) return false;
            CurrentSceneID = portal.DestinationSceneID;
            return true;
        }
    }
}
