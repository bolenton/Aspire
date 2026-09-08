using System.Collections.Generic;
using UnityEngine;

namespace Lantern.Unity.World
{
    /// <summary>Gentle pose animation on the authored limb pivots. No motion affects navigation.</summary>
    public sealed class CharacterMotion : MonoBehaviour
    {
        private readonly Dictionary<string, Transform> joints = new Dictionary<string, Transform>();
        private readonly Dictionary<string, Quaternion> rest = new Dictionary<string, Quaternion>();
        private readonly Dictionary<string, Vector3> restScale = new Dictionary<string, Vector3>();
        private static readonly string[] Eyes = { "Eye.L", "Eye.R" };
        private Transform motionRoot;
        private Vector3 previous, artworkRest;
        private float pace, phase, blinkAt;
        private bool quadruped, listening, thinking, speaking;
        private float speech, attention;
        public void SetExpression(bool listen,bool think,float level,bool talking)
        {listening=listen;thinking=think;speech=level;speaking=talking;}

        public void Initialize(Transform locomotion)
        {
            motionRoot = locomotion;
            previous = locomotion.position;
            artworkRest = transform.localPosition;
            foreach (var joint in GetComponentsInChildren<Transform>())
            {
                if (joints.ContainsKey(joint.name)) continue;
                joints.Add(joint.name, joint);
                rest.Add(joint.name, joint.localRotation);
                restScale.Add(joint.name, joint.localScale);
            }
            quadruped=joints.ContainsKey("Leg.Front.L");
            blinkAt = Time.time + 3.5f;
        }

        private void LateUpdate()
        {
            if (motionRoot == null) return;
            var speed = Vector3.Distance(motionRoot.position, previous) / Mathf.Max(Time.deltaTime, .001f);
            previous = motionRoot.position;
            pace = Mathf.MoveTowards(pace, Mathf.Clamp01(speed / .7f), Time.deltaTime * 5);
            phase += Mathf.Min(speed,4.5f) * Time.deltaTime * (quadruped ? 5.2f : 3.5f);
            transform.localPosition = artworkRest + Vector3.up * (Mathf.Abs(Mathf.Sin(phase))*.032f*pace);
            var stride = Mathf.Sin(phase) * pace;
            attention=Mathf.MoveTowards(attention,listening ? 1:0,Time.deltaTime*3);
            Pose("Arm.L", Vector3.right, stride * 20);
            Pose("Arm.R", Vector3.right, -stride * 20);
            Pose("Leg.L", Vector3.right, -stride * 30);
            Pose("Leg.R", Vector3.right, stride * 30);
            Pose("Leg.Front.L", Vector3.right, stride * 30);
            Pose("Leg.Front.R", Vector3.right, -stride * 30);
            Pose("Leg.Back.L", Vector3.right, -stride * 30);
            Pose("Leg.Back.R", Vector3.right, stride * 30);
            Pose("Head", Vector3.forward, (Mathf.Sin(Time.time * .7f) * 2 + attention*8 + (thinking ? 5:0)) * (1-pace));
            Pose("Jaw",Vector3.right,-Mathf.Clamp(speech*18+(speaking ? 2:0),0,20));
            Pose("Ear.L",Vector3.forward,-attention*9);
            Pose("Ear.R",Vector3.forward,attention*9);
            Pose("Tail", Vector3.up, Mathf.Sin(Time.time * (speaking ? 2.8f:1.7f)) * (speaking ? 16:9));
            Pose("Torso", Vector3.right, Mathf.Sin(Time.time * 1.2f) * .65f);
            var blink = Time.time >= blinkAt ? Mathf.Abs((Time.time-blinkAt) / .09f - 1) : 1;
            if (Time.time > blinkAt + .18f) { blinkAt = Time.time + 3.7f; blink = 1; }
            foreach (var name in Eyes)
                if (joints.TryGetValue(name, out var eye)) eye.localScale = Vector3.Scale(restScale[name],new Vector3(1, Mathf.Clamp(blink, .08f, 1), 1));
        }

        private void Pose(string name, Vector3 axis, float angle)
        {
            if (joints.TryGetValue(name, out var joint))
                joint.localRotation = rest[name] * Quaternion.AngleAxis(angle, axis);
        }
    }
}
