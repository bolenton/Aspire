using System;
using System.Collections.Generic;
using System.Linq;
using Lantern.Core.Content;
using UnityEngine;
using UnityEngine.UI;

namespace Lantern.Unity.Presentation
{
    /// <summary>Touch chimes over the world, with spoken labels and shape as well as color cues.</summary>
    public sealed class MelodyPanel : MonoBehaviour
    {
        private readonly Dictionary<SolfegeNote,RectTransform> pads = new Dictionary<SolfegeNote,RectTransform>();
        private readonly List<Image> progress = new List<Image>();
        private SolfegeNote? sounding;
        private float soundedAt;
        internal void Initialize(HudElements ui, IReadOnlyList<SolfegeNote> notes, Action<SolfegeNote> play, Action repeat, Action back)
        {
            var curtain=ui.Rect("Song touch shield",transform,Vector2.zero,Vector2.one);
            curtain.gameObject.AddComponent<Image>().color=new Color(0,0,0,.08f);
            var panel=ui.Rect("Listening garden chimes",transform,new Vector2(.15f,.035f),new Vector2(.85f,.34f));
            ui.Panel(panel).color=new Color(.025f,.07f,.085f,.94f);
            var unique=notes.Distinct().OrderBy(n=>(int)n).ToArray();
            var colors=new[] {new Color(1,.73f,.26f),new Color(.45f,.86f,.78f),new Color(1,.53f,.34f),new Color(.73f,.63f,.95f),new Color(.69f,.83f,.38f)};
            for(var i=0;i<unique.Length;i++)
            {
                var note=unique[i]; var center=new Vector2((i+1f)/(unique.Length+1),.48f);
                var rect=ui.Rect(note.ToString(),panel,center,center);rect.sizeDelta=Vector2.one*112;
                var disc=rect.gameObject.AddComponent<ControlGlyph>();disc.Shape=ControlGlyph.Kind.Disc;disc.color=colors[i%colors.Length];
                var button=rect.gameObject.AddComponent<Button>();button.targetGraphic=disc;button.onClick.AddListener(()=>play(note));
                var action=rect.gameObject.AddComponent<AccessibleAction>();action.Button=button;
                action.Label=ui.Text("Spoken note",rect,note+", chime "+(i+1));action.Label.color=Color.clear;
                // One, two, three marks distinguish notes without relying on color or reading.
                for(var dot=0;dot<=i;dot++)
                {
                    var mark=ui.Rect("Chime mark",rect,Vector2.one*.5f,Vector2.one*.5f);
                    mark.sizeDelta=new Vector2(9,34+dot*6);mark.anchoredPosition=new Vector2((dot-i*.5f)*15,0);
                    mark.gameObject.AddComponent<Image>().color=new Color(.025f,.09f,.11f);mark.GetComponent<Image>().raycastTarget=false;
                }
                pads[note]=rect;
            }
            for(var i=0;i<notes.Count;i++)
            {
                var p=ui.Rect("Song progress",panel,new Vector2(.5f,.88f),new Vector2(.5f,.88f));
                p.sizeDelta=Vector2.one*11;p.anchoredPosition=new Vector2((i-(notes.Count-1)*.5f)*23,0);
                var dot=p.gameObject.AddComponent<ControlGlyph>();dot.Shape=ControlGlyph.Kind.Disc;dot.color=new Color(.27f,.34f,.35f);dot.raycastTarget=false;
                progress.Add(dot);
            }
            SmallButton(ui,"Hear the song",ControlGlyph.Kind.Replay,new Vector2(.08f,.16f),repeat);
            SmallButton(ui,"Back to adventure",ControlGlyph.Kind.Back,new Vector2(.92f,.16f),back);
        }
        private void SmallButton(HudElements ui,string name,ControlGlyph.Kind symbol,Vector2 anchor,Action invoke)
        {
            var root=ui.Rect(name,transform,anchor,anchor);root.sizeDelta=Vector2.one*88;
            var disc=root.gameObject.AddComponent<ControlGlyph>();disc.Shape=ControlGlyph.Kind.Disc;disc.color=new Color(.025f,.07f,.085f);
            var button=root.gameObject.AddComponent<Button>();button.targetGraphic=disc;button.onClick.AddListener(()=>invoke());
            var inner=ui.Rect("Symbol",root,Vector2.one*.14f,Vector2.one*.86f);
            var glyph=inner.gameObject.AddComponent<ControlGlyph>();glyph.Shape=symbol;glyph.color=new Color(1,.79f,.39f);glyph.raycastTarget=false;
            var accessible=root.gameObject.AddComponent<AccessibleAction>();accessible.Button=button;
            accessible.Label=ui.Text("Spoken action",root,name);accessible.Label.color=Color.clear;
        }
        public void Highlight(SolfegeNote note) { sounding=note;soundedAt=Time.unscaledTime; }
        public void SetProgress(int completed)
        { for(var i=0;i<progress.Count;i++) progress[i].color=i<completed ? new Color(1,.81f,.38f) : new Color(.27f,.34f,.35f); }
        private void Update()
        {
            var pulse=Mathf.Sin(Mathf.Clamp01((Time.unscaledTime-soundedAt)/.45f)*Mathf.PI)*.08f;
            foreach(var pair in pads) pair.Value.localScale=Vector3.one*(1+(pair.Key==sounding ? pulse : 0));
        }
    }
}
