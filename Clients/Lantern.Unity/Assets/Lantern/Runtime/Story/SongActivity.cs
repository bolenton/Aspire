using System;
using Lantern.Core.Content;
using Lantern.Core.Gameplay;
using Lantern.Unity.Audio;
using Lantern.Unity.Companion;
using Lantern.Unity.Platform;
using Lantern.Unity.Presentation;

namespace Lantern.Unity.Story
{
    /// <summary>Untimed musical interaction, separate from quest progression and the view.</summary>
    public sealed class SongActivity
    {
        private readonly SongInstrument instrument;
        private readonly AdventureHud hud;
        private readonly CompanionVoice voice;
        private readonly Action<string> say;
        public SongActivity(SongInstrument instrument,AdventureHud hud,CompanionVoice voice,Action<string> say)
        { this.instrument=instrument;this.hud=hud;this.voice=voice;this.say=say; }
        public void Begin(SongSpell song,int challenge,Action completed,Action back)
        {
            var performance=new SongPerformance(song.NotesForChallenge(challenge));
            void Play(SolfegeNote note)
            {
                voice.Stop();instrument.Play(note);
                var result=performance.Play(note);
                hud.SetSongProgress(performance.Index);
                if(result==NoteResult.Complete) completed();
                else if(result==NoteResult.TryAgain) say("Let's try "+performance.Notes[performance.Index]+". Take your time.");
                else hud.Say("Lovely. Next is "+performance.Notes[performance.Index]+".");
            }
            var words=song.Name+": "+string.Join(", ",performance.Notes)+". Tap the chimes, or the round arrow to hear the song.";
            hud.ShowMelody(words,performance.Notes,Play,()=> {voice.Stop();instrument.Demonstrate(performance.Notes);},back);
            say(words);
        }
    }
}
