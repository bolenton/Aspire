using System;
using Lantern.Core.Companion;
using Lantern.Core.Gameplay;
using UnityEngine;
using UnityEngine.AI;

namespace Lantern.Unity.World
{
    [RequireComponent(typeof(NavMeshAgent))]
    public sealed class PlayerMotor : MonoBehaviour
    {
        private NavMeshAgent agent;
        private Vector2 manual;
        private bool guiding;
        private float stationaryTime;
        private Vector3 lastPosition;
        private float stepRemaining, turnRemaining;
        private Vector3 worldInput;
        public float WalkSpeed { get; private set; } = 2.8f;
        public event Action Arrived;
        public event Action RouteFailed;
        public bool IsMoving => agent != null && agent.velocity.sqrMagnitude > .02f;
        public float Yaw => transform.eulerAngles.y;

        private void Awake()
        {
            agent = GetComponent<NavMeshAgent>();
            SetPace(TravelPace.Comfortable);
            agent.acceleration = 6;
            agent.angularSpeed = 150;
            agent.radius = .45f;
            agent.height = 2.1f;
            agent.stoppingDistance = 1.7f;
            agent.autoBraking = true;
        }
        public void SetPace(TravelPace pace)
        {
            WalkSpeed = TravelSettings.WalkSpeed(pace);
            if (agent != null) agent.speed = TravelSettings.GuideSpeed(pace);
        }
        public void Move(Vector2 input)
        {
            worldInput = Vector3.zero;
            manual = Vector2.ClampMagnitude(input, 1);
            if (manual.sqrMagnitude > .01f && guiding) Stop();
            manual = Vector2.ClampMagnitude(input, 1);
        }
        public void MoveWorld(Vector3 direction)
        {
            if (direction.sqrMagnitude > .001f && guiding) Stop();
            manual = Vector2.zero;
            worldInput = Vector3.ClampMagnitude(Vector3.ProjectOnPlane(direction,Vector3.up),1);
        }
        public void Step(float forward, float turn)
        {
            Stop();
            turnRemaining = Mathf.Clamp(turn,-45,45);
            stepRemaining = Mathf.Clamp(forward,-1,1);
        }
        public bool Guide(Vector3 destination)
        {
            Stop();
            var path = Route(destination);
            if (path == null) return false;
            agent.isStopped = false;
            guiding = agent.SetPath(path);
            lastPosition = transform.position;
            return guiding;
        }
        public NavMeshPath Route(Vector3 destination)
        {
            if (!agent.isOnNavMesh || !NavMesh.SamplePosition(destination, out var hit, 3, agent.areaMask)) return null;
            var path = new NavMeshPath();
            return agent.CalculatePath(hit.position, path) && path.status == NavMeshPathStatus.PathComplete ? path : null;
        }
        public ObservedEntity Observe(string id, string name, Vector3 destination)
        {
            var path = Route(destination);
            var result = new ObservedEntity { Id = id, Name = name, Position = Coordinates.Snapshot(destination), Route = path == null ? RouteStatus.Blocked : RouteStatus.Reachable };
            if (path == null) return result;
            var previous = transform.position;
            foreach (var corner in path.corners) { result.RouteDistance += Vector3.Distance(previous, corner); previous = corner; }
            var next = path.corners.Length > 1 ? path.corners[1] : destination;
            result.NextWaypoint = Coordinates.Snapshot(next);
            return result;
        }
        public void Stop()
        {
            guiding = false;
            manual = Vector2.zero;
            worldInput = Vector3.zero;
            stationaryTime = 0;
            stepRemaining = turnRemaining = 0;
            if (agent != null && agent.isOnNavMesh) { agent.ResetPath(); agent.isStopped = true; agent.velocity = Vector3.zero; }
        }
        private void Update()
        {
            if (!agent.isOnNavMesh) return;
            if (worldInput.sqrMagnitude > .001f)
            {
                transform.rotation = Quaternion.RotateTowards(transform.rotation,Quaternion.LookRotation(worldInput),180*Time.deltaTime);
                agent.Move(worldInput * (WalkSpeed*Time.deltaTime));
            }
            if (Mathf.Abs(turnRemaining) > .01f)
            {
                var delta = Mathf.MoveTowards(0,turnRemaining,65*Time.deltaTime);
                transform.Rotate(0,delta,0); turnRemaining -= delta;
            }
            else if (Mathf.Abs(stepRemaining) > .001f)
            {
                var delta = Mathf.MoveTowards(0,stepRemaining,1.4f*Time.deltaTime);
                agent.Move(transform.forward*delta); stepRemaining -= delta;
            }
            if (manual.sqrMagnitude > .01f)
            {
                transform.Rotate(0, manual.x * 65 * Time.deltaTime, 0);
                agent.Move(transform.forward * (manual.y * WalkSpeed * Time.deltaTime));
            }
            if (!guiding || agent.pathPending) return;
            if (agent.pathStatus != NavMeshPathStatus.PathComplete) { Stop(); RouteFailed?.Invoke(); return; }
            if (agent.remainingDistance <= agent.stoppingDistance + .1f) { Stop(); Arrived?.Invoke(); return; }
            stationaryTime = Vector3.Distance(lastPosition, transform.position) < .01f ? stationaryTime + Time.deltaTime : 0;
            lastPosition = transform.position;
            if (stationaryTime > 3) { Stop(); RouteFailed?.Invoke(); }
        }
        private void OnApplicationFocus(bool focus) { if (!focus) Stop(); }
        private void OnApplicationPause(bool pause) { if (pause) Stop(); }
    }
}
