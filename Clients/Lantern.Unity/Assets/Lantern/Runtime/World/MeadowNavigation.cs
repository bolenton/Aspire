using Unity.AI.Navigation;
using UnityEngine;
using UnityEngine.AI;

namespace Lantern.Unity.World
{
    /// <summary>Smooth gameplay collision, independent of decorative stones and plants.</summary>
    public sealed class MeadowNavigation : MonoBehaviour
    {
        private Mesh bridge;
        public void Build()
        {
            Box("Meadow floor",new Vector3(-5,-.25f,6),new Vector3(66,.5f,42));
            Box("Oak trunk",new Vector3(0,2,17),new Vector3(3.3f,4,3.3f));
            Box("West boundary",new Vector3(-38.5f,1,6),new Vector3(1,2,44));
            Box("East boundary",new Vector3(28.5f,1,6),new Vector3(1,2,44));
            Box("South boundary",new Vector3(-5,1,-15),new Vector3(68,2,1));
            Box("North boundary",new Vector3(-5,1,27),new Vector3(68,2,1));
            // The river is blocked on both sides of its single safe crossing.
            Box("River south",new Vector3(12,1,-5.0f),new Vector3(7.2f,2,19.9f));
            Box("River north",new Vector3(12,1,17.05f),new Vector3(7.2f,2,20.0f));
            Bridge();
            GardenBorders();
            TreeTrunks();
            foreach(var p in new[] {new Vector3(-19,2,10),new Vector3(-28,2,13),new Vector3(-36,2,10),new Vector3(-38,2,3),new Vector3(-37,2,-9),new Vector3(-28,2,-10),new Vector3(-21,2,-7)})Box("Orchard trunk",p,new Vector3(.85f,4,.85f));
            var surface = gameObject.AddComponent<NavMeshSurface>();
            surface.collectObjects = CollectObjects.Children;
            surface.useGeometry = NavMeshCollectGeometry.PhysicsColliders;
            surface.overrideVoxelSize = true; surface.voxelSize = .08f;
            surface.BuildNavMesh();
        }
        private void GardenBorders()
        {
            for(var i=0;i<32;i++)
            {
                var angle=i*Mathf.PI*2/32;
                if(Mathf.Sin(angle)<-.80f)continue;
                Box("Raised garden border",new Vector3(24+Mathf.Cos(angle)*4,.6f,17+Mathf.Sin(angle)*4),new Vector3(.86f,1.2f,.86f));
            }
            foreach(var x in new[] {20.8f,27.2f})
                Box("Garden bench",new Vector3(x,.65f,17.15f),new Vector3(.85f,1.3f,3.7f));
        }
        private void TreeTrunks()
        {
            for(var i=0;i<18;i++)
            {
                var angle=i*Mathf.PI*2/18;var x=Mathf.Cos(angle)*25;var z=13+Mathf.Sin(angle)*25;
                if(x < -38 || x > 28 || z < -15 || z > 27)continue;
                Box("Woodland trunk",new Vector3(x,2.5f,z),new Vector3(.9f,5,.9f));
            }
        }
        private void Box(string name,Vector3 position,Vector3 size)
        {
            var root=new GameObject(name); root.transform.SetParent(transform,false);
            root.transform.position=position; root.AddComponent<BoxCollider>().size=size;
        }
        private void Bridge()
        {
            const int sections=22;
            var vertices=new Vector3[(sections+1)*2]; var indices=new int[sections*6];
            for (var i=0;i<=sections;i++)
            {
                var x=8.2f+i*(7.7f/sections);
                var t=Mathf.Clamp01((x-9)/6.12f);
                var height=x<9 ? Mathf.Lerp(0,.23f,(x-8.2f)/.8f) : x>15.12f ? Mathf.Lerp(.23f,0,(x-15.12f)/.78f) : .23f+Mathf.Sin(t*Mathf.PI)*.68f;
                vertices[i*2]=new Vector3(x,height,5.02f); vertices[i*2+1]=new Vector3(x,height,6.98f);
                if(i==0)continue;
                var k=(i-1)*6; var a=(i-1)*2;
                indices[k]=a;indices[k+1]=a+1;indices[k+2]=a+3;
                indices[k+3]=a;indices[k+4]=a+3;indices[k+5]=a+2;
            }
            bridge=new Mesh { name="Smooth bridge walking surface",vertices=vertices,triangles=indices };
            bridge.RecalculateNormals();
            var floor=new GameObject("Bridge walkway");floor.transform.SetParent(transform,false);
            floor.AddComponent<MeshCollider>().sharedMesh=bridge;
        }
        private void OnDestroy() { if(bridge!=null)Destroy(bridge); }
    }
}
