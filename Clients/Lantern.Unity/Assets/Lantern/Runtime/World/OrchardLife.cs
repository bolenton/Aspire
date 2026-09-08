using UnityEngine;

namespace Lantern.Unity.World
{
    public sealed class OrchardLife : MonoBehaviour
    {
        private Transform[] fireflies;
        private Light hearth;
        private Material glow;
        private bool awake,restored;
        public void Initialize()
        {
            glow=new Material(Shader.Find("Universal Render Pipeline/Lit"));glow.color=new Color(1,.78f,.28f);glow.EnableKeyword("_EMISSION");glow.SetColor("_EmissionColor",new Color(1,.62f,.1f)*2);
            fireflies=new Transform[24];
            for(var i=0;i<fireflies.Length;i++)
            {
                var mote=GameObject.CreatePrimitive(PrimitiveType.Sphere);mote.name="Orchard firefly";Destroy(mote.GetComponent<Collider>());mote.transform.SetParent(transform);mote.transform.localScale=Vector3.one*.08f;mote.GetComponent<Renderer>().sharedMaterial=glow;fireflies[i]=mote.transform;mote.SetActive(false);
            }
            hearth=new GameObject("Firefly home light").AddComponent<Light>();hearth.transform.SetParent(transform);hearth.transform.position=new Vector3(-34,2.2f,-5);hearth.type=LightType.Point;hearth.color=new Color(1,.7f,.26f);hearth.range=8;hearth.intensity=0;
        }
        public void Refresh(bool waking,bool planted){awake=waking;restored=planted;foreach(var mote in fireflies)mote.gameObject.SetActive(awake);}
        private void Update()
        {
            if(fireflies==null)return;
            hearth.intensity=Mathf.MoveTowards(hearth.intensity,restored?3:0,Time.deltaTime);
            if(!awake)return;
            var center=restored?new Vector3(-34,1.9f,-5):new Vector3(-31,1.8f,6);
            for(var i=0;i<fireflies.Length;i++)
            {
                var angle=i*2.4f+Time.time*.12f;var radius=1.3f+(i%5)*.48f;
                fireflies[i].position=center+new Vector3(Mathf.Cos(angle)*radius,Mathf.Sin(angle*.8f+i)*.65f,Mathf.Sin(angle)*radius);
            }
        }
        private void OnDestroy(){if(glow!=null)Destroy(glow);}
    }
}
