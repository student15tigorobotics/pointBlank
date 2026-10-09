using System;

namespace PointBlank.Core
{
    /// <summary>Upgrade-derived rules applied to one battle.</summary>
    public struct BattleModifiers
    {
        public int CoreMaxHp;
        public float OverkillRatio;
        public float EarlyBonusMult;
        public float TowerCostMult;
        public float WeaponDamageMult;
        public float TowerDamageMult;
        public float WeaponCooldownMult;
        public int StartCredits;

        public static BattleModifiers Default => new BattleModifiers
        {
            CoreMaxHp = Balance.BaseCoreHp,
            OverkillRatio = Balance.BaseOverkillRatio,
            EarlyBonusMult = 1f,
            TowerCostMult = 1f,
            WeaponDamageMult = 1f,
            TowerDamageMult = 1f,
            WeaponCooldownMult = 1f,
            StartCredits = 0,
        };
    }

    /// <summary>Credits, core health and kill accounting for one battle.</summary>
    public sealed class BattleEconomy
    {
        public int Credits { get; private set; }
        public int EarnedTotal { get; private set; }
        public int CoreHp { get; private set; }
        public int CoreMaxHp { get; }
        public float OverkillRatio { get; }
        public float EarlyBonusMult { get; }
        public float TowerCostMult { get; }

        public int Kills { get; private set; }
        public int Leaks { get; private set; }
        public int EarlyCalls { get; private set; }
        public int OverkillCredits { get; private set; }
        public float OverkillDamage { get; private set; }

        float overkillCarry;

        public BattleEconomy(BattleModifiers m)
        {
            CoreMaxHp = CoreHp = m.CoreMaxHp;
            OverkillRatio = m.OverkillRatio;
            EarlyBonusMult = m.EarlyBonusMult;
            TowerCostMult = m.TowerCostMult;
            Earn(m.StartCredits);
        }

        public bool CoreDestroyed => CoreHp <= 0;
        public float CoreFraction => CoreMaxHp > 0 ? (float)CoreHp / CoreMaxHp : 0f;

        public void Earn(int amount)
        {
            if (amount <= 0) return;
            Credits += amount;
            EarnedTotal += amount;
        }

        public bool TrySpend(int amount)
        {
            if (amount > Credits) return false;
            Credits -= amount;
            return true;
        }

        public void Refund(int amount)
        {
            if (amount > 0) Credits += amount;
        }

        public int TowerCost(TowerKind kind) => (int)Math.Round(Balance.Tower(kind).Cost * TowerCostMult);

        public void OnKill(EnemyKind kind, float overkill)
        {
            Kills++;
            Earn(Balance.Enemy(kind).Reward);
            if (overkill <= 0f) return;

            OverkillDamage += overkill;
            float raw = overkill * OverkillRatio + overkillCarry;
            int whole = (int)raw;
            overkillCarry = raw - whole;
            if (whole > 0)
            {
                OverkillCredits += whole;
                Earn(whole);
            }
        }

        public void OnLeak(EnemyKind kind)
        {
            Leaks++;
            CoreHp = Math.Max(0, CoreHp - Balance.Enemy(kind).CoreDamage);
        }

        public void OnEarlyCall(int bonus)
        {
            EarlyCalls++;
            Earn(bonus);
        }

        public static int EarlyCallBonus(float remainingSeconds, float mult)
        {
            if (remainingSeconds <= 0f) return 0;
            return (int)Math.Round(remainingSeconds * Balance.EarlyCallCreditsPerSecond * mult);
        }

        public static int WaveClearBonus(int waveIndex) =>
            (int)(Balance.WaveClearBase + Balance.WaveClearPerWave * waveIndex);

        public static int Stars(float coreFraction, bool cleared)
        {
            if (!cleared) return 0;
            if (coreFraction >= Balance.Star3Ratio) return 3;
            if (coreFraction >= Balance.Star2Ratio) return 2;
            return 1;
        }

        /// <summary>Bank credits paid out when a stage is cleared.</summary>
        public static int BankPayout(int earnedTotal, int stars, bool firstClear) =>
            (int)(earnedTotal * 0.2f) + stars * 150 + (firstClear ? 300 : 0);
    }

    public static class Scoring
    {
        public static int Compute(int kills, int overkillCredits, int stars, int earlyCalls) =>
            kills * 10 + overkillCredits * 2 + stars * 250 + earlyCalls * 100;
    }
}
