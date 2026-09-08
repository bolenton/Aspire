using UnityEngine;

namespace Lantern.Unity.World
{
    // A nearby friend acknowledges the explorer without sudden turns or camera movement.
    public sealed class WoodlandFriend : MonoBehaviour
    {
        public Transform Explorer { private get; set; }
        private void LateUpdate()
        {
            if(Explorer==null)return;
            var toward=Explorer.position-transform.position;toward.y=0;
            if(toward.sqrMagnitude<.1f||toward.sqrMagnitude>144)return;
            transform.rotation=Quaternion.RotateTowards(transform.rotation,Quaternion.LookRotation(toward),65*Time.deltaTime);
        }
    }
}
