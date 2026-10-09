using System;
using System.Collections.Generic;

namespace PointBlank.Core
{
    public enum ShotStyle : byte { Bolt, Chain, Pulse, Shell, Lance, Beam, Pellet, Burst }

    /// <summary>Visual-only record of an attack, consumed by the engine layer for tracers and bursts.</summary>
    public struct Shot
    {
        public V3 From, To;
        public float Radius;
        public ShotStyle Style;
    }

    public static class Combat
    {
        /// <summary>Applies damage and returns the overkill (damage beyond remaining HP), or 0 if still alive.</summary>
        public static float ApplyToHp(ref float hp, float damage, out bool killed)
        {
            hp -= damage;
            killed = hp <= 0f;
            if (!killed) return 0f;
            float overkill = -hp;
            hp = 0f;
            return overkill;
        }

        /// <summary>Damages one enemy and books kills/overkill in the economy. Returns true if it died.</summary>
        public static bool Hit(Swarm swarm, int i, float damage, BattleEconomy economy)
        {
            if (!swarm.Alive[i] || damage <= 0f) return false;
            bool killed;
            float overkill = ApplyToHp(ref swarm.Hp[i], damage, out killed);
            if (killed)
            {
                economy.OnKill(swarm.Kind[i], overkill);
                swarm.Kill(i);
            }
            return killed;
        }

        /// <summary>Nearest alive enemy to (x,z) within range, using XZ distance. Returns -1 if none.</summary>
        public static int NearestInRange(Swarm swarm, float x, float z, float range, Func<int, bool> filter = null)
        {
            float best = range * range;
            int found = -1;
            for (int i = 0; i < swarm.HighWater; i++)
            {
                if (!swarm.Alive[i]) continue;
                float dx = swarm.X[i] - x, dz = swarm.Z[i] - z;
                float d2 = dx * dx + dz * dz;
                if (d2 > best) continue;
                if (filter != null && !filter(i)) continue;
                best = d2;
                found = i;
            }
            return found;
        }

        public static void Collect(Swarm swarm, float x, float z, float radius, List<int> into)
        {
            float r2 = radius * radius;
            for (int i = 0; i < swarm.HighWater; i++)
            {
                if (!swarm.Alive[i]) continue;
                float dx = swarm.X[i] - x, dz = swarm.Z[i] - z;
                if (dx * dx + dz * dz <= r2) into.Add(i);
            }
        }
    }
}
