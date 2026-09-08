using System.Runtime.InteropServices;
using UnityEngine;

namespace Lantern.Unity.Companion
{
    internal static class CompanionCredentials
    {
        public static string Load(string server)
        {
#if UNITY_IOS && !UNITY_EDITOR
            var pointer=LanternCredentialLoad(server);
            if(pointer==System.IntPtr.Zero)return "";
            var token=Marshal.PtrToStringUTF8(pointer);LanternCredentialFree(pointer);return token;
#else
            return PlayerPrefs.GetString("LanternServer:"+server,"");
#endif
        }
        public static void Save(string server,string token)
        {
#if UNITY_IOS && !UNITY_EDITOR
            LanternCredentialSave(server,token);
#else
            PlayerPrefs.SetString("LanternServer:"+server,token);PlayerPrefs.Save();
#endif
        }
#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")]private static extern System.IntPtr LanternCredentialLoad(string server);
        [DllImport("__Internal")]private static extern void LanternCredentialFree(System.IntPtr value);
        [DllImport("__Internal")]private static extern void LanternCredentialSave(string server,string token);
#endif
    }
}
