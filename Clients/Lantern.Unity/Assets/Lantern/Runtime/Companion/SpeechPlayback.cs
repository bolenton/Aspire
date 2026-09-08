using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace Lantern.Unity.Companion
{
    public sealed class SpeechPlayback : MonoBehaviour
    {
        private readonly Queue<AudioClip> clips=new Queue<AudioClip>();
        private AudioSource source;
        public bool Playing => (source!=null&&source.isPlaying)||clips.Count>0;
        public float Level {get;private set;}
        private readonly float[] samples=new float[128];
        private void Awake(){source=gameObject.AddComponent<AudioSource>();source.playOnAwake=false;source.spatialBlend=0;source.priority=0;}
        public void Enqueue(byte[] wav)
        {
            if(clips.Count>=12)throw new InvalidDataException("Speech queue is full");
            clips.Enqueue(Decode(wav));
        }
        public void SetVolume(float volume){if(source!=null)source.volume=volume;}
        public void Stop()
        {
            if(source!=null){source.Stop();if(source.clip!=null){Destroy(source.clip);source.clip=null;}}
            while(clips.Count>0)Destroy(clips.Dequeue());Level=0;
        }
        private void Update()
        {
            if(!source.isPlaying&&clips.Count>0){if(source.clip!=null)Destroy(source.clip);source.clip=clips.Dequeue();source.Play();}
            if(source.isPlaying){source.GetOutputData(samples,0);float sum=0;foreach(var value in samples)sum+=value*value;Level=Mathf.Clamp01(Mathf.Sqrt(sum/samples.Length)*7);}else Level=0;
        }
        private static AudioClip Decode(byte[] bytes)
        {
            using var stream=new MemoryStream(bytes);using var reader=new BinaryReader(stream);
            if(new string(reader.ReadChars(4))!="RIFF")throw new InvalidDataException("Invalid voice audio");reader.ReadInt32();if(new string(reader.ReadChars(4))!="WAVE")throw new InvalidDataException("Invalid voice format");
            int rate=0,channels=0,bits=0,format=0;byte[] data=null;
            while(stream.Position+8<=stream.Length)
            {
                var name=new string(reader.ReadChars(4));var length=reader.ReadInt32();if(length<0||length>stream.Length-stream.Position)throw new InvalidDataException("Invalid audio size");var end=stream.Position+length;
                if(name=="fmt "&&length>=16){format=reader.ReadUInt16();channels=reader.ReadUInt16();rate=reader.ReadInt32();reader.ReadInt32();reader.ReadUInt16();bits=reader.ReadUInt16();}
                else if(name=="data")data=reader.ReadBytes(length);
                stream.Position=end+(length%2);
            }
            if(format!=1||bits!=16||channels<1||channels>2||rate<8000||rate>48000||data==null)throw new InvalidDataException("Unsupported voice audio");
            var samples=new float[data.Length/2];for(int i=0;i<samples.Length;i++)samples[i]=(short)(data[i*2]|data[i*2+1]<<8)/32768f;
            var clip=AudioClip.Create("Ember voice",samples.Length/channels,channels,rate,false);clip.SetData(samples,0);return clip;
        }
        private void OnDestroy()=>Stop();
    }
}
