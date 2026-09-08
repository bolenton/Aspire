using UnityEngine;

namespace Lantern.Unity.World
{
    /// <summary>A quiet world-space ring identifies the current landmark without a text overlay.</summary>
    public sealed class DestinationMarker : MonoBehaviour
    {
        private Mesh mesh;
        private Material material;
        private Transform target;
        public void Initialize()
        {
            const int count=64;
            var vertices=new Vector3[count*2];var indices=new int[count*6];
            for(var i=0;i<count;i++)
            {
                var a=i*Mathf.PI*2/count;var direction=new Vector3(Mathf.Cos(a),0,Mathf.Sin(a));
                vertices[i*2]=direction*1.12f;vertices[i*2+1]=direction*1.23f;
                var j=(i+1)%count;var k=i*6;
                indices[k]=i*2;indices[k+1]=j*2;indices[k+2]=j*2+1;
                indices[k+3]=i*2;indices[k+4]=j*2+1;indices[k+5]=i*2+1;
            }
            mesh=new Mesh {name="Destination inlay",vertices=vertices,triangles=indices};mesh.RecalculateNormals();
            gameObject.AddComponent<MeshFilter>().sharedMesh=mesh;
            material=new Material(Shader.Find("Universal Render Pipeline/Unlit"));
            material.SetColor("_BaseColor",new Color(1,.73f,.22f));
            gameObject.AddComponent<MeshRenderer>().sharedMaterial=material;
        }
        public void Follow(Transform destination) { target=destination;gameObject.SetActive(target!=null); }
        private void LateUpdate()
        { if(target!=null)transform.position=target.position+Vector3.up*.035f; }
        private void OnDestroy() { Destroy(mesh);Destroy(material); }
    }
}
