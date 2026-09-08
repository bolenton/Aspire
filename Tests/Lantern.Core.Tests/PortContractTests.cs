using Lantern.Core.Companion;
using Lantern.Core.Content;
using Lantern.Core.Gameplay;
using Lantern.Core.Persistence;
using Xunit;

namespace Lantern.Core.Tests;

public sealed class PortContractTests
{
    private static readonly StoryPack Pack = StoryJson.Read<StoryPack>(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "StoryPacks/ForestJourney/pack.json")));
    private static readonly CompanionRoster Roster = StoryJson.Read<CompanionRoster>(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "StoryPacks/Companions/roster.json")));
    private static GameProgress NewProgress() => new PlayerVault().CreateSlot(Pack, Roster.Companions[0]).Progress;

    [Fact] public void ExistingContentAndCompanionFlavorsLoad()
    {
        StoryJson.Validate(Pack, Roster);
        Assert.Equal(3, Pack.Scenes.Count());
        Assert.Equal(3, Roster.Companions.Count);
        Assert.Contains("smells", Pack.Scene("fox_hollow")!.SpokenDescription.Resolve("ember"));
        Assert.NotEqual(Pack.Scene("fox_hollow")!.SpokenDescription.Resolve("petal"), Pack.Scene("fox_hollow")!.SpokenDescription.Resolve("ember"));
        Assert.NotEmpty(Roster.Companions[0].AssetName!);
    }
    [Fact] public void ReachingCannotSkipDialogueAndFoxQuestUnlocksAcornInOrder()
    {
        var progress = NewProgress();
        Assert.NotNull(progress.Complete(Pack, "@companion", QuestGoal.Reach));
        Assert.Null(progress.Complete(Pack, "@companion", QuestGoal.Reach));
        Assert.NotNull(progress.Complete(Pack, "@companion", QuestGoal.Talk));
        Assert.Null(progress.Complete(Pack, "glowing_acorn", QuestGoal.Collect));
        Assert.NotNull(progress.Complete(Pack, "old_oak", QuestGoal.Reach));
        Assert.NotNull(progress.Complete(Pack, "old_oak", QuestGoal.Song));
        Assert.Contains("oak_awake", progress.Flags);
        Assert.NotNull(progress.Complete(Pack, "glowing_acorn", QuestGoal.Collect));
        Assert.Contains("acorn_found", progress.Flags);
        Assert.Single(progress.Inventory);
        Assert.Null(progress.Complete(Pack, "glowing_acorn", QuestGoal.Collect));
    }
    [Fact] public void PortalAndCompanionAbilityGatesRemainEnforced()
    {
        var progress = NewProgress();
        var scene = Pack.Scene("fox_hollow")!;
        var portal = scene.Entities.Single(e => e.Id == "cave_mouth");
        Assert.False(progress.Travel(Pack, portal));
        progress.Flags.Add("acorn_found");
        Assert.True(progress.Travel(Pack, portal));
        Assert.Equal("echo_chamber", progress.CurrentSceneID);
        var treat = scene.Entities.Single(e => e.Id == "buried_treat");
        Assert.True(progress.IsPerceivable(treat, Roster.Companions.Single(c => c.Id == "ember")));
        Assert.False(progress.IsPerceivable(treat, Roster.Companions.Single(c => c.Id == "petal")));
    }
    [Fact] public void SongMistakesDoNotResetProgressOrCountAsSuccess()
    {
        var song = new SongPerformance(Pack.Song("oak_song")!.NotesForChallenge(1));
        Assert.Equal(NoteResult.Correct, song.Play(SolfegeNote.Do));
        Assert.Equal(NoteResult.TryAgain, song.Play(SolfegeNote.Ti));
        Assert.Equal(1, song.Index);
        Assert.Equal(NoteResult.Correct, song.Play(SolfegeNote.Re));
        Assert.Equal(NoteResult.Complete, song.Play(SolfegeNote.Mi));
    }
    [Fact] public void AdaptationNeverDropsBelowParentBaseline()
    {
        var director = DifficultyDirector.For(new CalibrationProfile { HintAggressiveness = HintAggressiveness.Eager });
        for (var i = 0; i < 20; i++) director.Record(new TelemetrySample { Succeeded = false });
        Assert.Equal(2, director.Support.AudioCueGain);
        for (var i = 0; i < 20; i++) director.Record(new TelemetrySample { Succeeded = true });
        Assert.Equal(director.Baseline.AudioCueGain, director.Support.AudioCueGain);
        Assert.Equal(2, director.Support.HintTier);
        Assert.Equal(5, director.Support.Challenge);
    }
    [Theory]
    [InlineData(0, 10, 0, "ahead")]
    [InlineData(10, 0, 0, "to your right")]
    [InlineData(0, 10, 90, "to your left")]
    [InlineData(0, -10, 0, "behind you")]
    public void GuidanceUsesUnityCoordinatesAndBodyOrientation(double x, double z, double yaw, string expected) =>
        Assert.Equal(expected, Guidance.Direction(new WorldPoint(), new WorldPoint(x, 0, z), yaw));

    [Fact] public void GuideCannotStartForBlockedOrLockedRoutes()
    {
        var target = new ObservedEntity { Id = "oak", Name = "oak", Route = RouteStatus.Blocked, Available = true };
        var world = new WorldObservation { TargetID = "oak", Entities = new() { target } };
        Assert.Equal(CompanionAction.None, CompanionConversation.LocalCommand("guide me", world)!.Action);
        target.Route = RouteStatus.Reachable;
        target.Available = false;
        Assert.Equal(CompanionAction.None, CompanionConversation.LocalCommand("take me to oak", world)!.Action);
        target.Available = true;
        Assert.Equal(CompanionAction.GuideToTarget, CompanionConversation.LocalCommand("guide me", world)!.Action);
        Assert.Equal(CompanionAction.Stop, CompanionConversation.LocalCommand("stop please", world)!.Action);
    }
    [Fact] public void CorruptSaveIsPreservedAndCannotBeOverwritten()
    {
        var directory = Path.Combine(Path.GetTempPath(), "lantern-tests-" + Guid.NewGuid());
        Directory.CreateDirectory(directory);
        try
        {
            var path = Path.Combine(directory, "vault.json");
            File.WriteAllText(path, "broken{");
            var store = new VaultStore(path);
            Assert.ThrowsAny<Exception>(() => store.Load());
            Assert.Throws<InvalidOperationException>(() => store.Save(new PlayerVault()));
            Assert.Equal("broken{", File.ReadAllText(path));
        }
        finally { Directory.Delete(directory, true); }
    }
    [Fact] public void LegacySaveRetainsMemoriesAvatarAndOptionalDefaults()
    {
        var vault = new PlayerVault();
        var slot = vault.CreateSlot(Pack, Roster.Companions[0]);
        slot.Progress.Complete(Pack, "@companion", QuestGoal.Reach);
        vault.Avatar["outfitColorID"] = "royal";
        vault.Remember(new MemoryEvent { Kind = MemoryKind.Favorite, Key = "color", Value = "purple" }, slot);
        var json = Newtonsoft.Json.Linq.JObject.Parse(StoryJson.Write(vault));
        json.Remove("schemaVersion");
        var migrated = VaultStore.Parse(json.ToString());
        Assert.Equal("royal", (string?)migrated.Avatar["outfitColorID"]);
        Assert.Equal("purple", migrated.SharedJournal.Recall("color"));
        Assert.Null(migrated.Slots[0].PlayerPosition);
        Assert.Single(migrated.Slots[0].Progress.CompletedStepIDs);
    }
    [Fact] public void SaveWrittenByActualSwiftEngineLoadsWithoutLosingProgress()
    {
        var json = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures/legacy-swift-vault.json"));
        var vault = VaultStore.Parse(json);
        var slot = Assert.Single(vault.Slots);
        Assert.Equal("Fixture child", vault.Calibration.ChildName);
        Assert.Equal("royal", (string?)vault.Avatar["outfitColorID"]);
        Assert.Equal("careful", slot.Journal.Recall("adventure_spirit"));
        Assert.Single(slot.Progress.CompletedStepIDs);
        Assert.Equal(QuestGoal.Talk, slot.Progress.CurrentStep(Pack)!.Goal);
        Assert.Single(slot.Difficulty.Recent);
        Assert.Equal(new DateTime(2024, 7, 3, 9, 46, 40, DateTimeKind.Utc), slot.CreatedAt);
    }
    [Fact] public async Task StopDiscardsAReplyAlreadyInFlight()
    {
        var provider = new DelayedProvider();
        using var conversation = new CompanionConversation(provider);
        var original = conversation.ReplyAsync("hello", Roster.Companions[0], new WorldObservation());
        var stop = await conversation.ReplyAsync("stop", Roster.Companions[0], new WorldObservation());
        Assert.Equal(CompanionAction.Stop, stop.Action);
        provider.Completion.SetResult("A stale instruction");
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => original);
    }
    private sealed class DelayedProvider : IConversationProvider
    {
        public readonly TaskCompletionSource<string> Completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task<string> ReplyAsync(string utterance, CompanionDefinition companion, WorldObservation observation, CancellationToken cancellation) => Completion.Task;
    }
}
