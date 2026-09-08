using System.Runtime.InteropServices;
using UnityEngine;

namespace Lantern.Unity.Platform
{
    internal static class SpatialAudioBridge
    {
#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")] private static extern int LanternSpatialStart();
        [DllImport("__Internal")] private static extern int LanternSpatialAdd(string id, string path, float x, float y, float z, float volume, float far, int loops);
        [DllImport("__Internal")] private static extern void LanternSpatialPose(float x, float y, float z, float yaw);
        [DllImport("__Internal")] private static extern void LanternSpatialDuck(float multiplier);
        [DllImport("__Internal")] private static extern void LanternSpatialRemove(string id);
        [DllImport("__Internal")] private static extern void LanternSpatialPause(int paused);
        [DllImport("__Internal")] private static extern void LanternSpatialRecenter();
        [DllImport("__Internal")] private static extern void LanternSpatialStop();
        public static bool Start() => LanternSpatialStart() == 1;
        public static bool Add(string id, string path, Vector3 position, float volume, float far, bool loops) => LanternSpatialAdd(id, path, position.x, position.y, position.z, volume, far, loops ? 1 : 0) == 1;
        public static void Pose(Vector3 position, float yaw) => LanternSpatialPose(position.x, position.y, position.z, yaw);
        public static void Duck(float multiplier) => LanternSpatialDuck(multiplier);
        public static void Remove(string id) => LanternSpatialRemove(id);
        public static void Pause(bool paused) => LanternSpatialPause(paused ? 1 : 0);
        public static void Recenter() => LanternSpatialRecenter();
        public static void Stop() => LanternSpatialStop();
#else
        public static bool Start() => false;
        public static bool Add(string id, string path, Vector3 position, float volume, float far, bool loops) => false;
        public static void Pose(Vector3 position, float yaw) { }
        public static void Duck(float multiplier) { }
        public static void Remove(string id) { }
        public static void Pause(bool paused) { }
        public static void Recenter() { }
        public static void Stop() { }
#endif
    }
}
