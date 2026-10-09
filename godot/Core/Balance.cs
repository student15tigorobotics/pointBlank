namespace PointBlank.Core
{
    public enum EnemyKind : byte { Drone, Walker, Shade, Brute, Titan }
    public enum MeshShape : byte { Tetra, Octa, Icosa }
    public enum WeaponKind : byte { Blaster, Scatter, Rail, Arc, Nova }
    public enum TowerKind : byte { Turret, Tesla, Frost, Mortar, Sniper }
    public enum ThemeKind : byte { SpaceOpera, Metropolis, NoirHarbor, Egypt, Norse, NeonFuture }

    public struct EnemyStats
    {
        public string Name;
        public float Hp, Speed, Scale, Hover;
        public int CoreDamage, Reward;
        public MeshShape Shape;
    }

    /// <summary>Count = max targets per shot, Radius = splash / chain / line tolerance in meters.</summary>
    public struct WeaponStats
    {
        public string Name;
        public float Cooldown, Damage, Range, ConeDeg, Radius;
        public int Count;
        public int UnlockCost;
    }

    public struct TowerStats
    {
        public string Name;
        public int Cost;
        public float Range, Cooldown, Damage, Splash, Slow, SlowSeconds;
        public int Chain;
    }

    public static class Balance
    {
        // Logical battlefield: square of side 3 m centred on the table origin, table top at y = 0.
        public const float FieldHalf = 1.5f;
        public const float PadSpacing = 0.2f;
        public const float PadClearance = 0.14f;
        public const float EnemyBaseCapacity = 2500f; // design target, adapted at runtime by QualityController
        public const int MaxEnemies = 6000;
        public const int MaxTowers = 48;
        public const int MaxTowerLevel = 3;

        public const float PrepSeconds = 25f;
        public const float EarlyCallCreditsPerSecond = 10f;
        public const float WaveClearBase = 20f;
        public const float WaveClearPerWave = 6f;
        public const float BaseOverkillRatio = 0.25f;
        public const int BaseCoreHp = 20;
        public const int TowerSellPercent = 60;
        public const float TowerUpgradeCostFactor = 0.6f;
        public const float TowerUpgradeDamage = 1.45f;
        public const float TowerUpgradeCooldown = 0.9f;
        public const float Star3Ratio = 0.8f;
        public const float Star2Ratio = 0.4f;

        public static EnemyStats Enemy(EnemyKind k)
        {
            switch (k)
            {
                case EnemyKind.Drone:  return new EnemyStats { Name = "Drone",  Hp = 5f,    Speed = 0.55f, Scale = 0.035f, Hover = 0f,    CoreDamage = 1, Reward = 1, Shape = MeshShape.Tetra };
                case EnemyKind.Walker: return new EnemyStats { Name = "Walker", Hp = 14f,   Speed = 0.38f, Scale = 0.05f,  Hover = 0f,    CoreDamage = 1, Reward = 2, Shape = MeshShape.Octa };
                case EnemyKind.Shade:  return new EnemyStats { Name = "Shade",  Hp = 22f,   Speed = 0.50f, Scale = 0.05f,  Hover = 0.06f, CoreDamage = 2, Reward = 3, Shape = MeshShape.Octa };
                case EnemyKind.Brute:  return new EnemyStats { Name = "Brute",  Hp = 90f,   Speed = 0.22f, Scale = 0.09f,  Hover = 0f,    CoreDamage = 5, Reward = 8, Shape = MeshShape.Icosa };
                default:               return new EnemyStats { Name = "Titan",  Hp = 1600f, Speed = 0.12f, Scale = 0.22f,  Hover = 0f,    CoreDamage = 20, Reward = 150, Shape = MeshShape.Icosa };
            }
        }

        public static WeaponStats Weapon(WeaponKind k)
        {
            switch (k)
            {
                case WeaponKind.Blaster: return new WeaponStats { Name = "Blaster", Cooldown = 0.16f, Damage = 4f,  Range = 6f,   ConeDeg = 4f,  Radius = 0f,    Count = 1,  UnlockCost = 0 };
                case WeaponKind.Scatter: return new WeaponStats { Name = "Scatter", Cooldown = 0.65f, Damage = 5f,  Range = 1.2f, ConeDeg = 16f, Radius = 0f,    Count = 12, UnlockCost = 300 };
                case WeaponKind.Rail:    return new WeaponStats { Name = "Rail",    Cooldown = 1.1f,  Damage = 45f, Range = 4f,   ConeDeg = 0f,  Radius = 0.05f, Count = 999, UnlockCost = 500 };
                case WeaponKind.Arc:     return new WeaponStats { Name = "Arc",     Cooldown = 0.45f, Damage = 9f,  Range = 5f,   ConeDeg = 6f,  Radius = 0.22f, Count = 6,  UnlockCost = 700 };
                default:                 return new WeaponStats { Name = "Nova",    Cooldown = 1.5f,  Damage = 38f, Range = 6f,   ConeDeg = 0f,  Radius = 0.22f, Count = 1,  UnlockCost = 900 };
            }
        }

        public static TowerStats Tower(TowerKind k)
        {
            switch (k)
            {
                case TowerKind.Turret: return new TowerStats { Name = "Turret", Cost = 60,  Range = 0.45f, Cooldown = 0.22f, Damage = 5f,   Splash = 0f,    Slow = 1f,    SlowSeconds = 0f,   Chain = 0 };
                case TowerKind.Tesla:  return new TowerStats { Name = "Tesla",  Cost = 110, Range = 0.38f, Cooldown = 0.9f,  Damage = 13f,  Splash = 0.2f,  Slow = 1f,    SlowSeconds = 0f,   Chain = 4 };
                case TowerKind.Frost:  return new TowerStats { Name = "Frost",  Cost = 90,  Range = 0.36f, Cooldown = 0.5f,  Damage = 1.2f, Splash = 0f,    Slow = 0.45f, SlowSeconds = 1.2f, Chain = 0 };
                case TowerKind.Mortar: return new TowerStats { Name = "Mortar", Cost = 130, Range = 0.8f,  Cooldown = 2.2f,  Damage = 28f,  Splash = 0.18f, Slow = 1f,    SlowSeconds = 0f,   Chain = 0 };
                default:               return new TowerStats { Name = "Sniper", Cost = 170, Range = 1.1f,  Cooldown = 2.6f,  Damage = 190f, Splash = 0f,    Slow = 1f,    SlowSeconds = 0f,   Chain = 0 };
            }
        }
    }
}
