using UnityEditor;
using UnityEditor.SceneManagement;

namespace Lantern.Unity.Editor
{
    public static class MeadowPreview
    {
        [MenuItem("Lantern/Play meadow preview")]
        public static void Play()
        {
            LanternProject.Prepare();
            EditorSceneManager.OpenScene("Assets/Lantern/Scenes/FoxHollow.unity");
            EditorApplication.isPlaying = true;
        }
    }
}
