using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;

namespace Lantern.Unity.Companion
{
    public sealed class SpeechPlayback : MonoBehaviour
    {
        private sealed class Decoded
        {
            public float[] Samples;
            public int Rate, Channels;
            public string Error;
        }
        private sealed class Batch
        {
            public readonly ConcurrentQueue<Decoded> Ready=new ConcurrentQueue<Decoded>();
            public Task Tail=Task.CompletedTask;
            public int Pending;
        }
        private volatile Batch batch=new Batch();
        private readonly Queue<AudioClip> clips=new Queue<AudioClip>();
        private AudioSource source;
        private readonly float[] meter=new float[128];
        public bool Playing => (source != null && source.isPlaying) || clips.Count>0 || batch.Pending>0 || !batch.Ready.IsEmpty;
        public float Level { get; private set; }
        public event Action<string> Failed;
        private void Awake()
        {
            source=gameObject.AddComponent<AudioSource>();
            source.playOnAwake=false; source.spatialBlend=0; source.priority=0;
        }
        public void Enqueue(string encoded, long request)
        {
            var current=batch;
            if(current.Pending+current.Ready.Count+clips.Count>=12)
            { Failed?.Invoke("My voice needs a moment. Please try again."); return; }
            Interlocked.Increment(ref current.Pending);
            current.Tail=current.Tail.ContinueWith(_ =>
            {
                try
                {
                    if(current != batch) return;
                    var decoded=Decode(Convert.FromBase64String(encoded));
                    if(current == batch) current.Ready.Enqueue(decoded);
                }
                catch(Exception error) when(error is FormatException || error is IOException || error is ArgumentException)
                { if(current == batch) current.Ready.Enqueue(new Decoded { Error="I couldn't play that answer. Please try again." }); }
                finally { Interlocked.Decrement(ref current.Pending); }
            },CancellationToken.None,TaskContinuationOptions.None,TaskScheduler.Default);
        }
        public void SetVolume(float volume) { if(source != null) source.volume=volume; }
        public void Stop()
        {
            batch=new Batch();
            if(source != null)
            {
                source.Stop();
                if(source.clip != null) { Destroy(source.clip); source.clip=null; }
            }
            while(clips.Count>0) Destroy(clips.Dequeue());
            Level=0;
        }
        private void Update()
        {
            // Upload at most one already-decoded sentence per frame; decoding never stalls movement.
            if(batch.Ready.TryDequeue(out var decoded))
            {
                if(decoded.Error != null) { Failed?.Invoke(decoded.Error); return; }
                var clip=AudioClip.Create("Ember voice",decoded.Samples.Length/decoded.Channels,decoded.Channels,decoded.Rate,false);
                clip.SetData(decoded.Samples,0); clips.Enqueue(clip);
            }
            if(!source.isPlaying && clips.Count>0)
            {
                if(source.clip != null) Destroy(source.clip);
                source.clip=clips.Dequeue(); source.Play();
            }
            if(source.isPlaying)
            {
                source.GetOutputData(meter,0);
                float sum=0; foreach(var value in meter) sum+=value*value;
                Level=Mathf.Clamp01(Mathf.Sqrt(sum/meter.Length)*7);
            }
            else Level=0;
        }
        private static Decoded Decode(byte[] bytes)
        {
            using var stream=new MemoryStream(bytes);
            using var reader=new BinaryReader(stream);
            if(new string(reader.ReadChars(4))!="RIFF") throw new InvalidDataException();
            reader.ReadInt32();
            if(new string(reader.ReadChars(4))!="WAVE") throw new InvalidDataException();
            int rate=0,channels=0,bits=0,format=0;
            byte[] data=null;
            while(stream.Position+8<=stream.Length)
            {
                var name=new string(reader.ReadChars(4)); var length=reader.ReadInt32();
                if(length<0 || length>stream.Length-stream.Position) throw new InvalidDataException();
                var end=stream.Position+length;
                if(name=="fmt " && length>=16)
                { format=reader.ReadUInt16();channels=reader.ReadUInt16();rate=reader.ReadInt32();reader.ReadInt32();reader.ReadUInt16();bits=reader.ReadUInt16(); }
                else if(name=="data") data=reader.ReadBytes(length);
                stream.Position=end+length%2;
            }
            if(format!=1 || bits!=16 || channels<1 || channels>2 || rate<8000 || rate>48000 || data==null || data.Length<channels*2 || data.Length%(channels*2)!=0)
                throw new InvalidDataException();
            var samples=new float[data.Length/2];
            for(var i=0;i<samples.Length;i++) samples[i]=(short)(data[i*2]|data[i*2+1]<<8)/32768f;
            return new Decoded { Samples=samples,Rate=rate,Channels=channels };
        }
        private void OnDestroy() => Stop();
    }
}
