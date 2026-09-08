using Lantern.Core.Content;
using UnityEngine;

namespace Lantern.Unity.World
{
    public static class Coordinates
    {
        public static Vector3 Authored(WorldPoint point) => new Vector3((float)point.X, (float)point.Y, -(float)point.Z);
        public static Vector3 Runtime(WorldPoint point) => new Vector3((float)point.X, (float)point.Y, (float)point.Z);
        public static WorldPoint Snapshot(Vector3 position) => new WorldPoint(position.x, position.y, position.z);
    }
}
