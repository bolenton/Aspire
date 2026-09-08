using System;
using System.Collections.Generic;
using Lantern.Core.Gameplay;
using Lantern.Core.Content;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem.UI;
using UnityEngine.UI;

namespace Lantern.Unity.Presentation
{
    public sealed class AdventureHud : MonoBehaviour
    {
        private HudElements ui;
        private ScreenReaderPresenter accessibility;
        private RectTransform safeArea, content, narrationPanel;
        private ScrollRect choicesScroll;
        private Text caption;
        private Button actionButton;
        private string currentCaption = "Welcome to Lantern.";
        private string currentAction = "Explore";
        private string currentPageTitle;
        private IReadOnlyList<(string label, Action action)> currentChoices;
        private WorldPalette palette;
        private CalibrationProfile profile;
        private Rect lastSafeArea;
        private bool titlePage;
        private MelodyPanel melody;
        private GameObject titleArtwork;
        private VoiceIndicator voiceIndicator;
        private VoiceState voiceState;
        private bool voiceMode;
        private GameObject voiceControl;
        public bool IsPlayingSong=>melody!=null;
        public event Action Guide, Interact, Talk, Repeat, Stop, Settings;
        public event Action<float, float> Step;
        public bool IsAdventure { get; private set; }
        public string PageTitle => currentPageTitle ?? "Taking a break";

        public void Initialize(WorldPalette worldPalette, CalibrationProfile calibration)
        {
            palette = worldPalette; profile = calibration;
            ui = new HudElements(palette) { TextScale = Mathf.Clamp((float)profile.TextScale / 2, .85f, 2) };
            var canvas = gameObject.AddComponent<Canvas>(); canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = gameObject.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1280, 720); scaler.matchWidthOrHeight = 1;
            gameObject.AddComponent<GraphicRaycaster>();
            var events = new GameObject("Input events", typeof(EventSystem), typeof(InputSystemUIInputModule));
            events.GetComponent<InputSystemUIInputModule>().AssignDefaultActions();
            accessibility = gameObject.AddComponent<ScreenReaderPresenter>();
            safeArea = ui.Rect("Safe area", transform, Vector2.zero, Vector2.one);
            ApplySafeArea();
            IconButton(ControlGlyph.Kind.Microphone,"Voice mode",new Vector2(1,0),new Vector2(-76,86),() => Talk?.Invoke(),safeArea);
            voiceControl.SetActive(false);
        }
        private void ApplySafeArea()
        {
            var area = Screen.safeArea;
            lastSafeArea = area;
            safeArea.anchorMin = new Vector2(area.xMin / Screen.width, area.yMin / Screen.height);
            safeArea.anchorMax = new Vector2(area.xMax / Screen.width, area.yMax / Screen.height);
        }
        private void Update() { if (safeArea != null && lastSafeArea != Screen.safeArea) ApplySafeArea(); }
        private void Clear()
        {
            if (content != null) { content.gameObject.SetActive(false); Destroy(content.gameObject); }
            content = ui.Rect("Page", safeArea, Vector2.zero, Vector2.one);
            caption = null;
            melody = null;
            narrationPanel = null;
            titlePage = false;
            if(voiceControl!=null){voiceControl.SetActive(voiceMode);voiceControl.transform.SetAsLastSibling();}
            if (titleArtwork != null) { Destroy(titleArtwork); titleArtwork = null; }
        }
        public void ShowTitle(IReadOnlyList<(string label, Action action)> options)
        {
            Clear(); IsAdventure = false; titlePage = true; currentChoices = options;
            var artRect = ui.Rect("Meadow title illustration", transform, Vector2.zero, Vector2.one);
            artRect.SetAsFirstSibling();
            titleArtwork = artRect.gameObject;
            var art = artRect.gameObject.AddComponent<RawImage>();
            art.texture = Resources.Load<Texture2D>("LanternMeadow");
            art.raycastTarget = false;
            var ratio = artRect.gameObject.AddComponent<AspectRatioFitter>();
            ratio.aspectMode = AspectRatioFitter.AspectMode.EnvelopeParent;
            ratio.aspectRatio = art.texture != null ? (float)art.texture.width/art.texture.height : 16f/9;
            var panel = ui.Rect("Welcome", content, new Vector2(.025f,.05f),new Vector2(.52f,.95f));
            var background = ui.Panel(panel);
            background.color = new Color(.025f,.065f,.07f,.94f);
            var title = ui.Text("Lantern title",panel,"LANTERN",68);
            title.fontSize = 68;
            title.color = WorldPalette.Hex("FFE0A0");
            title.fontStyle = FontStyle.Bold;
            title.rectTransform.anchorMin = new Vector2(.07f,.73f);
            title.rectTransform.anchorMax = new Vector2(.95f,.94f);
            caption = ui.Text("Welcome words",panel,"A little light.\nA friend beside you.",31);
            caption.rectTransform.anchorMin = new Vector2(.07f,.55f);
            caption.rectTransform.anchorMax = new Vector2(.93f,.77f);
            caption.color = WorldPalette.Hex("FFF5DD");
            var buttons = ui.Rect("Welcome choices",panel,new Vector2(.07f,.065f),new Vector2(.93f,.52f));
            var scroll = buttons.gameObject.AddComponent<ScrollRect>();
            buttons.gameObject.AddComponent<RectMask2D>();
            scroll.horizontal = false; scroll.inertia = false;
            var body = ui.Rect("Welcome buttons",buttons,new Vector2(0,1),Vector2.one);
            body.pivot = new Vector2(.5f,1);
            var layout = body.gameObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 16; layout.childControlHeight = layout.childControlWidth = true;
            layout.childForceExpandHeight = false;
            body.gameObject.AddComponent<ContentSizeFitter>().verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            scroll.viewport = buttons; scroll.content = body;
            for (var i=0; i<options.Count; i++) ui.Button(body,options[i].label,options[i].action,i==0);
            RefreshAccessibility();
        }
        public event Action<Vector3> Movement;
        public event Action MovementReleased;
        public event Action<Vector2> WorldTapped;

        public void ShowAdventure(string action)
        {
            Clear(); IsAdventure = true; currentPageTitle="Exploring"; currentAction = action;
            var surface = ui.Rect("Touch anywhere to move",content,Vector2.zero,Vector2.one);
            surface.gameObject.AddComponent<Image>().color = Color.clear;
            var movement = surface.gameObject.AddComponent<TouchMovement>();
            movement.Initialize(profile.ShowMovementControl);
            movement.Moved += direction => Movement?.Invoke(direction);
            movement.Released += () => MovementReleased?.Invoke();
            movement.Tapped += position => WorldTapped?.Invoke(position);
            // Speech remains available to VoiceOver even when visual captions are hidden.
            var words = ui.Rect("Companion narration",content,new Vector2(.025f,.80f),new Vector2(.78f,.96f));
            caption = ui.Text("Ember's words",words,profile.ShowCaptions ? BriefCaption(currentCaption) : currentCaption,30);
            if (profile.ShowCaptions)
            {
                var panel = ui.Panel(words); panel.raycastTarget = false;
                caption.rectTransform.offsetMin = new Vector2(20,12);
                caption.rectTransform.offsetMax = new Vector2(-20,-12);
            }
            else caption.color = Color.clear;
            IconButton(ControlGlyph.Kind.Pause,"Pause and options",new Vector2(1,1),new Vector2(-62,-58),ShowMore);
            voiceControl.SetActive(true);voiceControl.transform.SetAsLastSibling();
            IconButton(ControlGlyph.Kind.Compass,"Let Ember guide me",new Vector2(1,0),new Vector2(-76,228),() => Guide?.Invoke());
            RefreshAccessibility();
        }

        public void ShowMelody(string words,IReadOnlyList<SolfegeNote> notes,Action<SolfegeNote> play,Action repeat,Action back)
        {
            Clear(); IsAdventure=false; currentPageTitle="Playing an untimed chime song";
            var songWords=ui.Rect("Song caption",content,new Vector2(.15f,.78f),new Vector2(.85f,.96f));
            caption=ui.Text("Spoken song",songWords,words,28);caption.color=profile.ShowCaptions ? palette.Foreground : Color.clear;
            if(profile.ShowCaptions){var panel=ui.Panel(songWords);panel.raycastTarget=false;}
            melody=content.gameObject.AddComponent<MelodyPanel>();
            melody.Initialize(ui,notes,play,repeat,back);
            RefreshAccessibility();
        }
        public void HighlightNote(SolfegeNote note) => melody?.Highlight(note);
        public void SetSongProgress(int completed) => melody?.SetProgress(completed);

        private void IconButton(ControlGlyph.Kind symbol,string label,Vector2 anchor,Vector2 offset,Action action,Transform parent=null)
        {
            var rect = ui.Rect(label,parent ?? content,anchor,anchor);
            rect.sizeDelta = new Vector2(88,88); rect.anchoredPosition = offset;
            var disc = rect.gameObject.AddComponent<ControlGlyph>();
            disc.Shape = ControlGlyph.Kind.Disc; disc.color = palette.Panel;
            var button = rect.gameObject.AddComponent<Button>(); button.targetGraphic = disc;
            button.onClick.AddListener(() => action());
            var glyphRect = ui.Rect("Symbol",rect,new Vector2(.12f,.12f),new Vector2(.88f,.88f));
            var glyph = glyphRect.gameObject.AddComponent<ControlGlyph>();
            glyph.Shape = symbol; glyph.color = palette.Accent; glyph.raycastTarget = false;
            var accessible = rect.gameObject.AddComponent<AccessibleAction>();
            accessible.Button = button;
            accessible.Label = ui.Text("Spoken label",rect,label);
            accessible.Label.color = Color.clear;
            if (symbol == ControlGlyph.Kind.Microphone)
            {
                voiceControl=rect.gameObject;
                voiceIndicator = rect.gameObject.AddComponent<VoiceIndicator>();
                voiceIndicator.Initialize(ui,palette,accessible);
                voiceIndicator.Set(voiceState,voiceMode);
            }
        }
        public void SetVoiceState(VoiceState state)
        {
            if(voiceState==state)return;
            voiceState=state;
            if(voiceIndicator!=null)voiceIndicator.Set(state,voiceMode);
        }
        public void SetVoiceMode(bool active)
        {
            voiceMode=active;
            voiceControl.SetActive(active || IsAdventure);
            voiceControl.transform.SetAsLastSibling();
            voiceIndicator.Set(voiceState,active);
            if(caption!=null)RefreshAccessibility();
        }
        public void SetVoiceLevel(float level)=>voiceIndicator?.SetLevel(level);
        private void ShowMore()
        {
            Stop?.Invoke();
            ShowChoices("Take your time", new List<(string, Action)>
            {
                ("Repeat", () => Repeat?.Invoke()),
                ("Read Ember's words", () => ShowChoices(currentCaption, new List<(string,Action)> { ("Back to adventure", ResumeAdventure) })),
                ("Guide me", () => { ResumeAdventure(); Guide?.Invoke(); }),
                ("Interact here", () => { ResumeAdventure(); Interact?.Invoke(); }),
                ("Comfort settings", () => Settings?.Invoke()),
                ("Back to adventure", ResumeAdventure)
            });
        }
        public void ResumeAdventure() => ShowAdventure(currentAction);
        public void SetAction(string value)
        {
            currentAction = value;
            if (actionButton != null) actionButton.GetComponent<AccessibleAction>().Label.text = value;
        }
        public void Say(string value)
        {
            currentCaption = value;
            if (caption != null) caption.text = IsAdventure && profile.ShowCaptions ? BriefCaption(value) : value;
            FitNarration();
        }
        private static string BriefCaption(string words)
        {
            var end = words.IndexOfAny(new[] { '.', '!', '?' });
            if (end >= 0 && end < 120) return words.Substring(0,end+1);
            if (words.Length <= 120) return words;
            var space = words.LastIndexOf(' ',110);
            return words.Substring(0,space > 0 ? space : 110) + "…";
        }
        private void FitNarration()
        {
            if (narrationPanel == null || caption == null) return;
            Canvas.ForceUpdateCanvases();
            var height = Mathf.Clamp(caption.preferredHeight + 40, 100, safeArea.rect.height * .27f);
            narrationPanel.offsetMin = new Vector2(20, -height - 16);
            caption.GetComponentInParent<ScrollRect>().verticalNormalizedPosition = 1;
        }
        public void ShowChoices(string title, IReadOnlyList<(string label, Action action)> options)
        {
            Clear();
            IsAdventure = false;
            currentPageTitle = title;
            currentChoices = options;
            ui.Panel(content);
            var titleRect = ui.Rect("Title area", content, new Vector2(.05f, 1), new Vector2(.95f, 1));
            caption = ui.ScrollableText("Page title", titleRect, title, 30);
            Canvas.ForceUpdateCanvases();
            var titleHeight = Mathf.Clamp(caption.preferredHeight + 20, 100, safeArea.rect.height * .5f);
            titleRect.offsetMin = new Vector2(0, -titleHeight - 16);
            titleRect.offsetMax = new Vector2(0, -16);
            var viewport = ui.Rect("Choices viewport", content, new Vector2(.05f, .05f), new Vector2(.95f, 1));
            viewport.offsetMax = new Vector2(0, -titleHeight - 36);
            viewport.gameObject.AddComponent<RectMask2D>();
            var scroll = viewport.gameObject.AddComponent<ScrollRect>(); scroll.horizontal = false;
            scroll.inertia = false;
            scroll.movementType = ScrollRect.MovementType.Clamped;
            choicesScroll = scroll;
            var body = ui.Rect("Choices", viewport, new Vector2(0, 1), Vector2.one);
            body.pivot = new Vector2(.5f, 1);
            var layout = body.gameObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 18; layout.childControlHeight = layout.childControlWidth = true; layout.childForceExpandHeight = false;
            var fit = body.gameObject.AddComponent<ContentSizeFitter>(); fit.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            scroll.content = body; scroll.viewport = viewport;
            foreach (var (label, action) in options) ui.Button(body, label, action);
            RefreshAccessibility();
        }
        public void RefreshTheme()
        {
            ui.TextScale = Mathf.Clamp((float)profile.TextScale / 2, .85f, 2);
            if (titlePage) ShowTitle(currentChoices);
            else if (IsAdventure) ResumeAdventure();
            else
            {
                var position = choicesScroll.verticalNormalizedPosition;
                ShowChoices(currentPageTitle, currentChoices);
                choicesScroll.verticalNormalizedPosition = position;
            }
        }
        private void RefreshAccessibility()
        { Canvas.ForceUpdateCanvases(); accessibility.Rebuild(caption); }
    }
}
