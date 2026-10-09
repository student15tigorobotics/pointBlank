namespace PointBlank.Core
{
    public sealed class ThemeDef
    {
        public ThemeKind Kind;
        public string Name;
        public uint[] Enemy;       // 0xRRGGBB, cycled per enemy seed
        public uint Accent, Fog, Table, Grid;
    }

    public struct SpawnGroup
    {
        public EnemyKind Kind;
        public int Count;
        public float Delay;     // seconds after wave start
        public float Interval;  // seconds between individual spawns
    }

    public sealed class WaveDef
    {
        public SpawnGroup[] Groups;
        public int TotalCount
        {
            get
            {
                int total = 0;
                foreach (var g in Groups) total += g.Count;
                return total;
            }
        }
    }

    public sealed class StageDef
    {
        public int Index;
        public string Title;
        public string Subtitle;
        public ThemeDef Theme;
        public float[] Path;     // x,z pairs, last point is the core
        public WaveDef[] Waves;
        public float HpScale;    // enemy HP multiplier for this chapter
    }

    public static class StageCatalog
    {
        public const int WavesPerStage = 8;

        public static readonly ThemeDef[] Themes =
        {
            new ThemeDef { Kind = ThemeKind.SpaceOpera, Name = "Space Opera",
                Enemy = new uint[] { 0x3DFFEA, 0xFFD23F, 0xFF4D6D, 0x7B61FF }, Accent = 0xE8F7FF, Fog = 0x05060F, Table = 0x0B1026, Grid = 0x2AF5FF },
            new ThemeDef { Kind = ThemeKind.Metropolis, Name = "Superhero Metropolis",
                Enemy = new uint[] { 0xFF3B3B, 0x3B82FF, 0xFFE14D, 0xB84DFF }, Accent = 0xFF2E88, Fog = 0x0A0716, Table = 0x140B22, Grid = 0xFF2E88 },
            new ThemeDef { Kind = ThemeKind.NoirHarbor, Name = "Noir Harbor",
                Enemy = new uint[] { 0x9BA3B5, 0x5CFFB0, 0xFFB347, 0x6B7BFF }, Accent = 0x5CFFB0, Fog = 0x06080C, Table = 0x0E131B, Grid = 0x3DFFB0 },
            new ThemeDef { Kind = ThemeKind.Egypt, Name = "Ancient Egypt",
                Enemy = new uint[] { 0xFFC53D, 0x2EE6D6, 0xF2A65A, 0xE8D8A0 }, Accent = 0xFFE08A, Fog = 0x1A1206, Table = 0x2A1E0E, Grid = 0x2EE6D6 },
            new ThemeDef { Kind = ThemeKind.Norse, Name = "Iron Pantheon",
                Enemy = new uint[] { 0x9FD8FF, 0xE0F7FF, 0x6AA8FF, 0xB8C7FF }, Accent = 0xE0F7FF, Fog = 0x061020, Table = 0x0C1B30, Grid = 0x9FD8FF },
            new ThemeDef { Kind = ThemeKind.NeonFuture, Name = "The Last Frequency",
                Enemy = new uint[] { 0xFF00E6, 0x00FFF0, 0x7CFF00, 0xFF8A00 }, Accent = 0x00FFF0, Fog = 0x04000A, Table = 0x0B0018, Grid = 0xFF00E6 },
        };

        // Paths stay inside +-1.35 m so every chapter keeps buildable ground.
        static readonly float[][] Paths =
        {
            new float[] { -1.4f, -1.2f, -0.4f, -1.2f, -0.4f, 0.2f, 0.7f, 0.2f, 0.7f, -0.6f, 1.2f, -0.6f, 1.2f, 0.9f },
            new float[] { -1.4f, 0.9f, -0.2f, 0.9f, -0.2f, -0.2f, -1.0f, -0.2f, -1.0f, -1.1f, 0.5f, -1.1f, 0.5f, 0.5f, 1.3f, 0.5f },
            new float[] { 1.4f, -1.3f, -0.3f, -1.3f, -0.3f, -0.4f, 0.9f, -0.4f, 0.9f, 0.5f, -0.9f, 0.5f, -0.9f, 1.3f, -1.3f, 1.3f },
            new float[] { -1.4f, -1.4f, 1.2f, -1.4f, 1.2f, 1.2f, -0.9f, 1.2f, -0.9f, -0.7f, 0.5f, -0.7f, 0.5f, 0.4f, -0.2f, 0.4f },
            new float[] { -1.4f, 1.3f, -0.6f, 0.3f, 0.2f, -0.5f, 1.1f, -1.1f, 1.3f, 0.1f, 0.0f, 0.9f, -0.8f, 0.0f },
            new float[] { -1.4f, -0.5f, -0.7f, -0.5f, -0.2f, 0.4f, 0.5f, 0.9f, 1.3f, 0.9f, 1.3f, -0.2f, 0.4f, -0.5f, 0.1f, -1.3f },
        };

        static readonly string[] Titles =
        {
            "Starfall Reach", "Neon Ascendancy", "Midnight Harbor",
            "Sands of the Scarab King", "Iron Pantheon", "The Last Frequency",
        };

        static readonly string[] Subtitles =
        {
            "The Hollow Tide breaches the outer colonies.",
            "The skyline becomes the front line.",
            "Something climbs out of Ravenport's storm drains.",
            "Golden scarabs cross the Sun Gate for the first time.",
            "A frozen rift shatters the gates of the Pantheon.",
            "Every rift converges on one frequency.",
        };

        public static readonly StageDef[] All = Build();

        public static int Count => All.Length;

        static StageDef[] Build()
        {
            var stages = new StageDef[Themes.Length];
            for (int s = 0; s < stages.Length; s++)
            {
                stages[s] = new StageDef
                {
                    Index = s,
                    Title = Titles[s],
                    Subtitle = Subtitles[s],
                    Theme = Themes[s],
                    Path = Paths[s],
                    HpScale = 1f + 0.2f * s,
                    Waves = WaveFactory.Build(s, WavesPerStage),
                };
            }
            return stages;
        }
    }

    public static class WaveFactory
    {
        /// <summary>Procedural waves: the swarm grows each wave, brutes join late, a Titan closes every chapter.</summary>
        public static WaveDef[] Build(int stageIndex, int waveCount)
        {
            float k = 1f + 0.35f * stageIndex;
            var waves = new WaveDef[waveCount];
            for (int w = 0; w < waveCount; w++)
            {
                var groups = new System.Collections.Generic.List<SpawnGroup>();
                groups.Add(new SpawnGroup { Kind = EnemyKind.Drone, Count = Scale(40 + 25 * w, k), Delay = 0f, Interval = 0.03f });
                if (w >= 1)
                    groups.Add(new SpawnGroup { Kind = EnemyKind.Walker, Count = Scale(14 + 10 * w, k), Delay = 2f, Interval = 0.12f });
                if (w >= 2)
                    groups.Add(new SpawnGroup { Kind = EnemyKind.Shade, Count = Scale(10 + 8 * w, k), Delay = 4f, Interval = 0.08f });
                if (w >= 4)
                    groups.Add(new SpawnGroup { Kind = EnemyKind.Brute, Count = Scale(3 + 2 * (w - 3), k), Delay = 7f, Interval = 0.8f });
                if (w == waveCount - 1)
                    groups.Add(new SpawnGroup { Kind = EnemyKind.Titan, Count = stageIndex >= 3 ? 2 : 1, Delay = 9f, Interval = 6f });
                waves[w] = new WaveDef { Groups = groups.ToArray() };
            }
            return waves;
        }

        static int Scale(int baseCount, float k) => (int)(baseCount * k + 0.5f);
    }
}
