#if UNITY_IOS
using System.IO;
using UnityEditor;
using UnityEditor.Callbacks;
using UnityEditor.iOS.Xcode;

namespace Lantern.Unity.Editor
{
    internal static class AppleBuildSettings
    {
        [PostProcessBuild(100)]
        private static void Configure(BuildTarget target, string output)
        {
            if (target != BuildTarget.iOS) return;
            var path = PBXProject.GetPBXProjectPath(output);
            var project = new PBXProject(); project.ReadFromFile(path);
            var framework = project.GetUnityFrameworkTargetGuid();
            foreach (var name in new[] { "AVFoundation.framework", "Speech.framework", "PHASE.framework", "CoreMotion.framework", "Security.framework" }) project.AddFrameworkToProject(framework, name, false);
            project.AddFrameworkToProject(framework, "FoundationModels.framework", true);
            project.SetBuildProperty(framework, "SWIFT_VERSION", "5.0");
            project.SetBuildProperty(framework, "CLANG_ENABLE_MODULES", "YES");
            project.SetBuildProperty(project.GetUnityMainTargetGuid(), "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES", "YES");
            project.WriteToFile(path);
            var plistPath = Path.Combine(output, "Info.plist");
            var plist = new PlistDocument(); plist.ReadFromFile(plistPath);
            plist.root.SetString("NSMicrophoneUsageDescription", "Talk to Ember. With family server voice enabled, microphone audio is sent to your family server for speech recognition.");
            plist.root.SetString("NSSpeechRecognitionUsageDescription", "Lantern understands your spoken questions using speech recognition on this device.");
            plist.root.SetString("NSMotionUsageDescription", "Headphone motion keeps game sounds in the right place as you turn your head.");
            plist.WriteToFile(plistPath);
        }
    }
}
#endif
