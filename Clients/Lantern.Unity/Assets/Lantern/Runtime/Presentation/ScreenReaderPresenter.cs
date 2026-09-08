using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Accessibility;
using UnityEngine.UI;

namespace Lantern.Unity.Presentation
{
    public sealed class ScreenReaderPresenter : MonoBehaviour
    {
        private AccessibilityHierarchy hierarchy;
        private readonly List<(AccessibleAction action, AccessibilityNode node)> entries = new List<(AccessibleAction, AccessibilityNode)>();
        private readonly Vector3[] corners = new Vector3[4];
        private AccessibilityNode lastFocused;
        private Text narration;
        private AccessibilityNode narrationNode;
        public void Rebuild(Text words)
        {
            entries.Clear();
            lastFocused = null;
            hierarchy = new AccessibilityHierarchy();
            narration = words;
            narrationNode = hierarchy.AddNode(words.text);
            narrationNode.role = AccessibilityRole.StaticText;
            foreach (var action in GetComponentsInChildren<AccessibleAction>())
            {
                var node = hierarchy.AddNode(action.Label.text);
                node.role = AccessibilityRole.Button;
                node.invoked += () => { if (action != null && action.Button.IsInteractable()) action.Button.onClick.Invoke(); return true; };
                entries.Add((action, node));
            }
            UpdateFrames();
            AssistiveSupport.activeHierarchy = hierarchy;
        }
        private void OnEnable() => AssistiveSupport.screenReaderStatusChanged += ReaderChanged;
        private void ReaderChanged(bool enabled) { if (enabled && hierarchy != null) AssistiveSupport.activeHierarchy = hierarchy; }
        private void LateUpdate() => UpdateFrames();
        private void UpdateFrames()
        {
            if (narration != null && narrationNode != null)
            {
                narrationNode.label = narration.text;
                var scroll = narration.GetComponentInParent<ScrollRect>();
                narrationNode.frame = Frame(scroll != null ? scroll.viewport : narration.rectTransform);
            }
            foreach (var (action, node) in entries)
            {
                if (action == null) continue;
                if (node.isFocused && lastFocused != node)
                {
                    lastFocused = node;
                    Reveal(action);
                }
                node.label = action.Label.text;
                node.state = action.Button.IsInteractable() ? AccessibilityState.None : AccessibilityState.Disabled;
                node.frame = Frame((RectTransform)action.transform);
            }
        }
        private Rect Frame(RectTransform rect)
        {
            rect.GetWorldCorners(corners);
            var min = RectTransformUtility.WorldToScreenPoint(null, corners[0]);
            var max = RectTransformUtility.WorldToScreenPoint(null, corners[2]);
            return new Rect(min.x, Screen.height - max.y, max.x - min.x, max.y - min.y);
        }
        private static void Reveal(AccessibleAction action)
        {
            var scroll = action.GetComponentInParent<ScrollRect>();
            if (scroll == null) return;
            var bounds = RectTransformUtility.CalculateRelativeRectTransformBounds(scroll.viewport, action.transform);
            var viewport = scroll.viewport.rect;
            var delta = bounds.min.y < viewport.yMin ? viewport.yMin - bounds.min.y
                : bounds.max.y > viewport.yMax ? viewport.yMax - bounds.max.y : 0;
            var position = scroll.content.anchoredPosition;
            position.y = Mathf.Clamp(position.y + delta, 0, Mathf.Max(0, scroll.content.rect.height - viewport.height));
            scroll.content.anchoredPosition = position;
        }
        private void OnDisable()
        {
            AssistiveSupport.screenReaderStatusChanged -= ReaderChanged;
            AssistiveSupport.activeHierarchy = null;
        }
    }
}
