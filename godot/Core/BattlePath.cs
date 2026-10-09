using System;

namespace PointBlank.Core
{
    /// <summary>Polyline the swarm walks along, in table-local XZ meters.</summary>
    public sealed class BattlePath
    {
        readonly float[] px;
        readonly float[] pz;
        readonly float[] cum; // cumulative distance at each vertex
        public float Length { get; }
        public int Count => px.Length;

        public BattlePath(float[] xzPairs)
        {
            int n = xzPairs.Length / 2;
            if (n < 2) throw new ArgumentException("A path needs at least two points.");
            px = new float[n];
            pz = new float[n];
            cum = new float[n];
            for (int i = 0; i < n; i++)
            {
                px[i] = xzPairs[i * 2];
                pz[i] = xzPairs[i * 2 + 1];
            }
            for (int i = 1; i < n; i++)
            {
                float dx = px[i] - px[i - 1], dz = pz[i] - pz[i - 1];
                cum[i] = cum[i - 1] + (float)Math.Sqrt(dx * dx + dz * dz);
            }
            Length = cum[n - 1];
        }

        public V3 Start => new V3(px[0], 0f, pz[0]);
        public V3 End => new V3(px[px.Length - 1], 0f, pz[pz.Length - 1]);

        /// <summary>Position and unit heading at arc-length distance d. d below 0 extrapolates backwards.</summary>
        public V3 Sample(float d, out V3 dir)
        {
            int n = px.Length;
            if (d <= 0f)
            {
                dir = Heading(0);
                return new V3(px[0] + dir.X * d, 0f, pz[0] + dir.Z * d);
            }
            if (d >= Length)
            {
                dir = Heading(n - 2);
                return new V3(px[n - 1], 0f, pz[n - 1]);
            }
            int i = 0;
            while (i < n - 2 && cum[i + 1] < d) i++;
            float segLen = cum[i + 1] - cum[i];
            float t = segLen > 1e-6f ? (d - cum[i]) / segLen : 0f;
            dir = Heading(i);
            return new V3(px[i] + (px[i + 1] - px[i]) * t, 0f, pz[i] + (pz[i + 1] - pz[i]) * t);
        }

        V3 Heading(int seg)
        {
            float dx = px[seg + 1] - px[seg], dz = pz[seg + 1] - pz[seg];
            float l = (float)Math.Sqrt(dx * dx + dz * dz);
            return l > 1e-6f ? new V3(dx / l, 0f, dz / l) : new V3(0f, 0f, 1f);
        }

        /// <summary>Shortest XZ distance from a point to any segment of the path.</summary>
        public float DistanceTo(float x, float z)
        {
            float best = float.MaxValue;
            for (int i = 0; i < px.Length - 1; i++)
            {
                float ax = px[i], az = pz[i], bx = px[i + 1], bz = pz[i + 1];
                float vx = bx - ax, vz = bz - az;
                float len2 = vx * vx + vz * vz;
                float t = len2 > 1e-9f ? Math.Max(0f, Math.Min(1f, ((x - ax) * vx + (z - az) * vz) / len2)) : 0f;
                float cx = ax + vx * t - x, cz = az + vz * t - z;
                float d = (float)Math.Sqrt(cx * cx + cz * cz);
                if (d < best) best = d;
            }
            return best;
        }
    }
}
