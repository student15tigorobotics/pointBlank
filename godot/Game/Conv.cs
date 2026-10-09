using Godot;
using PointBlank.Core;

namespace PointBlank
{
    /// <summary>Bridges the engine-free Core vector type and Godot's Vector3.</summary>
    public static class Conv
    {
        public static V3 ToCore(this Vector3 v) => new V3(v.X, v.Y, v.Z);
        public static Vector3 ToGodot(this V3 v) => new Vector3(v.X, v.Y, v.Z);
    }
}
