using System;

namespace PointBlank.Core
{
    public enum UpgradeId : byte { CoreArmor, OverkillEngine, EarlyCallBonus, Logistics, WeaponTuning, TowerTuning, RapidCycle, FundingDrive }

    public sealed class UpgradeDef
    {
        public UpgradeId Id;
        public string Name;
        public string Description;
        public int MaxLevel;
        public int BaseCost;
    }

    /// <summary>Permanent, levelled upgrades bought with the bank in the Hub (stage select or between chapters).</summary>
    public static class UpgradeCatalog
    {
        public static readonly UpgradeDef[] All =
        {
            new UpgradeDef { Id = UpgradeId.CoreArmor,      Name = "Core Armor",      Description = "+5 core HP per level",            MaxLevel = 6, BaseCost = 120 },
            new UpgradeDef { Id = UpgradeId.OverkillEngine, Name = "Overkill Engine", Description = "Overkill credit ratio +0.15 per level", MaxLevel = 5, BaseCost = 150 },
            new UpgradeDef { Id = UpgradeId.EarlyCallBonus, Name = "Early Call Bonus", Description = "Early wave bonus +25% per level",   MaxLevel = 4, BaseCost = 100 },
            new UpgradeDef { Id = UpgradeId.Logistics,      Name = "Logistics",       Description = "Towers cost 8% less per level",   MaxLevel = 5, BaseCost = 130 },
            new UpgradeDef { Id = UpgradeId.WeaponTuning,   Name = "Weapon Tuning",   Description = "Weapon damage +12% per level",    MaxLevel = 5, BaseCost = 140 },
            new UpgradeDef { Id = UpgradeId.TowerTuning,    Name = "Tower Tuning",    Description = "Tower damage +12% per level",     MaxLevel = 5, BaseCost = 140 },
            new UpgradeDef { Id = UpgradeId.RapidCycle,     Name = "Rapid Cycle",     Description = "Weapon cooldown -6% per level",   MaxLevel = 5, BaseCost = 160 },
            new UpgradeDef { Id = UpgradeId.FundingDrive,   Name = "Funding Drive",   Description = "+60 starting credits per level",  MaxLevel = 5, BaseCost = 90 },
        };

        public static int Count => All.Length;

        public static UpgradeDef Get(UpgradeId id) => All[(int)id];

        /// <summary>Price of the next level when currently at <paramref name="level"/>.</summary>
        public static int NextCost(UpgradeDef def, int level) =>
            (int)Math.Round(def.BaseCost * Math.Pow(1.5, level));
    }

    /// <summary>One-time unlocks for weapons and towers.</summary>
    public sealed class UnlockDef
    {
        public string Key;      // "W:Scatter" or "T:Tesla"
        public string Title;
        public int Cost;
    }

    public static class UnlockCatalog
    {
        public static readonly UnlockDef[] All =
        {
            new UnlockDef { Key = "W:Scatter", Title = "Scatter Cannon", Cost = Balance.Weapon(WeaponKind.Scatter).UnlockCost },
            new UnlockDef { Key = "W:Rail",    Title = "Rail Lance",     Cost = Balance.Weapon(WeaponKind.Rail).UnlockCost },
            new UnlockDef { Key = "W:Arc",     Title = "Chain Arc",      Cost = Balance.Weapon(WeaponKind.Arc).UnlockCost },
            new UnlockDef { Key = "W:Nova",    Title = "Nova Grenade",   Cost = Balance.Weapon(WeaponKind.Nova).UnlockCost },
            new UnlockDef { Key = "T:Tesla",   Title = "Tesla Coil",     Cost = 250 },
            new UnlockDef { Key = "T:Frost",   Title = "Frost Emitter",  Cost = 320 },
            new UnlockDef { Key = "T:Mortar",  Title = "Mortar Battery", Cost = 400 },
            new UnlockDef { Key = "T:Sniper",  Title = "Sniper Spire",   Cost = 600 },
        };

        public static string WeaponKey(WeaponKind k) => "W:" + k;
        public static string TowerKey(TowerKind k) => "T:" + k;
    }
}
