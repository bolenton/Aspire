#nullable enable
using System;
using System.Collections.Generic;
using Lantern.Core.Content;

namespace Lantern.Core.Gameplay
{
    public enum NoteResult { Correct, TryAgain, Complete }
    // No timing penalty. A mistaken note repeats the current note without losing progress.
    public sealed class SongPerformance
    {
        public IReadOnlyList<SolfegeNote> Notes { get; }
        public int Index { get; private set; }
        public bool IsComplete => Index == Notes.Count;
        public SongPerformance(IReadOnlyList<SolfegeNote> notes)
        {
            if (notes.Count == 0) throw new ArgumentException("A song needs notes.", nameof(notes));
            Notes = notes;
        }
        public NoteResult Play(SolfegeNote note)
        {
            if (IsComplete) return NoteResult.Complete;
            if (Notes[Index] != note) return NoteResult.TryAgain;
            Index++;
            return IsComplete ? NoteResult.Complete : NoteResult.Correct;
        }
    }
}
