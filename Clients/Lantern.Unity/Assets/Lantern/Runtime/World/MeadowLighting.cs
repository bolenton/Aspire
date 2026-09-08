using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Lantern.Unity.World
{
    public sealed class MeadowLighting : MonoBehaviour
    {
        private Material sky;
        private VolumeProfile profile;

        public void Initialize()
        {
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(.57f,.70f,.77f);
            RenderSettings.ambientEquatorColor = new Color(.43f,.51f,.40f);
            RenderSettings.ambientGroundColor = new Color(.28f,.25f,.20f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.ExponentialSquared;
            RenderSettings.fogColor = new Color(.65f,.76f,.72f);
            RenderSettings.fogDensity = .008f;
            sky = new Material(Shader.Find("Skybox/Procedural"));
            sky.SetColor("_SkyTint", new Color(.58f,.70f,.76f));
            sky.SetColor("_GroundColor", new Color(.40f,.46f,.37f));
            sky.SetFloat("_AtmosphereThickness", .75f);
            sky.SetFloat("_Exposure", 1.05f);
            sky.SetFloat("_SunSize", .018f);
            RenderSettings.skybox = sky;
            var sun = new GameObject("Late afternoon sun").AddComponent<Light>();
            sun.transform.SetParent(transform);
            sun.type = LightType.Directional;
            sun.color = new Color(1,.88f,.70f);
            sun.intensity = 1.9f;
            sun.transform.rotation = Quaternion.Euler(37,-38,0);
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = .70f;
            sun.shadowBias = .035f;
            sun.shadowNormalBias = .25f;
            RenderSettings.sun = sun;
            var fill = new GameObject("Soft sky fill").AddComponent<Light>();
            fill.transform.SetParent(transform,false);fill.type=LightType.Directional;
            fill.transform.rotation=Quaternion.Euler(42,145,0);fill.color=new Color(.68f,.81f,1);
            fill.intensity=.30f;fill.shadows=LightShadows.None;
            var volume = gameObject.AddComponent<Volume>();
            volume.isGlobal = true;
            profile = ScriptableObject.CreateInstance<VolumeProfile>();
            volume.sharedProfile = profile;
            profile.Add<Tonemapping>(true).mode.Override(TonemappingMode.ACES);
            var color = profile.Add<ColorAdjustments>(true);
            color.postExposure.Override(.3f);
            color.contrast.Override(5);
            color.saturation.Override(-3);
            var bloom=profile.Add<Bloom>(true);bloom.threshold.Override(1.3f);bloom.intensity.Override(.10f);bloom.scatter.Override(.45f);
            // No depth of field, motion blur, camera shake, or flashing effects.
        }

        private void OnDestroy() { Destroy(sky); Destroy(profile); }
    }
}
