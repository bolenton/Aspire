#if UNITY_EDITOR || DEVELOPMENT_BUILD
using System.Collections;
using System.IO;
using UnityEngine;
using UnityEngine.EventSystems;
using Lantern.Unity.Presentation;

namespace Lantern.Unity.World
{
    /// <summary>Opt-in captures of the running game, including its real interface.</summary>
    public sealed class DevelopmentCapture : MonoBehaviour
    {
        private IEnumerator Start()
        {
            if (System.Environment.GetEnvironmentVariable("LANTERN_CAPTURE") != "1") yield break;
            yield return new WaitForSeconds(6);
            if (System.Environment.GetEnvironmentVariable("LANTERN_VERIFY_INPUT") == "1")
                yield return VerifyMovement();
            yield return new WaitForEndOfFrame();
            var path = Path.Combine(Application.persistentDataPath, "lantern-gameplay.png");
            Capture("lantern-gameplay.png");
            yield return new WaitForSeconds(1);
            if (File.Exists(path)) Debug.Log("Lantern gameplay capture saved: " + path);
            else Debug.LogError("The gameplay screenshot was not saved: " + path);
        }
        private static void Capture(string file)
        {
            // Unity prefixes persistentDataPath itself on mobile platforms.
            ScreenCapture.CaptureScreenshot(Application.isMobilePlatform ? file : Path.Combine(Application.persistentDataPath,file));
        }
        private IEnumerator VerifyMovement()
        {
            var control = FindFirstObjectByType<TouchMovement>();
            var player = FindFirstObjectByType<PlayerMotor>();
            if (control == null || player == null) { Debug.LogError("Touch verification could not find the adventure controls."); yield break; }
            var start = player.transform.position;
            var rotation = player.transform.rotation;
            var touch = new PointerEventData(EventSystem.current) { pointerId = 17, position = new Vector2(Screen.width*.3f,Screen.height*.4f) };
            control.OnPointerDown(touch);
            touch.position += new Vector2(0,-Screen.height*.11f);
            control.OnDrag(touch);
            yield return new WaitForSeconds(.30f);
            yield return new WaitForEndOfFrame();
            Capture("lantern-touch.png");
            yield return new WaitForSeconds(.35f);
            var moved = Vector3.Distance(start,player.transform.position);
            var other = new PointerEventData(EventSystem.current) { pointerId = 18, position = touch.position };
            control.OnPointerUp(other); // A second finger must not release the movement finger.
            var beforeOtherRelease = player.transform.position;
            yield return new WaitForSeconds(.2f);
            var stillMoving = Vector3.Distance(beforeOtherRelease,player.transform.position) > .05f;
            control.OnPointerUp(touch);
            var stopped = player.transform.position;
            yield return new WaitForSeconds(.3f);
            var drift = Vector3.Distance(stopped,player.transform.position);
            var passed = moved > .2f && stillMoving && drift < .015f;
            Debug.Log($"Lantern touch verification: {(passed ? "PASS" : "FAIL")}; moved={moved:F3}m; other finger ignored={stillMoving}; release drift={drift:F4}m.");
            if (!passed) Debug.LogError("The touch movement acceptance check failed.");
            player.GetComponent<UnityEngine.AI.NavMeshAgent>().Warp(start);
            player.transform.rotation = rotation;
            Camera.main.GetComponent<CalmCamera>().Snap();
            yield return new WaitForSeconds(1);
        }
    }
}
#endif
