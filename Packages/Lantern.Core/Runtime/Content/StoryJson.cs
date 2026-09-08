#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json;
using Newtonsoft.Json.Converters;
using Newtonsoft.Json.Serialization;

namespace Lantern.Core.Content
{
    public static class StoryJson
    {
        public static JsonSerializerSettings Settings() => new JsonSerializerSettings
        {
            ContractResolver = new CamelCasePropertyNamesContractResolver
            { NamingStrategy = new CamelCaseNamingStrategy { ProcessDictionaryKeys = false } },
            Converters = { new StringEnumConverter(new CamelCaseNamingStrategy()) },
            DateFormatHandling = DateFormatHandling.IsoDateFormat,
            DateTimeZoneHandling = DateTimeZoneHandling.Utc,
            NullValueHandling = NullValueHandling.Ignore,
            TypeNameHandling = TypeNameHandling.None
        };

        public static T Read<T>(string json) where T : class => JsonConvert.DeserializeObject<T>(json, Settings()) ?? throw new JsonSerializationException("Content was empty.");
        public static string Write<T>(T value) => JsonConvert.SerializeObject(value, Formatting.Indented, Settings());

        public static void Validate(StoryPack pack, CompanionRoster roster)
        {
            if (string.IsNullOrWhiteSpace(pack.Id) || pack.Version < 1 || !pack.Scenes.Any()) throw new InvalidOperationException("A story needs an ID, version and scene.");
            Unique(pack.Scenes.Select(s => s.Id), "scene");
            Unique(pack.Quests.Select(q => q.Id), "quest");
            Unique(pack.Quests.SelectMany(q => q.Steps).Select(s => s.Id), "step");
            Unique(pack.Dialogues.Select(d => d.Id), "dialogue");
            Unique(roster.Companions.Select(c => c.Id), "companion");
            var entities = pack.Scenes.SelectMany(s => s.Entities).Select(e => e.Id).ToHashSet();
            foreach (var scene in pack.Scenes)
            {
                Unique(scene.Entities.Select(e => e.Id), "entity in " + scene.Id);
                foreach (var entity in scene.Entities)
                {
                    if (entity.DestinationSceneID != null && pack.Scene(entity.DestinationSceneID) == null) throw new InvalidOperationException("Unknown portal destination: " + entity.Id);
                    if (entity.DialogueID != null && pack.Dialogue(entity.DialogueID) == null) throw new InvalidOperationException("Unknown dialogue: " + entity.Id);
                }
            }
            foreach (var step in pack.Quests.SelectMany(q => q.Steps))
            {
                if (!entities.Contains(step.TargetEntityID)) throw new InvalidOperationException("Unknown target: " + step.Id);
                if (step.Goal == QuestGoal.Song && (pack.Song(step.SongSpellID)?.Notes.Count ?? 0) == 0) throw new InvalidOperationException("Missing melody: " + step.Id);
            }
            foreach (var choice in pack.Dialogues.SelectMany(d => d.Choices))
                if (choice.NextDialogueID != null && pack.Dialogue(choice.NextDialogueID) == null) throw new InvalidOperationException("Unknown next dialogue: " + choice.Id);
        }

        private static void Unique(IEnumerable<string> ids, string kind)
        {
            var seen = new HashSet<string>();
            foreach (var id in ids) if (string.IsNullOrWhiteSpace(id) || !seen.Add(id)) throw new InvalidOperationException("Missing or duplicate " + kind + " ID: " + id);
        }
    }
}
