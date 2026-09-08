using System;
using System.IO;
using Lantern.Unity.Composition;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Lantern.Unity.Editor
{
    public static class LanternProject
    {
        private const string ScenePath = "Assets/Lantern/Scenes/FoxHollow.unity";
        [InitializeOnLoadMethod]
        private static void OnLoad() { if (!File.Exists(ScenePath)) EditorApplication.delayCall += Prepare; }

        [MenuItem("Lantern/Prepare Fox Hollow")]
        public static void Prepare()
        {
            CopyContent();
            Directory.CreateDirectory("Assets/Lantern/Settings");
            Directory.CreateDirectory("Assets/Lantern/Scenes");
            AssetDatabase.Refresh();
            var pipeline = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>("Assets/Lantern/Settings/LanternURP.asset");
            if (pipeline == null)
            {
                var renderer = ScriptableObject.CreateInstance<UniversalRendererData>();
                AssetDatabase.CreateAsset(renderer, "Assets/Lantern/Settings/LanternRenderer.asset");
                pipeline = UniversalRenderPipelineAsset.Create(renderer);
                pipeline.msaaSampleCount = 4;
                pipeline.renderScale = 1;
                pipeline.supportsHDR = false;
                pipeline.shadowDistance = 32;
                AssetDatabase.CreateAsset(pipeline, "Assets/Lantern/Settings/LanternURP.asset");
            }
            pipeline.supportsHDR = true;
            pipeline.shadowDistance = 55;
            pipeline.shadowCascadeCount = 2;
            EditorUtility.SetDirty(pipeline);
            GraphicsSettings.defaultRenderPipeline = pipeline;
            QualitySettings.renderPipeline = pipeline;
            IncludeRuntimeShaders();
            PlayerSettings.companyName = "Lantern";
            PlayerSettings.productName = "Lantern Unity";
            PlayerSettings.bundleVersion = "0.1.0";
            PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.iOS, "com.bolenton.Lantern.UnitySlice");
            PlayerSettings.SetScriptingBackend(NamedBuildTarget.iOS, ScriptingImplementation.IL2CPP);
            PlayerSettings.iOS.targetOSVersionString = "18.0";
            PlayerSettings.iOS.buildNumber = "12";
            PlayerSettings.iOS.targetDevice = iOSTargetDevice.iPhoneAndiPad;
            PlayerSettings.iOS.appleEnableAutomaticSigning = true;
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.colorSpace = ColorSpace.Linear;
            PlayerSettings.runInBackground = false;
            // No account, cloud analytics, ads or network service is required by the slice.
            if (!File.Exists(ScenePath))
            {
                var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                new GameObject("Lantern").AddComponent<LanternBootstrap>();
                EditorSceneManager.SaveScene(scene, ScenePath);
            }
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
            AssetDatabase.SaveAssets();
            Debug.Log("Lantern Fox Hollow is ready. Open its scene and press Play.");
        }
        public static void CopyContent()
        {
            var repository = Path.GetFullPath(Path.Combine(Application.dataPath, "../../.."));
            CopyDirectory(Path.Combine(repository, "StoryPacks"), Path.Combine(Application.streamingAssetsPath, "StoryPacks"));
            CopyDirectory(Path.Combine(Application.dataPath, "../Content"), Path.Combine(Application.streamingAssetsPath, "StoryPacks"));
            // The meadow owns its new sound set. Legacy Swift audio is never staged here.
        }
        private static void IncludeRuntimeShaders()
        {
            var settings = new SerializedObject(AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/GraphicsSettings.asset")[0]);
            var included = settings.FindProperty("m_AlwaysIncludedShaders");
            var shaders = new[]
            {
                Shader.Find("Skybox/Procedural"),
                Shader.Find("Lantern/Meadow Surface"),
                Shader.Find("Universal Render Pipeline/Unlit"),
                Shader.Find("Universal Render Pipeline/Lit"),
                Shader.Find("Universal Render Pipeline/Simple Lit"),
                AssetDatabase.LoadAssetAtPath<Shader>("Packages/com.unity.cloud.gltfast/Runtime/Shader/glTF-pbrMetallicRoughness.shadergraph")
            };
            foreach (var shader in shaders)
            {
                if (shader == null) throw new BuildFailedException("A required Lantern runtime shader was not imported.");
                var found = false;
                for (var i = 0; i < included.arraySize; i++)
                    if (included.GetArrayElementAtIndex(i).objectReferenceValue == shader) found = true;
                if (found) continue;
                included.InsertArrayElementAtIndex(included.arraySize);
                included.GetArrayElementAtIndex(included.arraySize - 1).objectReferenceValue = shader;
            }
            settings.ApplyModifiedPropertiesWithoutUndo();
        }
        private static void CopyDirectory(string source, string destination)
        {
            if (!Directory.Exists(source)) throw new DirectoryNotFoundException(source);
            Directory.CreateDirectory(destination);
            foreach (var file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
            {
                if (file.EndsWith(".meta", StringComparison.Ordinal) || Path.GetFileName(file).StartsWith(".")) continue;
                var target = Path.Combine(destination, Path.GetRelativePath(source, file));
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                File.Copy(file, target, true);
            }
        }
        [MenuItem("Lantern/Build iOS Xcode project")]
        public static void BuildIOS()
        {
            Prepare();
            var path = Environment.GetEnvironmentVariable("LANTERN_BUILD_PATH") ?? "Builds/iOS";
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            { scenes = new[] { ScenePath }, locationPathName = path, target = BuildTarget.iOS, options = BuildOptions.Development });
            if (report.summary.result != BuildResult.Succeeded) throw new BuildFailedException("Lantern iOS export failed. See the editor log.");
        }
    }
}
