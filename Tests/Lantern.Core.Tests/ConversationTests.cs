using Lantern.Core.Companion;
using Lantern.Core.Content;
using Lantern.Core.Persistence;
using Xunit;

namespace Lantern.Core.Tests;

public sealed class ConversationTests
{
    private static readonly CompanionDefinition Ember = new() { Name = "Ember", Species = "fox" };

    [Fact] public void FamiliarNamesResolveButUnknownDestinationsNeverStartMovement()
    {
        var oak = new ObservedEntity { Id = "old_oak", Name = "Old oak", Aliases = new() { "tree", "oak", "home" }, Available = true, Route = RouteStatus.Reachable };
        var world = new WorldObservation { TargetID = "other", Entities = new() { oak } };
        var reply = CompanionCommands.Resolve("Could you walk me to the tree?", world)!;
        Assert.Equal(CompanionAction.GuideToTarget, reply.Action);
        Assert.Equal("old_oak", reply.TargetID);
        Assert.Equal(CompanionAction.None, CompanionCommands.Resolve("take me to the moon", world)!.Action);
        oak.Available = false;
        Assert.Equal(CompanionAction.None, CompanionCommands.Resolve("take me home", world)!.Action);
    }

    [Fact] public async Task TimeoutReturnsAnAuthoredReplyEvenWhenProviderIgnoresCancellation()
    {
        var completion = new TaskCompletionSource<string>();
        using var conversation = new CompanionConversation(new Provider(() => completion.Task), TimeSpan.FromMilliseconds(25));
        var reply = await conversation.ReplyAsync("Tell me a joke", Ember, new WorldObservation()).WaitAsync(TimeSpan.FromSeconds(2));
        Assert.Contains("paw prints", reply.Text);
        Assert.Equal(CompanionAction.None, reply.Action);
        completion.SetResult("Too late");
    }

    [Fact] public async Task LocalCommandsBypassTheModelAndGeneratedTextCannotPerformAnAction()
    {
        var calls = 0;
        using var conversation = new CompanionConversation(new Provider(() => { calls++; return Task.FromResult("Walk to the moon!"); }));
        var stopped = await conversation.ReplyAsync("stop now", Ember, new WorldObservation());
        Assert.Equal(0, calls);
        Assert.Equal(CompanionAction.Stop, stopped.Action);
        var generated = await conversation.ReplyAsync("hello friend", Ember, new WorldObservation());
        Assert.Equal(1, calls);
        Assert.Equal(CompanionAction.None, generated.Action);
    }

    [Fact] public void ContextExcludesLockedPlacesAndConversationPreferenceRoundTrips()
    {
        var world = new WorldObservation { Entities = new() { new() { Name = "Secret cave", Available = false, InAwarenessRange = true } } };
        var prompt = ConversationPrompt.Create("hello", Ember, world, Array.Empty<ConversationExchange>());
        Assert.DoesNotContain("Secret cave", prompt);
        var oldSave = VaultStore.Parse("{\"slots\":[],\"calibration\":{}}");
        Assert.True(oldSave.Calibration.OnDeviceConversation);
        oldSave.Calibration.OnDeviceConversation = false;
        Assert.False(VaultStore.Parse(StoryJson.Write(oldSave)).Calibration.OnDeviceConversation);
    }

    private sealed class Provider(Func<Task<string>> reply) : IConversationProvider
    {
        public Task<string> ReplyAsync(string utterance, CompanionDefinition companion, WorldObservation observation, CancellationToken cancellation) => reply();
    }
}
