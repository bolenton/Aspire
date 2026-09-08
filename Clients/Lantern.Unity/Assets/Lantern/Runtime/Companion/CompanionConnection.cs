using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Lantern.Core.Companion;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Newtonsoft.Json.Serialization;
using UnityEngine;

namespace Lantern.Unity.Companion
{
    public sealed class CompanionConnection : MonoBehaviour
    {
        [Serializable] public sealed class Configuration { public string url; public string pairingCode; }
        public sealed class Reply { public long Id; public string Text; public long ElapsedMs; }
        private readonly ConcurrentQueue<JObject> inbox = new ConcurrentQueue<JObject>();
        private readonly ConcurrentQueue<byte[]> outgoing = new ConcurrentQueue<byte[]>();
        private readonly SemaphoreSlim outgoingSignal = new SemaphoreSlim(0);
        private readonly Dictionary<long, TaskCompletionSource<Reply>> requests = new Dictionary<long, TaskCompletionSource<Reply>>();
        private readonly CancellationTokenSource lifetime = new CancellationTokenSource();
        private static readonly JsonSerializerSettings JsonSettings = new JsonSerializerSettings { ContractResolver = new CamelCasePropertyNamesContractResolver() };
        private ClientWebSocket socket;
        private CancellationTokenSource connectionLife;
        private Configuration config;
        private bool connecting, paused, enabledForFamily=true;
        private float retryAt;
        private long sequence;
        private AdventureWorld world;
        public bool Connected => socket?.State == WebSocketState.Open;
        public string Status { get; private set; } = "Ember is using the on-device voice.";
        public event Action<JObject> Message;
        public event Action<bool> ConnectionChanged;
        public AdventureWorld World => world;
        public void SetEnabled(bool value){enabledForFamily=value;if(!value)Disconnect("Using the on-device companion.");else retryAt=0;}
        public void Initialize()
        {
            var path = Path.Combine(Application.streamingAssetsPath,"CompanionServer.json");
            if (File.Exists(path)) config = JsonConvert.DeserializeObject<Configuration>(File.ReadAllText(path));
            _ = ConnectAsync();
        }
        public long NextId() => ++sequence;
        public void SetWorld(AdventureWorld snapshot)
        {
            world = snapshot;
            if (Connected) Send(new { type="world", world=snapshot });
        }
        public void Send(object message)
        {
            if (!Connected) return;
            if (outgoing.Count >= 160) { Disconnect("The connection slowed down. Tap to reconnect."); return; }
            outgoing.Enqueue(Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(message,JsonSettings)));
            outgoingSignal.Release();
        }
        public async Task<Reply> RequestAsync(long id,string type,string text,CancellationToken cancellation)
        {
            if (!Connected || world == null) throw new HttpRequestException("Companion server unavailable");
            var completion = new TaskCompletionSource<Reply>(TaskCreationOptions.RunContinuationsAsynchronously);
            requests.Add(id,completion);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation,lifetime.Token);
            timeout.CancelAfter(TimeSpan.FromSeconds(40));
            using var registration=timeout.Token.Register(() => completion.TrySetCanceled());
            try { Send(new {type,id,text,revision=world.Revision}); return await completion.Task; }
            finally { requests.Remove(id); if(timeout.IsCancellationRequested) Send(new {type="cancel",id}); }
        }
        public void Cancel(long id) { Send(new {type="cancel",id}); if(requests.TryGetValue(id,out var pending))pending.TrySetCanceled(); }
        public void Forget() => Send(new { type="forget" });
        private async Task ConnectAsync()
        {
            if(!enabledForFamily || connecting || paused || config == null || string.IsNullOrWhiteSpace(config.url) || Connected)return;
            connecting=true;
            try
            {
                var endpoint=new Uri(config.url);
                if(endpoint.Scheme!="https" && !endpoint.IsLoopback) throw new InvalidOperationException("The companion endpoint must use HTTPS.");
                using var setup=CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);setup.CancelAfter(TimeSpan.FromSeconds(15));
                var token=CompanionCredentials.Load(config.url);
                if(string.IsNullOrEmpty(token))
                {
                    using var http=new HttpClient();
                    using var response=await http.PostAsync(config.url.TrimEnd('/')+"/v1/pair",new StringContent(JsonConvert.SerializeObject(new {code=config.pairingCode}),Encoding.UTF8,"application/json"),setup.Token);
                    response.EnsureSuccessStatusCode();
                    token=JObject.Parse(await response.Content.ReadAsStringAsync()).Value<string>("token");
                    CompanionCredentials.Save(config.url,token);
                }
                connectionLife?.Dispose();connectionLife=CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
                socket=new ClientWebSocket();socket.Options.SetRequestHeader("Authorization","Bearer "+token);socket.Options.KeepAliveInterval=TimeSpan.FromSeconds(20);
                var uri=new UriBuilder(config.url.TrimEnd('/')+"/v1/companion"){Scheme=endpoint.Scheme=="https" ? "wss":"ws"};
                await socket.ConnectAsync(uri.Uri,setup.Token);
                Status="Connected to Ember's home server.";ConnectionChanged?.Invoke(true);
                if(world!=null)SetWorld(world);
                var connectedSocket=socket;var connectedLife=connectionLife.Token;
                _ = Task.Run(() => ReceiveLoop(connectedSocket,connectedLife));
                _ = Task.Run(() => SendLoop(connectedSocket,connectedLife));
            }
            catch(Exception error) when(error is HttpRequestException || error is WebSocketException || error is OperationCanceledException || error is InvalidOperationException)
            { Disconnect("Ember's server is unavailable. The adventure and local voice still work."); }
            finally {connecting=false;retryAt=Time.unscaledTime+12;}
        }
        private async Task ReceiveLoop(ClientWebSocket current,CancellationToken cancel)
        {
            try
            {
                var buffer=new byte[16384];
                while(!cancel.IsCancellationRequested)
                {
                    using var message=new MemoryStream();WebSocketReceiveResult part;
                    do {part=await current.ReceiveAsync(new ArraySegment<byte>(buffer),cancel);if(part.MessageType==WebSocketMessageType.Close)throw new WebSocketException();message.Write(buffer,0,part.Count);if(message.Length>3*1024*1024)throw new WebSocketException();}while(!part.EndOfMessage);
                    inbox.Enqueue(JObject.Parse(Encoding.UTF8.GetString(message.ToArray())));
                }
            }
            catch(Exception error) when(error is WebSocketException || error is OperationCanceledException || error is ObjectDisposedException || error is JsonException)
            { if(!cancel.IsCancellationRequested)inbox.Enqueue(new JObject{{"type","disconnected"}}); }
        }
        private async Task SendLoop(ClientWebSocket current,CancellationToken cancel)
        {
            try {while(!cancel.IsCancellationRequested){await outgoingSignal.WaitAsync(cancel);if(outgoing.TryDequeue(out var bytes))await current.SendAsync(new ArraySegment<byte>(bytes),WebSocketMessageType.Text,true,cancel);}}
            catch(Exception error) when(error is WebSocketException || error is OperationCanceledException || error is ObjectDisposedException)
            {if(!cancel.IsCancellationRequested)inbox.Enqueue(new JObject{{"type","disconnected"}});}
        }
        private void Update()
        {
            while(inbox.TryDequeue(out var value))
            {
                var type=value.Value<string>("type");var id=value.Value<long?>("id")??0;
                if(type=="disconnected"){Disconnect("The connection paused. Ember's local voice is available.");continue;}
                if(requests.TryGetValue(id,out var completion))
                {
                    if(type=="done")completion.TrySetResult(new Reply{Id=id,Text=value.Value<string>("text")??"",ElapsedMs=value.Value<long?>("elapsedMs")??0});
                    else if(type=="error")completion.TrySetException(new HttpRequestException("Local inference unavailable"));
                    else if(type=="cancelled")completion.TrySetCanceled();
                }
                Message?.Invoke(value);
            }
            if(!Connected&&!connecting&&!paused&&Time.unscaledTime>=retryAt)_ = ConnectAsync();
        }
        private void Disconnect(string status)
        {
            Status=status;connectionLife?.Cancel();socket?.Abort();socket?.Dispose();socket=null;
            while(outgoing.TryDequeue(out _)){}while(inbox.TryDequeue(out _)){}
            foreach(var request in requests.Values)request.TrySetException(new HttpRequestException("Connection lost"));
            ConnectionChanged?.Invoke(false);retryAt=Time.unscaledTime+12;
        }
        private void OnApplicationPause(bool value){paused=value;if(value)Disconnect("Conversation paused.");else retryAt=0;}
        private void OnDestroy(){lifetime.Cancel();Disconnect("Conversation closed.");lifetime.Dispose();}
    }
}
