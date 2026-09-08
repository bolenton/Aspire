using Lantern.Core.Content;
using Lantern.Core.Gameplay;
using Lantern.Core.Persistence;
using Xunit;

namespace Lantern.Core.Tests;

public sealed class MeadowExpansionTests
{
    private static StoryPack Meadow => StoryJson.Read<StoryPack>(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"UnityContent/MeadowJourney/pack.json")));
    private static CompanionRoster Roster => StoryJson.Read<CompanionRoster>(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"StoryPacks/Companions/roster.json")));

    [Fact] public void ExistingAcornSaveContinuesThroughGardenAndHomeWithoutSkippingLockedRewards()
    {
        var pack=Meadow;var roster=Roster;StoryJson.Validate(pack,roster);
        var progress=new PlayerVault().CreateSlot(pack,roster.Companions.Single(c=>c.Id=="ember")).Progress;
        foreach(var step in pack.Quests[0].Steps) Assert.NotNull(progress.Complete(pack,step.TargetEntityID,step.Goal));
        // Existing completed-acorn saves have the old quest active and no current step.
        var restored=StoryJson.Read<GameProgress>(StoryJson.Write(progress));
        Assert.Null(restored.CurrentStep(pack));restored.SelectNextQuest(pack);
        Assert.Equal("reach_river_bell",restored.CurrentStep(pack)!.Id);
        Assert.False(restored.IsAvailable(pack.Scene("fox_hollow")!.Entities.Single(e=>e.Id=="garden_star")));
        Assert.Null(restored.Complete(pack,"garden_star",QuestGoal.Collect));
        var count=5;
        while(restored.CurrentStep(pack) is { } next)
        {
            Assert.NotNull(restored.Complete(pack,next.TargetEntityID,next.Goal));count++;
            if(restored.CurrentStep(pack)==null)restored.SelectNextQuest(pack);
        }
        Assert.Equal(21,count);Assert.Contains("moon_seed",restored.Inventory);Assert.Contains("orchard_restored",restored.Flags);Assert.Contains("garden_star",restored.Inventory);Assert.Contains("meadow_lit",restored.Flags);
        Assert.Equal(4,restored.AvailableQuests(pack).Count());Assert.All(pack.Quests,q=>Assert.True(restored.IsComplete(q)));
    }

    [Fact] public void LegacyCalibrationGetsFasterDefaultAndChosenGentlePacePersists()
    {
        var legacy=StoryJson.Read<CalibrationProfile>("{\"textScale\":2,\"showMovementControl\":true}");
        Assert.Equal(TravelPace.Comfortable,legacy.TravelPace);
        Assert.InRange(TravelSettings.WalkSpeed(legacy.TravelPace),2.79f,2.81f);
        Assert.True(TravelSettings.GuideSpeed(TravelPace.Comfortable)>3.2f);
        legacy.TravelPace=TravelPace.Gentle;
        var restored=StoryJson.Read<CalibrationProfile>(StoryJson.Write(legacy));
        Assert.Equal(TravelPace.Gentle,restored.TravelPace);Assert.True(restored.ShowMovementControl);
    }
}
