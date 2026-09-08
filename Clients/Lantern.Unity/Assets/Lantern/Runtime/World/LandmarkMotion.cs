using UnityEngine;

namespace Lantern.Unity.World
{
    /// <summary>Small, slow collectible motion and a garden bloom that preserves the walking surface.</summary>
    public sealed class LandmarkMotion : MonoBehaviour
    {
        private Vector3 restPosition, restScale;
        private bool collectible;
        private float bloom = 1;
        public void Initialize(bool isCollectible)
        { collectible=isCollectible;restPosition=transform.localPosition;restScale=transform.localScale; }
        public void SetBloom(bool awake) => bloom=awake ? 1 : .73f;
        private void Update()
        {
            if(collectible)
            {
                transform.localPosition=restPosition+Vector3.up*(.12f+Mathf.Sin(Time.time*1.5f)*.09f);
                transform.localRotation=Quaternion.Euler(0,Mathf.Sin(Time.time*.6f)*22,0);
            }
            else transform.localScale=Vector3.Lerp(transform.localScale,restScale*bloom,Time.deltaTime*.7f);
        }
    }
}
