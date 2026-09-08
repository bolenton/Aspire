using System.Collections.Generic;
using UnityEngine;

namespace Lantern.Unity.World
{
    /// <summary>Generous taps follow visible object bounds, including tall flower heads and tree doors.</summary>
    public static class WorldInteraction
    {
        public static Bounds BoundsFor(string id,Transform anchor)
        {
            var renderers=anchor.GetComponentsInChildren<Renderer>();
            if(renderers.Length>0)
            {
                var bounds=renderers[0].bounds;
                for(var i=1;i<renderers.Length;i++) bounds.Encapsulate(renderers[i].bounds);
                bounds.Expand(.20f);
                return bounds;
            }
            if(id=="old_oak") return new Bounds(anchor.position+new Vector3(0,2.8f,1.6f),new Vector3(3.8f,5.6f,3.8f));
            if(id=="garden_gate") return new Bounds(anchor.position+Vector3.up*1.8f,new Vector3(.9f,3.6f,3.6f));
            return new Bounds(anchor.position+Vector3.up,Vector3.one*2);
        }
        private static bool HitGateway(Ray ray,Vector3 origin,out float distance)
        {
            distance=float.MaxValue;var hit=false;
            // The opening is empty space; it must not intercept a tap on an object beyond it.
            var parts=new[]
            {
                new Bounds(origin+new Vector3(0,1.4f,-1.45f),new Vector3(.65f,2.8f,.65f)),
                new Bounds(origin+new Vector3(0,1.4f,1.45f),new Vector3(.65f,2.8f,.65f)),
                new Bounds(origin+new Vector3(0,3.2f,0),new Vector3(.65f,1,3.6f))
            };
            foreach(var part in parts) if(part.IntersectRay(ray,out var value)) { hit=true;distance=Mathf.Min(distance,value); }
            return hit;
        }
        public static string Resolve(Vector2 position,Camera camera,IReadOnlyDictionary<string,Transform> anchors)
        {
            var ray=camera.ScreenPointToRay(position);
            string closest=null;var depth=float.MaxValue;
            foreach(var entry in anchors)
            {
                if(!entry.Value.gameObject.activeInHierarchy)continue;
                float distance;
                var hit = (entry.Key=="garden_gate" || entry.Key=="orchard_gate") ? HitGateway(ray,entry.Value.position,out distance) : BoundsFor(entry.Key,entry.Value).IntersectRay(ray,out distance);
                if(hit && distance<depth)
                { depth=distance;closest=entry.Key; }
            }
            if(closest!=null)return closest;
            // Forgive a near miss, while preserving direct taps on a foreground object.
            var radius=Mathf.Max(36,Screen.height*.055f);
            foreach(var entry in anchors)
            {
                if(!entry.Value.gameObject.activeInHierarchy)continue;
                var projected=camera.WorldToScreenPoint(BoundsFor(entry.Key,entry.Value).center);
                if(projected.z<=0)continue;
                var distance=Vector2.Distance(position,projected);
                if(distance<radius){radius=distance;closest=entry.Key;}
            }
            return closest;
        }
    }
}
