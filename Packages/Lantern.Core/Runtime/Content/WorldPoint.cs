#nullable enable
using System;

namespace Lantern.Core.Content
{
    public readonly struct WorldPoint
    {
        public double X { get; }
        public double Y { get; }
        public double Z { get; }
        [Newtonsoft.Json.JsonConstructor]
        public WorldPoint(double x, double y, double z) { X = x; Y = y; Z = z; }
        public double DistanceTo(WorldPoint other) => Math.Sqrt(Math.Pow(X - other.X, 2) + Math.Pow(Y - other.Y, 2) + Math.Pow(Z - other.Z, 2));
        public WorldPoint FromLegacyCoordinates() => new WorldPoint(X, Y, -Z);
    }
}
