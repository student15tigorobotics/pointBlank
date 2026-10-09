using System;
using System.Collections.Generic;

namespace PointBlank.Core
{
    /// <summary>Everything that persists between sessions. Plain public fields so System.Text.Json can serialize it.</summary>
    public sealed class Profile
    {
        public int Version = 1;
        public int Bank;
        public int[] UpgradeLevels = new int[UpgradeCatalog.Count];
        public List<string> Unlocks = new List<string>();
        public int[] StageStars = new int[StageCatalog.Count];
        public List<string> Revealed = new List<string>();   // cheat codes revealed by clearing chapters
        public List<string> Redeemed = new List<string>();
        public List<string> Pending = new List<string>();    // CheatEffect names applied to the next battle
        public List<string> Flags = new List<string>();      // dialogue choices
        public List<ScoreEntry> Board = new List<ScoreEntry>();
        public int CallsignSeed = 1;
        public int BenchmarkMax;
        public bool TtsOn = true;
        public int Quality = 1;          // 0 low, 1 medium, 2 high
        public bool PrologueSeen;

        public int UpgradeLevel(UpgradeId id) => UpgradeLevels[(int)id];

        public bool HasWeapon(WeaponKind k) => k == WeaponKind.Blaster || Unlocks.Contains(UnlockCatalog.WeaponKey(k));
        public bool HasTower(TowerKind k) => k == TowerKind.Turret || Unlocks.Contains(UnlockCatalog.TowerKey(k));
        public bool HasFlag(string flag) => Flags.Contains(flag);

        public bool CanPlayStage(int stage) => stage == 0 || StageStars[stage - 1] > 0;

        public bool TryBuyUpgrade(UpgradeId id)
        {
            var def = UpgradeCatalog.Get(id);
            int level = UpgradeLevel(id);
            if (level >= def.MaxLevel) return false;
            int cost = UpgradeCatalog.NextCost(def, level);
            if (Bank < cost) return false;
            Bank -= cost;
            UpgradeLevels[(int)id] = level + 1;
            return true;
        }

        public bool TryBuyUnlock(UnlockDef def)
        {
            if (Unlocks.Contains(def.Key) || Bank < def.Cost) return false;
            Bank -= def.Cost;
            Unlocks.Add(def.Key);
            return true;
        }

        /// <summary>Applies persistent upgrades plus any cheat effects queued for this battle, then clears the queue.</summary>
        public BattleModifiers ConsumeBattleModifiers()
        {
            var m = BattleModifiers.Default;
            m.CoreMaxHp += 5 * UpgradeLevel(UpgradeId.CoreArmor);
            m.OverkillRatio += 0.15f * UpgradeLevel(UpgradeId.OverkillEngine);
            m.EarlyBonusMult += 0.25f * UpgradeLevel(UpgradeId.EarlyCallBonus);
            m.TowerCostMult = 1f - 0.08f * UpgradeLevel(UpgradeId.Logistics);
            m.WeaponDamageMult += 0.12f * UpgradeLevel(UpgradeId.WeaponTuning);
            m.TowerDamageMult += 0.12f * UpgradeLevel(UpgradeId.TowerTuning);
            m.WeaponCooldownMult = 1f - 0.06f * UpgradeLevel(UpgradeId.RapidCycle);
            m.StartCredits += 60 * UpgradeLevel(UpgradeId.FundingDrive);

            foreach (var name in Pending)
            {
                var effect = (CheatEffect)Enum.Parse(typeof(CheatEffect), name);
                var def = CheatCatalog.ForEffect(effect);
                switch (effect)
                {
                    case CheatEffect.OverkillBoost: m.OverkillRatio *= 2f; break;
                    case CheatEffect.CoreBoost: m.CoreMaxHp += def.Amount; break;
                    case CheatEffect.StartCredits: m.StartCredits += def.Amount; break;
                    case CheatEffect.RapidFire: m.WeaponCooldownMult *= 0.5f; break;
                }
            }
            Pending.Clear();
            return m;
        }

        /// <summary>Redeems a keypad code. Returns the player-facing message.</summary>
        public string Redeem(string code, out bool ok)
        {
            ok = false;
            var def = CheatCatalog.Find(code);
            if (def == null || !Revealed.Contains(code)) return "ACCESS DENIED";
            if (Redeemed.Contains(code)) return "ALREADY USED";

            switch (def.Effect)
            {
                case CheatEffect.BankCredits:
                    Bank += def.Amount;
                    break;
                case CheatEffect.ArsenalKey:
                    foreach (var u in UnlockCatalog.All) if (!Unlocks.Contains(u.Key)) Unlocks.Add(u.Key);
                    break;
                default:
                    Pending.Add(def.Effect.ToString());
                    break;
            }
            Redeemed.Add(code);
            ok = true;
            return def.Title + ": " + def.Text;
        }

        /// <summary>Records a finished battle. Returns the bank payout and the chapter code revealed by a clear (or null).</summary>
        public int RecordStage(int stage, int stars, int earnedCredits, out CheatDef revealed)
        {
            bool firstClear = StageStars[stage] == 0 && stars > 0;
            StageStars[stage] = Math.Max(StageStars[stage], stars);
            int payout = stars > 0 ? BattleEconomy.BankPayout(earnedCredits, stars, firstClear) : 0;
            Bank += payout;

            revealed = null;
            if (stars > 0)
            {
                revealed = CheatCatalog.ForChapter(stage);
                if (revealed != null && !Revealed.Contains(revealed.Code)) Revealed.Add(revealed.Code);
                else revealed = null;
            }
            return payout;
        }

        public void SetFlag(string flag)
        {
            if (!string.IsNullOrEmpty(flag) && !Flags.Contains(flag)) Flags.Add(flag);
        }

        /// <summary>Wipes campaign progress. Settings, callsign seed, benchmark result and the leaderboard are kept.</summary>
        public void ResetCampaign()
        {
            Bank = 0;
            UpgradeLevels = new int[UpgradeCatalog.Count];
            Unlocks = new List<string>();
            StageStars = new int[StageCatalog.Count];
            Revealed = new List<string>();
            Redeemed = new List<string>();
            Pending = new List<string>();
            Flags = new List<string>();
            PrologueSeen = false;
        }
    }
}
