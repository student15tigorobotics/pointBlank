using Godot;
using PointBlank.Core;

namespace PointBlank
{
    /// <summary>
    /// Frame-time governor. Averages over two seconds and trades render scale, mesh budget and spawn cap
    /// for frame rate when the headset falls behind its refresh target, then recovers when there is headroom.
    /// </summary>
    public sealed class Quality
    {
        public const float TargetHz = 90f;
        public const float BudgetMs = 1000f / TargetHz;

        public float AvgMs { get; private set; } = BudgetMs;
        public float RenderScale { get; private set; } = 1f;
        public int SpawnCap { get; private set; } = (int)Balance.EnemyBaseCapacity;
        public int MeshBudget { get; private set; } = 1400;

        float acc, accTime;
        int frames;

        public bool Enabled = true;

        public void Tick(float dtSeconds, OpenXRInterface xr, SwarmRenderer renderer)
        {
            acc += dtSeconds * 1000f;
            accTime += dtSeconds;
            frames++;
            if (accTime < 2f) return;

            AvgMs = acc / frames;
            acc = 0f;
            accTime = 0f;
            frames = 0;
            if (!Enabled) return;

            if (AvgMs > BudgetMs * 1.08f)
            {
                RenderScale = Mathf.Max(0.6f, RenderScale - 0.1f);
                MeshBudget = Mathf.Max(300, MeshBudget - 200);
                SpawnCap = Mathf.Max(800, (int)(SpawnCap * 0.9f));
            }
            else if (AvgMs < BudgetMs * 0.75f)
            {
                RenderScale = Mathf.Min(1f, RenderScale + 0.05f);
                MeshBudget = Mathf.Min(2000, MeshBudget + 100);
                SpawnCap = Mathf.Min(Balance.MaxEnemies, SpawnCap + 100);
            }

            if (xr != null) xr.RenderTargetSizeMultiplier = RenderScale;
            if (renderer != null) renderer.MeshBudget = MeshBudget;
        }

        /// <summary>Applies a player-chosen tier (0 low, 1 medium, 2 high) as a starting point.</summary>
        public void SetTier(int tier)
        {
            RenderScale = tier == 0 ? 0.7f : tier == 1 ? 0.85f : 1f;
            MeshBudget = tier == 0 ? 500 : tier == 1 ? 1000 : 1600;
            SpawnCap = tier == 0 ? 1200 : tier == 1 ? 2000 : 2500;
        }
    }
}
