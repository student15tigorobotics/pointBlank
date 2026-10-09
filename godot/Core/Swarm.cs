using System;

namespace PointBlank.Core
{
    /// <summary>
    /// Enemy simulation in struct-of-arrays layout. Pure logic: the engine layer only reads positions.
    /// Dead slots are recycled through a free list so spawning is O(1).
    /// </summary>
    public sealed class Swarm
    {
        public readonly int Capacity;
        public readonly float[] X, Y, Z, Hp, MaxHp, Dist, Speed, SlowLeft, SlowMul, Seed, Heading;
        public readonly EnemyKind[] Kind;
        public readonly bool[] Alive;
        public int AliveCount { get; private set; }

        readonly BattlePath path;
        readonly int[] freeSlots;
        int freeCount;
        int highWater;   // first never-used slot index; iteration runs to here
        public int HighWater => highWater;

        public Swarm(BattlePath path, int capacity)
        {
            this.path = path;
            Capacity = capacity;
            X = new float[capacity]; Y = new float[capacity]; Z = new float[capacity];
            Hp = new float[capacity]; MaxHp = new float[capacity]; Dist = new float[capacity];
            Speed = new float[capacity]; SlowLeft = new float[capacity]; SlowMul = new float[capacity];
            Seed = new float[capacity]; Heading = new float[capacity];
            Kind = new EnemyKind[capacity];
            Alive = new bool[capacity];
            freeSlots = new int[capacity];
        }

        /// <summary>Spawns one enemy at the path start. Returns the slot, or -1 when full.</summary>
        public int Spawn(EnemyKind kind, float hpScale, float seed)
        {
            if (AliveCount >= Capacity) return -1;
            int i;
            if (freeCount > 0) i = freeSlots[--freeCount];
            else i = highWater++;

            var stats = Balance.Enemy(kind);
            Kind[i] = kind;
            Hp[i] = MaxHp[i] = stats.Hp * hpScale;
            Speed[i] = stats.Speed * (0.9f + 0.2f * seed);
            Dist[i] = -seed * 0.12f;   // slight stagger so spawns don't stack on one point
            SlowLeft[i] = 0f;
            SlowMul[i] = 1f;
            Seed[i] = seed;
            Alive[i] = true;
            AliveCount++;
            Place(i);
            return i;
        }

        public void Kill(int i)
        {
            if (!Alive[i]) return;
            Alive[i] = false;
            AliveCount--;
            freeSlots[freeCount++] = i;
        }

        /// <summary>Advances every enemy along the path. Enemies reaching the core deal core damage and are removed.</summary>
        public void Step(float dt, BattleEconomy economy)
        {
            for (int i = 0; i < highWater; i++)
            {
                if (!Alive[i]) continue;

                if (SlowLeft[i] > 0f)
                {
                    SlowLeft[i] -= dt;
                    if (SlowLeft[i] <= 0f) { SlowLeft[i] = 0f; SlowMul[i] = 1f; }
                }

                Dist[i] += Speed[i] * SlowMul[i] * dt;
                if (Dist[i] >= path.Length)
                {
                    economy.OnLeak(Kind[i]);
                    Kill(i);
                    continue;
                }
                Place(i);
            }
        }

        /// <summary>Applies a slow, keeping the strongest active slow.</summary>
        public void Slow(int i, float multiplier, float seconds)
        {
            if (!Alive[i]) return;
            if (SlowLeft[i] <= 0f || multiplier < SlowMul[i]) SlowMul[i] = multiplier;
            SlowLeft[i] = Math.Max(SlowLeft[i], seconds);
        }

        void Place(int i)
        {
            V3 dir;
            V3 p = path.Sample(Dist[i], out dir);
            float hover = Balance.Enemy(Kind[i]).Hover;
            X[i] = p.X;
            Y[i] = hover + 0.02f * Seed[i];
            Z[i] = p.Z;
            Heading[i] = (float)Math.Atan2(dir.X, dir.Z);
        }
    }
}
