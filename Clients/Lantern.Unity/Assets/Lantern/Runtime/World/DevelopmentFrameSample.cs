#if UNITY_EDITOR || DEVELOPMENT_BUILD
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Lantern.Unity.World
{
    /// <summary>Opt-in main-thread frame timing, explicitly separate from a GPU or thermal benchmark.</summary>
    public sealed class DevelopmentFrameSample : MonoBehaviour
    {
        private IEnumerator Start()
        {
            if(System.Environment.GetEnvironmentVariable("LANTERN_CAPTURE")!="1")yield break;
            yield return new WaitForSeconds(14);
            var samples=new List<float>();var start=Time.realtimeSinceStartup;
            while(Time.realtimeSinceStartup-start<20)
            { yield return null;samples.Add(Time.unscaledDeltaTime*1000); }
            var elapsed=Time.realtimeSinceStartup-start;samples.Sort();
            if(samples.Count>0) Debug.Log($"Lantern frame sample: {samples.Count/elapsed:F1} fps average; p95={samples[Mathf.Min(samples.Count-1,Mathf.FloorToInt(samples.Count*.95f))]:F2} ms; frames={samples.Count}; window={elapsed:F1}s. Development build, main-thread timing only.");
        }
    }
}
#endif
