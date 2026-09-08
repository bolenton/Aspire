using System.Collections.Generic;
using UnityEngine;

namespace Lantern.Unity.World
{
    /// <summary>World-only surface treatment; character faces keep their authored materials.</summary>
    public sealed class MeadowSurfaces : MonoBehaviour
    {
        private readonly List<Material> owned = new List<Material>();
        public void Initialize(Transform landscape)
        {
            var shader = Shader.Find("Lantern/Meadow Surface");
            if (shader == null) throw new System.InvalidOperationException("The meadow surface shader is missing.");
            var cache = new Dictionary<Material,Material>();
            foreach (var renderer in landscape.GetComponentsInChildren<Renderer>())
            {
                var materials = renderer.sharedMaterials;
                for (var i=0;i<materials.Length;i++)
                {
                    var original = materials[i];
                    var name = original.name;
                    if (name.StartsWith("Lantern") || name.StartsWith("Oak • dark iron")) continue;
                    if (!cache.TryGetValue(original,out var surface))
                    {
                        surface = new Material(shader) { name = name };
                        var color = original.HasProperty("baseColorFactor") ? original.GetColor("baseColorFactor") : original.color;
                        surface.SetColor("_BaseColor",color);
                        surface.SetFloat("_Detail",name.StartsWith("Ground") || name.StartsWith("Path") ? 1 : .3f);
                        surface.SetFloat("_Wind",name.StartsWith("Leaves") ? 1 : name.StartsWith("Grass") || name.StartsWith("Flowers") ? .6f : 0);
                        surface.SetFloat("_Water",name.StartsWith("Water") ? 1 : 0);
                        owned.Add(surface); cache.Add(original,surface);
                    }
                    materials[i] = surface;
                }
                renderer.sharedMaterials = materials;
            }
        }
        private void OnDestroy() { foreach (var material in owned) Destroy(material); }
    }
}
