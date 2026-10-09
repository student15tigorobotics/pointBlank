using System;

namespace PointBlank.Core
{
    /// <summary>Minimal float vector so the simulation has no engine dependency.</summary>
    public struct V3
    {
        public float X, Y, Z;

        public V3(float x, float y, float z) { X = x; Y = y; Z = z; }

        public static V3 operator +(V3 a, V3 b) => new V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
        public static V3 operator -(V3 a, V3 b) => new V3(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
        public static V3 operator *(V3 a, float s) => new V3(a.X * s, a.Y * s, a.Z * s);

        public float Dot(V3 b) => X * b.X + Y * b.Y + Z * b.Z;
        public float LengthSq => X * X + Y * Y + Z * Z;
        public float Length => (float)Math.Sqrt(LengthSq);

        public V3 Normalized
        {
            get
            {
                float l = Length;
                return l > 1e-6f ? this * (1f / l) : new V3(0f, 0f, 1f);
            }
        }

        /// <summary>Distance from point p to the ray (origin o, unit direction d), clamped to t >= 0.</summary>
        public static float RayDistance(V3 o, V3 d, V3 p, out float t)
        {
            V3 op = p - o;
            t = Math.Max(0f, op.Dot(d));
            V3 closest = o + d * t;
            return (p - closest).Length;
        }
    }
}
