using System;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace Lantern.Unity.Presentation
{
    /// <summary>A floating joystick: the gesture origin is wherever the child puts a finger.</summary>
    public sealed class TouchMovement : MonoBehaviour, IPointerDownHandler, IDragHandler, IPointerUpHandler
    {
        public event Action<Vector3> Moved;
        public event Action Released;
        public event Action<Vector2> Tapped;
        private RectTransform ring, thumb;
        private Vector2 origin;
        private Vector3 right, forward;
        private int? pointer;
        private float maximumDistance, radius, pressedAt;
        private bool alwaysVisible;

        public void Initialize(bool visible)
        {
            alwaysVisible = visible;
            ring = ControlDisc("Movement area",transform,180,new Color(.03f,.10f,.12f,.5f));
            thumb = ControlDisc("Movement thumb",ring,66,new Color(1,.83f,.39f,.85f));
            Rest();
        }

        private static RectTransform ControlDisc(string name, Transform parent, float size, Color color)
        {
            var root = new GameObject(name,typeof(RectTransform));
            var rect = (RectTransform)root.transform;
            rect.SetParent(parent,false); rect.sizeDelta = Vector2.one*size;
            rect.anchorMin = rect.anchorMax = new Vector2(.5f,.5f);
            var graphic = root.AddComponent<ControlGlyph>();
            graphic.Shape = ControlGlyph.Kind.Disc; graphic.color = color; graphic.raycastTarget = false;
            return rect;
        }

        public void OnPointerDown(PointerEventData data)
        {
            if (pointer.HasValue) return;
            pointer = data.pointerId;
            Released?.Invoke();
            origin = data.position; maximumDistance = 0; pressedAt = Time.unscaledTime;
            var camera = Camera.main;
            forward = camera == null ? Vector3.forward : Vector3.ProjectOnPlane(camera.transform.forward,Vector3.up).normalized;
            right = Vector3.Cross(Vector3.up,forward);
            radius = Mathf.Clamp(Screen.height*.12f,65,180);
            RectTransformUtility.ScreenPointToLocalPointInRectangle((RectTransform)transform,origin,data.pressEventCamera,out var local);
            ring.anchorMin = ring.anchorMax = Vector2.one*.5f;
            ring.anchoredPosition = local;
            ring.gameObject.SetActive(true);
            thumb.anchoredPosition = Vector2.zero;
        }

        public void OnDrag(PointerEventData data)
        {
            if (pointer != data.pointerId) return;
            var delta = data.position-origin;
            maximumDistance = Mathf.Max(maximumDistance,delta.magnitude);
            var value = Vector2.ClampMagnitude(delta/radius,1);
            // A broad dead zone makes resting fingers harmless.
            var magnitude = Mathf.InverseLerp(.16f,1,value.magnitude);
            Moved?.Invoke((right*value.x+forward*value.y).normalized*magnitude);
            thumb.anchoredPosition = value*57;
        }

        public void OnPointerUp(PointerEventData data)
        {
            if (pointer != data.pointerId) return;
            pointer = null;
            Released?.Invoke();
            if (maximumDistance < 14 && Time.unscaledTime-pressedAt < .6f) Tapped?.Invoke(data.position);
            Rest();
        }

        private void Rest()
        {
            if (ring == null) return;
            ring.gameObject.SetActive(alwaysVisible);
            ring.anchorMin = ring.anchorMax = new Vector2(.13f,.20f);
            ring.anchoredPosition = Vector2.zero;
            thumb.anchoredPosition = Vector2.zero;
        }

        private void OnDisable() { pointer = null; Released?.Invoke(); Rest(); }
        private void OnApplicationFocus(bool focused) { if (!focused) { pointer = null; Released?.Invoke(); Rest(); } }
        private void OnApplicationPause(bool paused) { if (paused) { pointer = null; Released?.Invoke(); Rest(); } }
    }
}
