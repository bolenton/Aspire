#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using Lantern.Core.Content;

namespace Lantern.Core.Gameplay
{
    public enum ActivityKind { Navigation, Puzzle, Song, Dialogue }
    public sealed class TelemetrySample
    {
        public ActivityKind Kind { get; set; }
        public bool Succeeded { get; set; }
        public double Duration { get; set; }
        public int HintsUsed { get; set; }
    }
    public sealed class SupportLevel
    {
        public double AudioCueGain { get; set; } = 1.3;
        public double GlowBoost { get; set; } = 1.3;
        public int HintTier { get; set; } = 1;
        public int Challenge { get; set; } = 1;
        public static SupportLevel For(HintAggressiveness setting) => new SupportLevel
        { AudioCueGain = 1 + (int)setting * .3, GlowBoost = 1 + (int)setting * .3, HintTier = (int)setting };
    }
    public sealed class DifficultyDirector
    {
        public SupportLevel Support { get; set; } = new SupportLevel();
        public SupportLevel Baseline { get; set; } = new SupportLevel();
        public List<TelemetrySample> Recent { get; set; } = new List<TelemetrySample>();
        public double StruggleDuration { get; set; } = 90;
        public bool LastChangeWasEscalation { get; set; }
        public static DifficultyDirector For(CalibrationProfile profile) => new DifficultyDirector
        { Support = SupportLevel.For(profile.HintAggressiveness), Baseline = SupportLevel.For(profile.HintAggressiveness), StruggleDuration = 120 - 30 * (int)profile.HintAggressiveness };

        public void Record(TelemetrySample sample)
        {
            Recent.Add(sample);
            if (Recent.Count > 5) Recent.RemoveRange(0, Recent.Count - 5);
            LastChangeWasEscalation = false;
            if (Recent.Skip(Math.Max(0, Recent.Count - 2)).Count(IsStruggle) >= 2)
            {
                Support.AudioCueGain = Math.Min(2, Support.AudioCueGain + .2);
                Support.GlowBoost = Math.Min(2, Support.GlowBoost + .2);
                Support.HintTier = Math.Min(2, Support.HintTier + 1);
                Support.Challenge = Math.Max(1, Support.Challenge - 1);
                LastChangeWasEscalation = true;
            }
            else if (Recent.Count >= 3 && Recent.Skip(Recent.Count - 3).All(s => !IsStruggle(s)))
            {
                Support.AudioCueGain = Math.Max(Baseline.AudioCueGain, Support.AudioCueGain - .1);
                Support.GlowBoost = Math.Max(Baseline.GlowBoost, Support.GlowBoost - .1);
                Support.HintTier = Math.Max(Baseline.HintTier, Support.HintTier - 1);
                Support.Challenge = Math.Min(5, Support.Challenge + 1);
            }
        }
        private bool IsStruggle(TelemetrySample s) => !s.Succeeded || s.Duration > StruggleDuration || s.HintsUsed >= 2;
        public string Hint(QuestStep step, string? companionID) => step.HintLadder.Count == 0
            ? step.Intro.Resolve(companionID)
            : step.HintLadder[Math.Max(0, Math.Min(Support.HintTier, step.HintLadder.Count - 1))].Resolve(companionID);
    }
}
