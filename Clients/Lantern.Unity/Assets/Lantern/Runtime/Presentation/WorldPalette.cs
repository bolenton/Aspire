using System.Collections.Generic;
using Lantern.Core.Gameplay;
using UnityEngine;

namespace Lantern.Unity.Presentation
{
    public enum SurfaceRole { Ground, Path, Scenery, Landmark, Companion, Player, Collectible, Water }
    public sealed class WorldPalette
    {
        private sealed class Surface
        {
            public Renderer Renderer;
            public Material[] Original;
            public Material[] Contrast;
            public SurfaceRole Role;
        }
        private readonly List<Surface> surfaces = new List<Surface>();
        public ContrastTheme Theme { get; private set; }
        public Color Background => Theme == ContrastTheme.DarkOnLight ? Hex("F6F2DA") : Hex("09171F");
        public Color Foreground => Theme == ContrastTheme.DarkOnLight ? Hex("11212B") : Theme == ContrastTheme.HighContrastYellow ? Hex("FFE449") : Hex("F3F4DF");
        public Color Panel => Theme == ContrastTheme.DarkOnLight ? Hex("FFFCED") : Hex("09151D");
        public Color Accent => Theme == ContrastTheme.DarkOnLight ? Hex("183F54") : Hex("FFDD75");
        public static Color Hex(string value) { ColorUtility.TryParseHtmlString("#" + value.TrimStart('#'), out var color); return color; }

        public Material Make(string name, string hex, float smoothness = .15f)
        {
            var material = new Material(Shader.Find("Universal Render Pipeline/Lit")) { name = name, color = Hex(hex) };
            material.SetFloat("_Smoothness", smoothness);
            return material;
        }
        public void Track(GameObject root, SurfaceRole role)
        {
            foreach (var renderer in root.GetComponentsInChildren<Renderer>())
            {
                var originals = renderer.sharedMaterials;
                var variants = new Material[originals.Length];
                for (var i = 0; i < variants.Length; i++)
                    variants[i] = new Material(Shader.Find("Universal Render Pipeline/Simple Lit")) { name = root.name + " contrast" };
                var surface = new Surface { Renderer = renderer, Original = originals, Contrast = variants, Role = role };
                surfaces.Add(surface);
                Apply(surface);
            }
        }
        public void SetTheme(ContrastTheme theme)
        {
            Theme = theme;
            foreach (var surface in surfaces) Apply(surface);
            // The authored daylight remains consistent across interface themes.
            if (Camera.main != null) Camera.main.backgroundColor = Background;
        }
        private void Apply(Surface surface)
        {
            if (surface.Renderer == null) return;
            if (Theme != ContrastTheme.HighContrastYellow || surface.Role == SurfaceRole.Player || surface.Role == SurfaceRole.Companion)
            { surface.Renderer.sharedMaterials = surface.Original; return; }
            var quiet = surface.Role == SurfaceRole.Ground || surface.Role == SurfaceRole.Scenery;
            var color = Theme == ContrastTheme.DarkOnLight
                ? (quiet ? Hex("E6E4CE") : surface.Role == SurfaceRole.Path ? Hex("8A8162") : Hex("182C3B"))
                : (quiet ? Hex("080E12") : surface.Role == SurfaceRole.Path ? Hex("554B16") : Hex("FFE449"));
            foreach (var material in surface.Contrast) material.SetColor("_BaseColor", color);
            // Renderer includes SkinnedMeshRenderer: changing contrast never swaps geometry.
            surface.Renderer.sharedMaterials = surface.Contrast;
        }
        public void Dispose()
        {
            foreach (var surface in surfaces) foreach (var material in surface.Contrast) Object.Destroy(material);
            surfaces.Clear();
        }
    }
}
