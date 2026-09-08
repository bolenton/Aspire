using System;
using System.IO;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Networking;

namespace Lantern.Unity.Audio
{
    internal static class MeadowAudioClip
    {
        public static async Task<AudioClip> LoadAsync(string name)
        {
            var path = Path.Combine(Application.streamingAssetsPath,"Meadow",name);
            using (var request = UnityWebRequestMultimedia.GetAudioClip(new Uri(path).AbsoluteUri,AudioType.WAV))
            {
                var operation = request.SendWebRequest();
                while (!operation.isDone) await Task.Yield();
                if (request.result != UnityWebRequest.Result.Success)
                    throw new InvalidDataException("The meadow sound could not be opened: " + name);
                return DownloadHandlerAudioClip.GetContent(request);
            }
        }
    }
}
