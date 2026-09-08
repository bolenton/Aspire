using UnityEngine;
using Lantern.Core.Gameplay;

namespace Lantern.Unity.World
{
    /// <summary>Restored lights warm the characters gradually, without flashes or camera effects.</summary>
    public sealed class MeadowRewards : MonoBehaviour
    {
        private Light garden, oak;
        private bool gardenAwake, homeLit;
        public void Initialize()
        {
            garden=Lantern("Garden restored glow",new Vector3(24,3.2f,17));
            oak=Lantern("Home restored glow",new Vector3(0,2.5f,14.5f));
        }
        private Light Lantern(string name,Vector3 position)
        {
            var light=new GameObject(name).AddComponent<Light>();light.transform.SetParent(transform,false);
            light.transform.position=position;light.type=LightType.Point;light.range=7;
            light.color=new Color(1,.72f,.34f);light.intensity=0;light.shadows=LightShadows.None;
            return light;
        }
        public void Refresh(GameProgress progress)
        { gardenAwake=progress.Flags.Contains("garden_awake");homeLit=progress.Flags.Contains("meadow_lit"); }
        private void Update()
        {
            if(garden==null)return;
            garden.intensity=Mathf.MoveTowards(garden.intensity,gardenAwake ? 2.3f : 0,Time.deltaTime*.8f);
            oak.intensity=Mathf.MoveTowards(oak.intensity,homeLit ? 2.0f : 0,Time.deltaTime*.8f);
        }
    }
}
