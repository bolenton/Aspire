using System.Threading;
using System.Threading.Tasks;
using Lantern.Core.Companion;
using Lantern.Core.Content;

namespace Lantern.Unity.Companion
{
    public sealed class ServerConversation : IConversationProvider
    {
        private readonly CompanionConnection connection;
        private readonly CompanionVoice voice;
        private readonly IConversationProvider fallback;
        public ServerConversation(CompanionConnection connection,CompanionVoice voice,IConversationProvider fallback)
        {this.connection=connection;this.voice=voice;this.fallback=fallback;}
        public async Task<string> ReplyAsync(string utterance,CompanionDefinition companion,WorldObservation world,CancellationToken cancellation)
        {
            if(!connection.Connected)
            {
                using var local=CancellationTokenSource.CreateLinkedTokenSource(cancellation);local.CancelAfter(System.TimeSpan.FromSeconds(8));
                return await fallback.ReplyAsync(utterance,companion,world,local.Token);
            }
            var id=connection.NextId();voice.BeginReply(id);
            var reply=await connection.RequestAsync(id,"reply",utterance,cancellation);
            voice.ReuseReply(reply.Text);return reply.Text;
        }
    }
}
