#nullable enable
using System.Collections.Generic;
using System.Linq;

namespace Lantern.Core.Content
{
    public enum EntityKind { Companion, Character, Landmark, Item, Portal }
    public enum QuestGoal { Reach, Collect, Talk, Song }
    public enum SolfegeNote { Do, Re, Mi, Fa, Sol, La, Ti }

    public sealed class StoryPack
    {
        public const string CompanionPlaceholder = "@companion";
        public string Id { get; set; } = "";
        public string Title { get; set; } = "";
        public int Version { get; set; }
        public List<string>? CompanionIDs { get; set; }
        public List<CompanionDefinition> Companions { get; set; } = new List<CompanionDefinition>();
        public List<RegionDefinition> Regions { get; set; } = new List<RegionDefinition>();
        public List<QuestDefinition> Quests { get; set; } = new List<QuestDefinition>();
        public List<DialogueNode> Dialogues { get; set; } = new List<DialogueNode>();
        public List<SongSpell> SongSpells { get; set; } = new List<SongSpell>();
        public IEnumerable<SceneDefinition> Scenes => Regions.SelectMany(r => r.Scenes);
        public SceneDefinition? Scene(string id) => Scenes.FirstOrDefault(s => s.Id == id);
        public QuestDefinition? Quest(string? id) => Quests.FirstOrDefault(q => q.Id == id);
        public DialogueNode? Dialogue(string? id) => Dialogues.FirstOrDefault(d => d.Id == id);
        public SongSpell? Song(string? id) => SongSpells.FirstOrDefault(s => s.Id == id);
    }

    public sealed class RegionDefinition
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public int DifficultyTier { get; set; }
        public string NewMechanic { get; set; } = "";
        public List<SceneDefinition> Scenes { get; set; } = new List<SceneDefinition>();
    }

    public sealed class SceneDefinition
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public FlavoredText SpokenDescription { get; set; } = "";
        public string Environment { get; set; } = "forest";
        public List<SoundSpec> Ambience { get; set; } = new List<SoundSpec>();
        public List<EntityDefinition> Entities { get; set; } = new List<EntityDefinition>();
    }

    public sealed class EntityDefinition
    {
        public string Id { get; set; } = "";
        public EntityKind Kind { get; set; }
        public string Name { get; set; } = "";
        public List<string> VoiceAliases { get; set; } = new List<string>();
        public string Description { get; set; } = "";
        // Legacy authoring coordinates. Runtime guidance receives live positions instead.
        public WorldPoint Position { get; set; }
        public SoundSpec? Sound { get; set; }
        public VisualSpec? Visual { get; set; }
        public string? DialogueID { get; set; }
        public string? RequiresFlag { get; set; }
        public FlavoredText? LockedExplanation { get; set; }
        public string? DestinationSceneID { get; set; }
        public string? RequiresCompanion { get; set; }
        public string? RequiresAbility { get; set; }
        public FlavoredText? SenseLine { get; set; }
        public string? HiddenTease { get; set; }
    }

    public sealed class SoundSpec
    {
        public string Asset { get; set; } = "";
        public bool Loops { get; set; } = true;
        public double Volume { get; set; } = 1;
        public double NearRadius { get; set; } = 1;
        public double FarRadius { get; set; } = 20;
        public string? SpokenDescription { get; set; }
    }

    public sealed class VisualSpec
    {
        public string Shape { get; set; } = "sphere";
        public string ColorHex { get; set; } = "#FFD24A";
        public double Scale { get; set; } = 1;
        public double Glow { get; set; } = 1;
        public string? AssetName { get; set; }
    }

    public sealed class QuestDefinition
    {
        public string Id { get; set; } = "";
        public string Title { get; set; } = "";
        public FlavoredText SpokenSummary { get; set; } = "";
        public string? RequiresCompanion { get; set; }
        public string? RequiresFlag { get; set; }
        public List<QuestStep> Steps { get; set; } = new List<QuestStep>();
    }

    public sealed class QuestStep
    {
        public string Id { get; set; } = "";
        public QuestGoal Goal { get; set; }
        public string TargetEntityID { get; set; } = "";
        public string? SongSpellID { get; set; }
        public FlavoredText Intro { get; set; } = "";
        public FlavoredText Celebration { get; set; } = "";
        public List<FlavoredText> HintLadder { get; set; } = new List<FlavoredText>();
        public string? SetsFlag { get; set; }
    }

    public sealed class DialogueNode
    {
        public string Id { get; set; } = "";
        public string Speaker { get; set; } = "";
        public FlavoredText Line { get; set; } = "";
        public List<DialogueChoice> Choices { get; set; } = new List<DialogueChoice>();
    }

    public sealed class DialogueChoice
    {
        public string Id { get; set; } = "";
        public FlavoredText Text { get; set; } = "";
        public string? NextDialogueID { get; set; }
        public string? MemoryKey { get; set; }
        public string? MemoryValue { get; set; }
        public string? RequiresCompanion { get; set; }
    }

    public sealed class SongSpell
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public List<SolfegeNote> Notes { get; set; } = new List<SolfegeNote>();
        public int Tempo { get; set; } = 90;
        public IReadOnlyList<SolfegeNote> NotesForChallenge(int challenge) => Notes.Take(System.Math.Max(1, 2 + challenge)).ToArray();
    }
}
