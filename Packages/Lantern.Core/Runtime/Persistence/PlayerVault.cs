#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using Lantern.Core.Content;
using Lantern.Core.Gameplay;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Lantern.Core.Persistence
{
    public enum MemoryKind { Choice, Favorite, Discovery, QuestCompleted }
    public sealed class MemoryEvent
    {
        public DateTime Date { get; set; } = DateTime.UtcNow;
        public MemoryKind Kind { get; set; }
        public string Key { get; set; } = "";
        public string Value { get; set; } = "";
        public string SpokenRecap { get; set; } = "";
        public string? CompanionID { get; set; }
    }
    public sealed class MemoryJournal
    {
        public List<MemoryEvent> Events { get; set; } = new List<MemoryEvent>();
        public string? Recall(string key) => Events.LastOrDefault(e => e.Key == key)?.Value;
    }
    public sealed class SaveSlot
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string StoryPackID { get; set; } = "";
        public string CompanionID { get; set; } = "";
        public GameProgress Progress { get; set; } = new GameProgress();
        public DifficultyDirector Difficulty { get; set; } = new DifficultyDirector();
        public MemoryJournal Journal { get; set; } = new MemoryJournal();
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime LastPlayedAt { get; set; } = DateTime.UtcNow;
        // Absent in Swift saves: resume those at the authored scene entrance.
        public WorldPoint? PlayerPosition { get; set; }
        public double BodyYawDegrees { get; set; }
        [JsonExtensionData] public IDictionary<string, JToken> Extra { get; set; } = new Dictionary<string, JToken>();
    }
    public sealed class PlayerVault
    {
        public int SchemaVersion { get; set; } = 1;
        public CalibrationProfile Calibration { get; set; } = new CalibrationProfile();
        public MemoryJournal SharedJournal { get; set; } = new MemoryJournal();
        public List<SaveSlot> Slots { get; set; } = new List<SaveSlot>();
        // Keep avatar customizations intact until the Unity avatar designer is ported.
        public JObject Avatar { get; set; } = new JObject();
        [JsonExtensionData] public IDictionary<string, JToken> Extra { get; set; } = new Dictionary<string, JToken>();

        public SaveSlot CreateSlot(StoryPack pack, CompanionDefinition companion)
        {
            var progress = new GameProgress { StoryPackID = pack.Id, ChosenCompanionID = companion.Id, CurrentSceneID = pack.Scenes.First().Id };
            progress.SelectNextQuest(pack);
            var slot = new SaveSlot { StoryPackID = pack.Id, CompanionID = companion.Id, Progress = progress, Difficulty = DifficultyDirector.For(Calibration) };
            Slots.Add(slot);
            return slot;
        }
        public void Remember(MemoryEvent memory, SaveSlot slot) => (memory.Kind == MemoryKind.Favorite ? SharedJournal : slot.Journal).Events.Add(memory);
    }
}
