#nullable enable
using System.Collections.Generic;
using System.Linq;

namespace Lantern.Core.Content
{
    public sealed class CompanionRoster
    {
        public int Version { get; set; }
        public List<CompanionDefinition> Companions { get; set; } = new List<CompanionDefinition>();
    }

    public sealed class CompanionDefinition
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public string Species { get; set; } = "";
        public string Personality { get; set; } = "";
        public string Introduction { get; set; } = "";
        public string? AssetName { get; set; }
        public VoiceSpec Voice { get; set; } = new VoiceSpec();
        public List<string> Quirks { get; set; } = new List<string>();
        public Dictionary<string, string> Sounds { get; set; } = new Dictionary<string, string>();
        public List<PerceptionAbility> Abilities { get; set; } = new List<PerceptionAbility>();
        public SpeechStyle SpeechStyle { get; set; } = new SpeechStyle();
        public bool HasAbility(string id) => Abilities.Any(a => a.Id == id);
        public double HearingMultiplier => Abilities.Select(a => a.AudibleRangeMultiplier ?? 1).DefaultIfEmpty(1).Max();
    }

    public sealed class PerceptionAbility
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public string SpokenDescription { get; set; } = "";
        public string SenseVerb { get; set; } = "";
        public double? AudibleRangeMultiplier { get; set; }
    }

    public sealed class VoiceSpec
    {
        public string Language { get; set; } = "en-US";
        public double Rate { get; set; } = 0.45;
        public double Pitch { get; set; } = 1;
        public string? VoiceIdentifier { get; set; }
        public string? CloudVoiceID { get; set; }
    }

    public sealed class SpeechStyle
    {
        public string Exclamation { get; set; } = "Oh!";
        public List<string> Catchphrases { get; set; } = new List<string>();
        public Dictionary<string, List<string>> Templates { get; set; } = new Dictionary<string, List<string>>();
    }
}
