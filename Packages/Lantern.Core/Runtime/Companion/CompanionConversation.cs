#nullable enable
using System;
using System.Threading;
using System.Threading.Tasks;
using Lantern.Core.Content;

namespace Lantern.Core.Companion
{
    public enum CompanionAction { None, Stop, GuideToTarget, Interact }
    public sealed class CompanionReply
    {
        public string Text { get; }
        public CompanionAction Action { get; }
        public string? TargetID { get; }
        public CompanionReply(string text, CompanionAction action = CompanionAction.None, string? targetID = null)
        { Text = text; Action = action; TargetID = targetID; }
    }
    // A remote provider may phrase conversation. It has no ability to move the player or mutate quests.
    public interface IConversationProvider
    {
        Task<string> ReplyAsync(string utterance, CompanionDefinition companion, WorldObservation observation, CancellationToken cancellation);
    }
    public sealed class CompanionConversation : IDisposable
    {
        private readonly IConversationProvider? provider;
        private CancellationTokenSource? pending;
        private long generation;
        private readonly TimeSpan timeout;
        public CompanionConversation(IConversationProvider? provider = null, TimeSpan? timeout = null)
        { this.provider = provider; this.timeout = timeout ?? TimeSpan.FromSeconds(8); }
        public void Cancel() { generation++; pending?.Cancel(); }

        public static CompanionReply? LocalCommand(string utterance, WorldObservation world) => CompanionCommands.Resolve(utterance, world);

        public async Task<CompanionReply> ReplyAsync(string utterance, CompanionDefinition companion, WorldObservation world, CancellationToken cancellation = default)
        {
            Cancel();
            var requestGeneration = generation;
            using var request = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            pending = request;
            try
            {
                var local = LocalCommand(utterance, world);
                if (local != null) return local;
                if (provider != null)
                {
                    request.CancelAfter(timeout);
                    try
                    {
                        var response = provider.ReplyAsync(utterance, companion, world, request.Token);
                        // A provider that ignores cancellation must not hold up local help.
                        var cancelled = Task.Delay(Timeout.Infinite, request.Token);
                        if (await Task.WhenAny(response, cancelled) != response)
                        {
                            _ = response.ContinueWith(task => { _ = task.Exception; }, CancellationToken.None,
                                TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
                            request.Token.ThrowIfCancellationRequested();
                        }
                        var text = await response;
                        if (requestGeneration != generation) throw new OperationCanceledException(cancellation);
                        cancellation.ThrowIfCancellationRequested();
                        if (!request.IsCancellationRequested && !string.IsNullOrWhiteSpace(text)) return new CompanionReply(text.Trim());
                    }
                    catch (OperationCanceledException) when (!cancellation.IsCancellationRequested) { }
                    catch (System.Net.Http.HttpRequestException) { }
                }
                if (requestGeneration != generation) throw new OperationCanceledException(cancellation);
                cancellation.ThrowIfCancellationRequested();
                return new CompanionReply(CompanionSmallTalk.Reply(utterance, companion, world));
            }
            finally { if (ReferenceEquals(pending, request)) pending = null; }
        }
        public void Dispose() => Cancel();
    }
}
