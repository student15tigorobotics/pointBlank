namespace PointBlank.Core
{
    public enum CheatEffect : byte { BankCredits, OverkillBoost, CoreBoost, StartCredits, RapidFire, ArsenalKey }

    public sealed class CheatDef
    {
        public string Code;
        public int Chapter;      // stage index that reveals this code in its outro
        public CheatEffect Effect;
        public int Amount;
        public string Title;
        public string Text;
    }

    public static class CheatCatalog
    {
        public static readonly CheatDef[] All =
        {
            new CheatDef { Code = "1974", Chapter = 0, Effect = CheatEffect.BankCredits, Amount = 750, Title = "Armory Credit Drop", Text = "+750 bank credits, instantly" },
            new CheatDef { Code = "3316", Chapter = 1, Effect = CheatEffect.OverkillBoost, Title = "Overkill Surge", Text = "Overkill ratio doubled in the next battle" },
            new CheatDef { Code = "7742", Chapter = 2, Effect = CheatEffect.CoreBoost, Amount = 10, Title = "Breaker Override", Text = "+10 core HP in the next battle" },
            new CheatDef { Code = "5150", Chapter = 3, Effect = CheatEffect.StartCredits, Amount = 400, Title = "Gold Reserve", Text = "+400 starting credits in the next battle" },
            new CheatDef { Code = "8080", Chapter = 4, Effect = CheatEffect.RapidFire, Title = "Thunder Rune", Text = "Weapon cooldowns halved in the next battle" },
            new CheatDef { Code = "9001", Chapter = 5, Effect = CheatEffect.ArsenalKey, Title = "Arsenal Key", Text = "Every weapon and tower unlocked permanently" },
        };

        public static CheatDef Find(string code)
        {
            foreach (var c in All) if (c.Code == code) return c;
            return null;
        }

        public static CheatDef ForChapter(int chapter)
        {
            foreach (var c in All) if (c.Chapter == chapter) return c;
            return null;
        }

        public static CheatDef ForEffect(CheatEffect effect)
        {
            foreach (var c in All) if (c.Effect == effect) return c;
            return null;
        }
    }
}
