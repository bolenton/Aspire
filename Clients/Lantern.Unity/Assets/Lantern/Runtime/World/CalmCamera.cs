using UnityEngine;

namespace Lantern.Unity.World
{
    public sealed class CalmCamera : MonoBehaviour
    {
        public Transform Target { get; set; }
        public Bounds[] Obstacles { get; set; } = System.Array.Empty<Bounds>();
        private Vector3 velocity;
        private float yaw;
        private float yawVelocity;
        public void Snap()
        {
            yaw = Target.eulerAngles.y;
            velocity = Vector3.zero;
            yawVelocity = 0;
            transform.position = DesiredPosition();
            transform.LookAt(Target.position + Vector3.up * 1.55f);
        }
        private Vector3 DesiredPosition()
        {
            var focus=Target.position+Vector3.up*1.55f;
            var desired=Target.position+Quaternion.Euler(0,yaw,0)*new Vector3(.45f,3.6f,-6.7f);
            var offset=desired-focus;var distance=offset.magnitude;var ray=new Ray(focus,offset.normalized);
            foreach(var bounds in Obstacles)
                if(!bounds.Contains(focus) && bounds.IntersectRay(ray,out var hit)) distance=Mathf.Min(distance,Mathf.Max(2.8f,hit-.35f));
            var position=focus+offset.normalized*distance;
            position.y=Mathf.Max(position.y,Target.position.y+3.6f);
            return position;
        }
        private void LateUpdate()
        {
            if (Target == null) return;
            yaw = Mathf.SmoothDampAngle(yaw, Target.eulerAngles.y, ref yawVelocity, .65f, 95);
            transform.position = Vector3.SmoothDamp(transform.position, DesiredPosition(), ref velocity, .28f);
            transform.LookAt(Target.position + Vector3.up * 1.55f);
        }
    }
}
