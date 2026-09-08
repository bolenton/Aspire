using System;
using UnityEngine;
using UnityEngine.UI;

namespace Lantern.Unity.Presentation
{
    internal sealed class HudElements
    {
        private readonly WorldPalette palette;
        private readonly Font font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        private static Sprite rounded;
        public float TextScale { get; set; } = 1;
        public HudElements(WorldPalette palette) => this.palette = palette;
        public RectTransform Rect(string name, Transform parent, Vector2 min, Vector2 max)
        {
            var root = new GameObject(name, typeof(RectTransform));
            var rect = (RectTransform)root.transform;
            rect.SetParent(parent, false);
            rect.anchorMin = min; rect.anchorMax = max;
            rect.offsetMin = rect.offsetMax = Vector2.zero;
            return rect;
        }
        public Text Text(string name, Transform parent, string value, int size = 26)
        {
            var root = Rect(name, parent, Vector2.zero, Vector2.one);
            var label = root.gameObject.AddComponent<Text>();
            label.font = font;
            label.fontSize = Mathf.RoundToInt(size * TextScale);
            label.text = value;
            label.color = palette.Foreground;
            label.alignment = TextAnchor.MiddleLeft;
            label.horizontalOverflow = HorizontalWrapMode.Wrap;
            label.verticalOverflow = VerticalWrapMode.Overflow;
            label.raycastTarget = false;
            return label;
        }
        public Image Panel(RectTransform rect)
        {
            var image = rect.gameObject.AddComponent<Image>();
            image.sprite = Rounded(); image.type = Image.Type.Sliced;
            image.color = palette.Panel; return image;
        }
        private static Sprite Rounded()
        {
            if (rounded != null) return rounded;
            const int size = 64;
            const float radius = 18;
            var texture = new Texture2D(size,size,TextureFormat.RGBA32,false);
            texture.name = "Lantern rounded panel";
            var pixels = new Color[size*size];
            for (var y=0; y<size; y++) for (var x=0; x<size; x++)
            {
                var dx = Mathf.Max(Mathf.Abs(x-31.5f)-(32-radius),0);
                var dy = Mathf.Max(Mathf.Abs(y-31.5f)-(32-radius),0);
                pixels[y*size+x] = new Color(1,1,1,Mathf.Clamp01(radius-Mathf.Sqrt(dx*dx+dy)));
            }
            texture.SetPixels(pixels); texture.Apply(false,true);
            rounded = Sprite.Create(texture,new Rect(0,0,size,size),Vector2.one*.5f,100,0,SpriteMeshType.FullRect,new Vector4(20,20,20,20));
            return rounded;
        }
        public Text ScrollableText(string name, RectTransform parent, string value, int size = 26)
        {
            var viewport = Rect(name + " viewport", parent, Vector2.zero, Vector2.one);
            viewport.gameObject.AddComponent<Image>().color = Color.clear;
            viewport.gameObject.AddComponent<RectMask2D>();
            var scroll = viewport.gameObject.AddComponent<ScrollRect>();
            scroll.horizontal = false;
            scroll.inertia = false;
            scroll.movementType = ScrollRect.MovementType.Clamped;
            var text = Text(name, viewport, value, size);
            text.alignment = TextAnchor.UpperLeft;
            text.rectTransform.anchorMin = new Vector2(0, 1);
            text.rectTransform.anchorMax = Vector2.one;
            text.rectTransform.pivot = new Vector2(.5f, 1);
            text.gameObject.AddComponent<ContentSizeFitter>().verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            scroll.viewport = viewport;
            scroll.content = text.rectTransform;
            return text;
        }
        public Button Button(Transform parent, string title, Action action, bool accent = false)
        {
            var rect = Rect(title, parent, Vector2.zero, Vector2.one);
            var image = Panel(rect);
            image.color = accent ? palette.Accent : palette.Panel;
            var button = rect.gameObject.AddComponent<Button>();
            button.targetGraphic = image;
            var colors = button.colors;
            colors.highlightedColor = new Color(.8f, .88f, 1);
            colors.pressedColor = new Color(.65f, .75f, .85f);
            button.colors = colors;
            var border = rect.gameObject.AddComponent<Outline>(); border.effectColor = palette.Accent * new Color(1,1,1,.45f); border.effectDistance = new Vector2(1, -1);
            var label = Text("Label", rect, title, 28);
            label.fontStyle = FontStyle.Bold;
            label.alignment = TextAnchor.MiddleCenter;
            label.color = accent ? palette.Panel : palette.Foreground;
            label.rectTransform.offsetMin = new Vector2(12, 8);
            label.rectTransform.offsetMax = new Vector2(-12, -8);
            var layout = rect.gameObject.AddComponent<LayoutElement>();
            layout.minHeight = 96; layout.preferredHeight = Mathf.Max(96, 76 * TextScale); layout.flexibleWidth = 1;
            button.onClick.AddListener(() => action());
            var accessible = rect.gameObject.AddComponent<AccessibleAction>(); accessible.Button = button; accessible.Label = label;
            return button;
        }
        public HorizontalLayoutGroup Row(Transform parent, string name)
        {
            var rect = Rect(name, parent, Vector2.zero, Vector2.one);
            var row = rect.gameObject.AddComponent<HorizontalLayoutGroup>();
            row.spacing = 14; row.childControlWidth = row.childControlHeight = true;
            row.childForceExpandWidth = true; row.childForceExpandHeight = false;
            return row;
        }
    }
}
