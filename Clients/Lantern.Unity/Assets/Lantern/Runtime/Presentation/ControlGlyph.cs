using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace Lantern.Unity.Presentation
{
    // Small cached UI sprites keep the controls crisp without a font or an icon dependency.
    public sealed class ControlGlyph : Image
    {
        public enum Kind { Disc, Pause, Microphone, Compass, Replay, Back, Ring }
        private static readonly Dictionary<Kind,Sprite> sprites = new Dictionary<Kind,Sprite>();
        public Kind Shape { set { sprite = Icon(value); type = Type.Simple; preserveAspect = true; } }

        private static Sprite Icon(Kind kind)
        {
            if (sprites.TryGetValue(kind,out var existing)) return existing;
            const int size = 128;
            var texture = new Texture2D(size,size,TextureFormat.RGBA32,false);
            texture.name = "Lantern " + kind;
            var pixels = new Color[size*size];
            for (var y=0;y<size;y++) for (var x=0;x<size;x++)
            {
                var p = new Vector2((x+.5f)/size*2-1,(y+.5f)/size*2-1);
                float edge;
                if (kind == Kind.Disc) edge = .98f-p.magnitude;
                else if (kind == Kind.Ring) edge = .035f-Mathf.Abs(p.magnitude-.91f);
                else if (kind == Kind.Pause)
                    edge = Mathf.Max(Rectangle(p-new Vector2(-.24f,0),new Vector2(.085f,.42f)),Rectangle(p-new Vector2(.24f,0),new Vector2(.085f,.42f)));
                else if (kind == Kind.Microphone)
                {
                    var head = .15f-new Vector2(p.x,Mathf.Max(Mathf.Abs(p.y-.19f)-.17f,0)).magnitude;
                    var cup = Mathf.Min(.035f-Mathf.Abs(p.magnitude-.36f),.02f-p.y);
                    var stem = Rectangle(p-new Vector2(0,-.42f),new Vector2(.035f,.13f));
                    var foot = Rectangle(p-new Vector2(0,-.54f),new Vector2(.18f,.035f));
                    edge = Mathf.Max(head,cup,stem,foot);
                }
                else if (kind == Kind.Back)
                    edge = Mathf.Min(.075f-Mathf.Abs(p.x+.22f-Mathf.Abs(p.y)*.85f),.49f-Mathf.Abs(p.y));
                else if (kind == Kind.Replay)
                {
                    var arc = Mathf.Min(.045f-Mathf.Abs(p.magnitude-.39f),Mathf.Max(.10f-p.x,-p.y));
                    var arrow = Mathf.Min(.20f-Mathf.Abs(p.x-.27f),.45f-p.y,p.y-.05f);
                    edge = Mathf.Max(arc,arrow);
                }
                else
                {
                    var rim = .025f-Mathf.Abs(p.magnitude-.47f);
                    var triangle = Mathf.Min(.53f-p.y,p.y+.24f,.24f-(p.y+.24f)*.31f-Mathf.Abs(p.x));
                    edge = Mathf.Max(rim,triangle);
                }
                pixels[y*size+x] = new Color(1,1,1,Mathf.Clamp01(edge*size*.5f+.5f));
            }
            texture.SetPixels(pixels); texture.Apply(false,true);
            var result = Sprite.Create(texture,new Rect(0,0,size,size),Vector2.one*.5f,100);
            sprites.Add(kind,result); return result;
        }
        private static float Rectangle(Vector2 p,Vector2 halfSize) => Mathf.Min(halfSize.x-Mathf.Abs(p.x),halfSize.y-Mathf.Abs(p.y));
    }
}
