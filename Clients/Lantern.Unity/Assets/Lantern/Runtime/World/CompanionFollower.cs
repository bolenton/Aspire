using UnityEngine;
using UnityEngine.AI;

namespace Lantern.Unity.World
{
    /// <summary>Ember walks beside the explorer after their introduction, using the same safe paths.</summary>
    public sealed class CompanionFollower : MonoBehaviour
    {
        private NavMeshAgent agent;
        private Transform player;
        private float nextRoute;
        private PlayerMotor motor;
        private float side=1;
        private Transform interest;
        public bool Following { get; set; }

        public void Initialize(Transform explorer)
        {
            player = explorer;
            motor = explorer.GetComponent<PlayerMotor>();
            agent = gameObject.AddComponent<NavMeshAgent>();
            agent.speed = 3.6f;
            agent.acceleration = 6;
            agent.angularSpeed = 170;
            agent.radius = .35f;
            agent.height = 1.8f;
            agent.stoppingDistance = .6f;
            if (NavMesh.SamplePosition(transform.position, out var spawn,2,NavMesh.AllAreas)) agent.Warp(spawn.position);
        }

        public void SetInterest(Transform target)
        {
            if(target==interest)return;
            interest=target;
            side=target!=null && Vector3.Dot(target.position-player.position,player.right)>=0 ? -1 : 1;
            nextRoute=0;
        }
        private void Update()
        {
            if (!Following || player == null || !agent.isOnNavMesh) return;
            agent.speed = motor.WalkSpeed * 1.3f;
            if (Time.time < nextRoute) return;
            nextRoute = Time.time + .35f;
            // On the bridge Ember follows single-file, keeping the narrow crossing clear.
            var onBridge = player.position.x > 8 && player.position.x < 16.5f;
            var desired = onBridge ? player.position-player.forward*1.6f : player.position+player.right*(1.9f*side)-player.forward*.1f;
            if (Vector3.Distance(transform.position,desired) < 1)
            {
                agent.ResetPath();
                return;
            }
            if (NavMesh.SamplePosition(desired,out var target,2,NavMesh.AllAreas)) agent.SetDestination(target.position);
        }

        private void OnApplicationPause(bool paused)
        {
            if (paused && agent != null && agent.isOnNavMesh) agent.ResetPath();
        }
    }
}
