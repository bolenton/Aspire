using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace Lantern.Unity.Editor
{
    internal static class LanternDiagnostics
    {
        [MenuItem("Lantern/Diagnostics/Check visible button targets")]
        private static void CheckButtons()
        {
            if (!EditorApplication.isPlaying || EventSystem.current == null)
            {
                Debug.Log("Enter Play mode before checking Lantern's button targets.");
                return;
            }
            var hits = new List<RaycastResult>();
            var corners = new Vector3[4];
            foreach (var button in Object.FindObjectsByType<Button>(FindObjectsSortMode.None))
            {
                var rect = (RectTransform)button.transform;
                rect.GetWorldCorners(corners);
                var center = RectTransformUtility.WorldToScreenPoint(null, (corners[0] + corners[2]) * .5f);
                if (center.y < 0 || center.y > Screen.height) continue;
                hits.Clear();
                EventSystem.current.RaycastAll(new PointerEventData(EventSystem.current) { position = center }, hits);
                var target = hits.Count > 0 ? hits[0].gameObject : null;
                var targetName = target != null ? target.name : "none";
                Debug.Log($"Lantern button '{button.name}' at {center}: first hit '{targetName}', expected '{button.name}'.");
            }
        }
    }
}
