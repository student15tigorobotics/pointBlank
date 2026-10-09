using System;
using System.Collections.Generic;

namespace PointBlank.Core
{
    /// <summary>
    /// The player's held weapons. Aim is a world ray in table-local space; the engine layer converts controller poses.
    /// Aim assist is built in: shots snap to the enemy closest to the aim axis inside the weapon's cone.
    /// </summary>
    public sealed class WeaponSystem
    {
        public float Cooldown { get; private set; }
        public float DamageMult = 1f;
        public float CooldownMult = 1f;

        readonly List<int> scratch = new List<int>(64);
        readonly HashSet<int> chainSet = new HashSet<int>();
        readonly int[] scatterSlot = new int[16];
        readonly float[] scatterCos = new float[16];

        public bool Ready => Cooldown <= 0f;

        public void Tick(float dt)
        {
            if (Cooldown > 0f) Cooldown -= dt;
        }

        /// <summary>Fires if off cooldown. Returns the number of enemies damaged.</summary>
        public int TryFire(WeaponKind kind, V3 origin, V3 dir, Swarm swarm, BattleEconomy economy, List<Shot> shots)
        {
            if (!Ready) return 0;
            var s = Balance.Weapon(kind);
            Cooldown = s.Cooldown * CooldownMult;
            float dmg = s.Damage * DamageMult;
            dir = dir.Normalized;

            switch (kind)
            {
                case WeaponKind.Blaster: return FireBlaster(origin, dir, s, dmg, swarm, economy, shots);
                case WeaponKind.Scatter: return FireScatter(origin, dir, s, dmg, swarm, economy, shots);
                case WeaponKind.Rail:    return FireRail(origin, dir, s, dmg, swarm, economy, shots);
                case WeaponKind.Arc:     return FireArc(origin, dir, s, dmg, swarm, economy, shots);
                default:                 return FireNova(origin, dir, s, dmg, swarm, economy, shots);
            }
        }

        int FireBlaster(V3 o, V3 d, WeaponStats s, float dmg, Swarm swarm, BattleEconomy eco, List<Shot> shots)
        {
            int target = BestInCone(swarm, o, d, s.Range, s.ConeDeg);
            if (target < 0) return 0;
            shots.Add(new Shot { From = o, To = Pos(swarm, target), Style = ShotStyle.Bolt });
            Combat.Hit(swarm, target, dmg, eco);
            return 1;
        }

        int FireScatter(V3 o, V3 d, WeaponStats s, float dmg, Swarm swarm, BattleEconomy eco, List<Shot> shots)
        {
            float cosCone = Cos(s.ConeDeg);
            int cap = Math.Min(s.Count, scatterSlot.Length);
            int n = 0;
            for (int i = 0; i < swarm.HighWater; i++)
            {
                if (!swarm.Alive[i]) continue;
                float c, t;
                if (!InCone(o, d, Pos(swarm, i), s.Range, cosCone, out c, out t)) continue;
                if (n < cap)
                {
                    scatterSlot[n] = i;
                    scatterCos[n] = c;
                    n++;
                    continue;
                }
                // Keep the cap enemies closest to the aim axis: replace the weakest kept candidate.
                int worst = 0;
                for (int k = 1; k < cap; k++) if (scatterCos[k] < scatterCos[worst]) worst = k;
                if (c > scatterCos[worst]) { scatterSlot[worst] = i; scatterCos[worst] = c; }
            }

            for (int k = 0; k < n; k++)
            {
                int i = scatterSlot[k];
                shots.Add(new Shot { From = o, To = Pos(swarm, i), Style = ShotStyle.Pellet });
                Combat.Hit(swarm, i, dmg, eco);
            }
            return n;
        }

        int FireRail(V3 o, V3 d, WeaponStats s, float dmg, Swarm swarm, BattleEconomy eco, List<Shot> shots)
        {
            shots.Add(new Shot { From = o, To = o + d * s.Range, Style = ShotStyle.Beam, Radius = s.Radius });
            int hits = 0;
            for (int i = 0; i < swarm.HighWater; i++)
            {
                if (!swarm.Alive[i]) continue;
                float t;
                float dist = V3.RayDistance(o, d, Pos(swarm, i), out t);
                if (t > s.Range || dist > s.Radius) continue;
                Combat.Hit(swarm, i, dmg, eco);
                hits++;
            }
            return hits;
        }

        int FireArc(V3 o, V3 d, WeaponStats s, float dmg, Swarm swarm, BattleEconomy eco, List<Shot> shots)
        {
            int current = BestInCone(swarm, o, d, s.Range, s.ConeDeg);
            if (current < 0) return 0;
            chainSet.Clear();
            V3 from = o;
            float link = dmg;
            int hits = 0;
            for (int n = 0; n < s.Count && current >= 0; n++)
            {
                V3 to = Pos(swarm, current);
                shots.Add(new Shot { From = from, To = to, Style = ShotStyle.Chain });
                chainSet.Add(current);
                Combat.Hit(swarm, current, link, eco);
                hits++;
                from = to;
                link *= 0.85f;
                current = NearestExcluding(swarm, from, s.Radius);
            }
            return hits;
        }

        int FireNova(V3 o, V3 d, WeaponStats s, float dmg, Swarm swarm, BattleEconomy eco, List<Shot> shots)
        {
            // Land on the table plane where the aim line crosses it, otherwise at max range.
            V3 impact = d.Y < -0.05f
                ? o + d * Math.Min(-o.Y / d.Y, s.Range * 1.5f)
                : o + d * s.Range;
            impact.Y = 0f;
            shots.Add(new Shot { From = o, To = impact, Radius = s.Radius, Style = ShotStyle.Burst });

            scratch.Clear();
            Combat.Collect(swarm, impact.X, impact.Z, s.Radius, scratch);
            for (int k = 0; k < scratch.Count; k++)
            {
                int i = scratch[k];
                float dx = swarm.X[i] - impact.X, dz = swarm.Z[i] - impact.Z;
                float falloff = 1f - 0.5f * (float)Math.Sqrt(dx * dx + dz * dz) / s.Radius;
                Combat.Hit(swarm, i, dmg * falloff, eco);
            }
            return scratch.Count;
        }

        int BestInCone(Swarm swarm, V3 o, V3 d, float range, float coneDeg)
        {
            float cosCone = Cos(coneDeg);
            int best = -1;
            float bestCos = cosCone;
            for (int i = 0; i < swarm.HighWater; i++)
            {
                if (!swarm.Alive[i]) continue;
                float c, t;
                if (!InCone(o, d, Pos(swarm, i), range, cosCone, out c, out t)) continue;
                if (c >= bestCos) { bestCos = c; best = i; }
            }
            return best;
        }

        int NearestExcluding(Swarm swarm, V3 from, float radius)
        {
            float best = radius * radius;
            int found = -1;
            for (int i = 0; i < swarm.HighWater; i++)
            {
                if (!swarm.Alive[i] || chainSet.Contains(i)) continue;
                float dx = swarm.X[i] - from.X, dz = swarm.Z[i] - from.Z;
                float d2 = dx * dx + dz * dz;
                if (d2 <= best) { best = d2; found = i; }
            }
            return found;
        }

        static float Cos(float deg) => (float)Math.Cos(deg * Math.PI / 180.0);

        static bool InCone(V3 o, V3 d, V3 p, float range, float cosCone, out float cos, out float t)
        {
            V3 v = p - o;
            float len = v.Length;
            t = v.Dot(d);
            cos = len > 1e-6f ? t / len : 1f;
            return t > 0f && t <= range && cos >= cosCone;
        }

        static V3 Pos(Swarm s, int i) => new V3(s.X[i], s.Y[i], s.Z[i]);
    }
}
