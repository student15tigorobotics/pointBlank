using System;
using System.Collections.Generic;

namespace PointBlank.Core
{
    public sealed class TowerInstance
    {
        public int Id;
        public TowerKind Kind;
        public int Level = 1;
        public float X, Z;
        public float Cooldown;
        public int Spent;   // total credits invested, used for sell value
    }

    /// <summary>Placed towers and their auto-targeting. Economy decisions are made by the caller through Place/Sell/Upgrade.</summary>
    public sealed class TowerField
    {
        public readonly List<TowerInstance> Towers = new List<TowerInstance>();
        public float DamageMult = 1f;
        readonly List<int> scratch = new List<int>(64);
        int nextId = 1;

        public int UpgradeCost(TowerInstance t)
        {
            var s = Balance.Tower(t.Kind);
            return (int)Math.Round(s.Cost * Balance.TowerUpgradeCostFactor * t.Level);
        }

        public int SellValue(TowerInstance t) => t.Spent * Balance.TowerSellPercent / 100;

        public bool CanPlaceAt(float x, float z, BattlePath path, HashSet<long> occupied)
        {
            if (Towers.Count >= Balance.MaxTowers) return false;
            if (Math.Abs(x) > Balance.FieldHalf || Math.Abs(z) > Balance.FieldHalf) return false;
            if (path.DistanceTo(x, z) < Balance.PadClearance) return false;
            return !occupied.Contains(PadKey(x, z));
        }

        public static long PadKey(float x, float z)
        {
            long ix = (long)Math.Round(x / Balance.PadSpacing);
            long iz = (long)Math.Round(z / Balance.PadSpacing);
            return ix * 100000L + iz;
        }

        public TowerInstance Place(TowerKind kind, float x, float z, int cost, BattleEconomy economy)
        {
            if (!economy.TrySpend(cost)) return null;
            var t = new TowerInstance { Id = nextId++, Kind = kind, X = x, Z = z, Spent = cost };
            Towers.Add(t);
            return t;
        }

        public int Sell(TowerInstance t, BattleEconomy economy)
        {
            if (!Towers.Remove(t)) return 0;
            int refund = SellValue(t);
            economy.Refund(refund);
            return refund;
        }

        public bool Upgrade(TowerInstance t, BattleEconomy economy)
        {
            if (t.Level >= Balance.MaxTowerLevel) return false;
            int cost = UpgradeCost(t);
            if (!economy.TrySpend(cost)) return false;
            t.Spent += cost;
            t.Level++;
            return true;
        }

        public TowerInstance Pick(float x, float z, float radius)
        {
            TowerInstance best = null;
            float bestD = radius * radius;
            foreach (var t in Towers)
            {
                float dx = t.X - x, dz = t.Z - z;
                float d2 = dx * dx + dz * dz;
                if (d2 <= bestD) { bestD = d2; best = t; }
            }
            return best;
        }

        public void Tick(float dt, Swarm swarm, BattleEconomy economy, List<Shot> shots)
        {
            foreach (var t in Towers)
            {
                t.Cooldown -= dt;
                if (t.Cooldown > 0f) continue;

                var s = Balance.Tower(t.Kind);
                float levelBoost = (float)Math.Pow(Balance.TowerUpgradeDamage, t.Level - 1);
                float dmg = s.Damage * DamageMult * levelBoost;
                t.Cooldown = s.Cooldown * (float)Math.Pow(Balance.TowerUpgradeCooldown, t.Level - 1);

                switch (t.Kind)
                {
                    case TowerKind.Turret:
                        FireSingle(t, s, dmg, swarm, economy, shots, ShotStyle.Bolt);
                        break;
                    case TowerKind.Sniper:
                        FireStrongest(t, s, dmg, swarm, economy, shots);
                        break;
                    case TowerKind.Mortar:
                        FireShell(t, s, dmg, swarm, economy, shots);
                        break;
                    case TowerKind.Tesla:
                        FireChain(t, s, dmg, swarm, economy, shots);
                        break;
                    case TowerKind.Frost:
                        FirePulse(t, s, dmg, swarm, economy, shots);
                        break;
                }
            }
        }

        void FireSingle(TowerInstance t, TowerStats s, float dmg, Swarm swarm, BattleEconomy eco, List<Shot> shots, ShotStyle style)
        {
            int target = Combat.NearestInRange(swarm, t.X, t.Z, s.Range);
            if (target < 0) { t.Cooldown = 0f; return; }
            shots.Add(new Shot { From = Top(t), To = new V3(swarm.X[target], swarm.Y[target], swarm.Z[target]), Style = style });
            Combat.Hit(swarm, target, dmg, eco);
        }

        void FireStrongest(TowerInstance t, TowerStats s, float dmg, Swarm swarm, BattleEconomy eco, List<Shot> shots)
        {
            float r2 = s.Range * s.Range;
            int best = -1;
            float bestHp = -1f;
            for (int i = 0; i < swarm.HighWater; i++)
            {
                if (!swarm.Alive[i]) continue;
                float dx = swarm.X[i] - t.X, dz = swarm.Z[i] - t.Z;
                if (dx * dx + dz * dz > r2) continue;
                if (swarm.Hp[i] > bestHp) { bestHp = swarm.Hp[i]; best = i; }
            }
            if (best < 0) { t.Cooldown = 0f; return; }
            shots.Add(new Shot { From = Top(t), To = new V3(swarm.X[best], swarm.Y[best], swarm.Z[best]), Style = ShotStyle.Lance });
            Combat.Hit(swarm, best, dmg, eco);
        }

        void FireShell(TowerInstance t, TowerStats s, float dmg, Swarm swarm, BattleEconomy eco, List<Shot> shots)
        {
            int target = Combat.NearestInRange(swarm, t.X, t.Z, s.Range);
            if (target < 0) { t.Cooldown = 0f; return; }
            float tx = swarm.X[target], tz = swarm.Z[target];
            var impact = new V3(tx, 0f, tz);
            shots.Add(new Shot { From = Top(t), To = impact, Radius = s.Splash, Style = ShotStyle.Shell });
            scratch.Clear();
            Combat.Collect(swarm, tx, tz, s.Splash, scratch);
            for (int k = 0; k < scratch.Count; k++)
            {
                int i = scratch[k];
                float falloff = 1f - 0.5f * (float)Math.Sqrt(Dist2(swarm, i, tx, tz)) / s.Splash;
                Combat.Hit(swarm, i, dmg * falloff, eco);
            }
        }

        void FireChain(TowerInstance t, TowerStats s, float dmg, Swarm swarm, BattleEconomy eco, List<Shot> shots)
        {
            int first = Combat.NearestInRange(swarm, t.X, t.Z, s.Range);
            if (first < 0) { t.Cooldown = 0f; return; }
            V3 from = Top(t);
            int current = first;
            float link = dmg;
            var hitSet = new HashSet<int>();
            for (int n = 0; n <= s.Chain && current >= 0; n++)
            {
                var to = new V3(swarm.X[current], swarm.Y[current], swarm.Z[current]);
                shots.Add(new Shot { From = from, To = to, Style = ShotStyle.Chain });
                hitSet.Add(current);
                Combat.Hit(swarm, current, link, eco);
                from = to;
                link *= 0.85f;
                current = NearestExcluding(swarm, to.X, to.Z, s.Splash, hitSet);
            }
        }

        void FirePulse(TowerInstance t, TowerStats s, float dmg, Swarm swarm, BattleEconomy eco, List<Shot> shots)
        {
            shots.Add(new Shot { From = new V3(t.X, 0.01f, t.Z), To = new V3(t.X, 0.01f, t.Z), Radius = s.Range, Style = ShotStyle.Pulse });
            scratch.Clear();
            Combat.Collect(swarm, t.X, t.Z, s.Range, scratch);
            for (int k = 0; k < scratch.Count; k++)
            {
                int i = scratch[k];
                swarm.Slow(i, s.Slow, s.SlowSeconds);
                Combat.Hit(swarm, i, dmg, eco);
            }
        }

        static V3 Top(TowerInstance t) => new V3(t.X, 0.12f, t.Z);

        static float Dist2(Swarm s, int i, float x, float z)
        {
            float dx = s.X[i] - x, dz = s.Z[i] - z;
            return dx * dx + dz * dz;
        }

        static int NearestExcluding(Swarm swarm, float x, float z, float range, HashSet<int> exclude)
        {
            float best = range * range;
            int found = -1;
            for (int i = 0; i < swarm.HighWater; i++)
            {
                if (!swarm.Alive[i] || exclude.Contains(i)) continue;
                float d2 = Dist2(swarm, i, x, z);
                if (d2 <= best) { best = d2; found = i; }
            }
            return found;
        }
    }
}
