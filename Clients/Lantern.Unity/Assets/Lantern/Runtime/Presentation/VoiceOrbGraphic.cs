using UnityEngine;
using UnityEngine.UI;

namespace Lantern.Unity.Presentation
{
    // Soft continuous motion, with different shapes for listening, thought and reply.
    public sealed class VoiceOrbGraphic : MaskableGraphic
    {
        public VoiceState State;
        public float Level;
        private float smoothedLevel;
        protected override void OnPopulateMesh(VertexHelper mesh)
        {
            mesh.Clear();
            var center=rectTransform.rect.center;
            var radius=Mathf.Min(rectTransform.rect.width,rectTransform.rect.height)*.5f;
            var time=Time.unscaledTime;
            var breath=1+.035f*Mathf.Sin(time*2);
            var blue=new Color(.18f,.70f,1,.95f);
            var white=new Color(.91f,.99f,1,1);
            Ring(mesh,center,radius*.94f*breath,radius*.83f*breath,new Color(.30f,.82f,1,.25f));
            Ring(mesh,center,radius*.81f,radius*.76f,white);
            Disc(mesh,center,radius*.74f,new Color(.025f,.26f,.46f),blue);
            if(State==VoiceState.Thinking)
            {
                for(var i=0;i<3;i++)
                {
                    var angle=time*.95f+i*Mathf.PI*2/3;
                    Disc(mesh,center+new Vector2(Mathf.Cos(angle),Mathf.Sin(angle))*radius*.34f,radius*.10f,white,white);
                }
            }
            else
            {
                var active=State==VoiceState.Listening || State==VoiceState.Speaking;
                for(var i=0;i<5;i++)
                {
                    var sway=(Mathf.Sin(time*(State==VoiceState.Speaking ? 3.8f:2.2f)+i*.9f)+1)*.5f;
                    var height=active ? radius*(.14f+(smoothedLevel*.60f+.12f)*sway):radius*.14f;
                    var x=center.x+(i-2)*radius*.19f;
                    Bar(mesh,new Vector2(x,center.y),radius*.055f,height,white);
                }
            }
        }
        private static void Disc(VertexHelper mesh,Vector2 center,float radius,Color inside,Color edge)
        {
            const int count=48;var start=mesh.currentVertCount;
            mesh.AddVert(center,inside,Vector2.zero);
            for(var i=0;i<=count;i++)
            {var angle=i*Mathf.PI*2/count;mesh.AddVert(center+new Vector2(Mathf.Cos(angle),Mathf.Sin(angle))*radius,edge,Vector2.zero);if(i>0)mesh.AddTriangle(start,start+i,start+i+1);}
        }
        private static void Ring(VertexHelper mesh,Vector2 center,float outer,float inner,Color tint)
        {
            const int count=64;var start=mesh.currentVertCount;
            for(var i=0;i<=count;i++)
            {
                var angle=i*Mathf.PI*2/count;var direction=new Vector2(Mathf.Cos(angle),Mathf.Sin(angle));
                mesh.AddVert(center+direction*outer,tint,Vector2.zero);mesh.AddVert(center+direction*inner,tint,Vector2.zero);
                if(i==0)continue;var n=start+i*2;mesh.AddTriangle(n-2,n-1,n);mesh.AddTriangle(n,n-1,n+1);
            }
        }
        private static void Bar(VertexHelper mesh,Vector2 center,float width,float height,Color tint)
        {
            var start=mesh.currentVertCount;
            mesh.AddVert(center+new Vector2(-width,-height),tint,Vector2.zero);mesh.AddVert(center+new Vector2(-width,height),tint,Vector2.zero);
            mesh.AddVert(center+new Vector2(width,height),tint,Vector2.zero);mesh.AddVert(center+new Vector2(width,-height),tint,Vector2.zero);
            mesh.AddTriangle(start,start+1,start+2);mesh.AddTriangle(start,start+2,start+3);
            Disc(mesh,center+Vector2.up*height,width,tint,tint);Disc(mesh,center-Vector2.up*height,width,tint,tint);
        }
        private void Update()
        {
            smoothedLevel=Mathf.Lerp(smoothedLevel,Mathf.Clamp01(Level),1-Mathf.Exp(-12*Time.unscaledDeltaTime));
            SetVerticesDirty();
        }
    }
}
