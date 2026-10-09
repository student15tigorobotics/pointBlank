using System.Collections.Generic;

namespace PointBlank.Core
{
    public enum WavePhase : byte { Prep, Active, Finished }

    /// <summary>
    /// Drives one chapter: prep countdown, staggered spawn groups, clear detection and early-call bonuses.
    /// Pure logic; the caller applies the spawn list to the swarm.
    /// </summary>
    public sealed class WaveDirector
    {
        readonly StageDef stage;
        readonly float prepSeconds;
        float[] nextSpawn;
        int[] emitted;
        float waveTime;

        public WavePhase Phase { get; private set; }
        public int WaveIndex { get; private set; }
        public int WaveCount => stage.Waves.Length;
        public float PrepRemaining { get; private set; }
        public bool JustCleared { get; private set; }     // true for one frame after a wave is cleared
        public int ClearedWaveIndex { get; private set; }

        public WaveDirector(StageDef stage, float prepSeconds = Balance.PrepSeconds)
        {
            this.stage = stage;
            this.prepSeconds = prepSeconds;
            Phase = WavePhase.Prep;
            PrepRemaining = prepSeconds;
            BeginArrays();
        }

        void BeginArrays()
        {
            var groups = stage.Waves[WaveIndex].Groups;
            nextSpawn = new float[groups.Length];
            emitted = new int[groups.Length];
            for (int g = 0; g < groups.Length; g++) nextSpawn[g] = groups[g].Delay;
            waveTime = 0f;
        }

        /// <summary>Starts the wave now. Returns the early-call bonus for the prep time skipped.</summary>
        public int CallEarly(float bonusMultiplier, BattleEconomy economy)
        {
            if (Phase != WavePhase.Prep) return 0;
            int bonus = BattleEconomy.EarlyCallBonus(PrepRemaining, bonusMultiplier);
            economy.OnEarlyCall(bonus);
            Begin();
            return bonus;
        }

        void Begin()
        {
            Phase = WavePhase.Active;
            BeginArrays();
        }

        /// <summary>
        /// Advances timers. Appends the enemy kinds to spawn this frame into <paramref name="spawns"/>.
        /// <paramref name="aliveEnemies"/> is the swarm's live count before this frame's spawns are applied.
        /// </summary>
        public void Update(float dt, int aliveEnemies, List<EnemyKind> spawns)
        {
            JustCleared = false;
            if (Phase == WavePhase.Finished) return;

            if (Phase == WavePhase.Prep)
            {
                PrepRemaining -= dt;
                if (PrepRemaining <= 0f) Begin();
                return;
            }

            waveTime += dt;
            var groups = stage.Waves[WaveIndex].Groups;
            bool allEmitted = true;
            for (int g = 0; g < groups.Length; g++)
            {
                var grp = groups[g];
                while (emitted[g] < grp.Count && waveTime >= nextSpawn[g])
                {
                    spawns.Add(grp.Kind);
                    emitted[g]++;
                    nextSpawn[g] += grp.Interval;
                }
                if (emitted[g] < grp.Count) allEmitted = false;
            }

            if (allEmitted && aliveEnemies == 0 && spawns.Count == 0)
            {
                ClearedWaveIndex = WaveIndex;
                JustCleared = true;
                WaveIndex++;
                if (WaveIndex >= stage.Waves.Length)
                {
                    Phase = WavePhase.Finished;
                }
                else
                {
                    Phase = WavePhase.Prep;
                    PrepRemaining = prepSeconds;
                    BeginArrays();
                }
            }
        }
    }
}
