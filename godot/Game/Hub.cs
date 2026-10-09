using Godot;
using PointBlank.Core;
using System;
using System.Text;

namespace PointBlank
{
    /// <summary>
    /// Command hub: stage select, upgrade shop, leaderboard, cheat keypad and options. Rebuilt for each tab so every
    /// button reflects the saved profile.
    /// </summary>
    public partial class Hub : Node3D
    {
        static readonly Vector3 Center = new Vector3(0f, 1.45f, -2.0f);
        static readonly string[] Tabs = { "stages", "shop", "board", "codes", "options" };
        static readonly string[] TabNames = { "STAGES", "SHOP", "BOARD", "CODES", "OPTIONS" };
        static readonly string[] ShortNames = { "STARFALL REACH", "NEON ASCENDANCY", "MIDNIGHT HARBOR", "SCARAB KING", "IRON PANTHEON", "LAST FREQUENCY" };

        readonly Boot app;
        readonly Profile profile;

        Vector3 P(float x, float y) => new Vector3(Center.X + x, Center.Y + y, Center.Z + 0.03f);

        public Hub(Boot app, string tab, string message)
        {
            this.app = app;
            profile = app.Profile;
            Ui.Quad(this, P(0f, 0f), new Vector2(2.9f, 2.05f), Ui.Panel);
            Ui.Label(this, "POINTBLANK  COMMAND", P(0f, 0.9f), 42, Ui.Accent);
            Ui.Label(this, "BANK  " + profile.Bank + " CR", P(0f, 0.76f), 28, Ui.Gold);

            for (int t = 0; t < Tabs.Length; t++)
            {
                string key = Tabs[t];
                bool selected = key == tab;
                Ui.Button(this, TabNames[t], P(-1.2f + t * 0.6f, 0.6f), new Vector2(0.56f, 0.12f), selected ? Ui.Gold : Ui.Dim,
                    () => app.ShowHub(key, ""), 26);
            }

            switch (tab)
            {
                case "shop": BuildShop(); break;
                case "board": BuildBoard(); break;
                case "codes": BuildCodes(); break;
                case "options": BuildOptions(); break;
                default: BuildStages(); break;
            }

            Ui.Label(this, message, P(0f, -0.92f), 24, Ui.Warn);
        }

        void BuildStages()
        {
            for (int i = 0; i < StageCatalog.Count; i++)
            {
                int stage = i;
                float x = -0.95f + (i % 3) * 0.95f;
                float y = 0.12f - (i / 3) * 0.5f;
                string status;
                if (!profile.CanPlayStage(i)) status = "LOCKED";
                else if (profile.StageStars[i] == 0) status = "NEW CHAPTER";
                else status = profile.StageStars[i] + " / 3 STARS";
                Ui.Button(this, (i + 1) + "  " + ShortNames[i] + "\n" + status, P(x, y), new Vector2(0.84f, 0.42f),
                    profile.CanPlayStage(i) ? Ui.Accent : Ui.Dim,
                    () => app.StartStage(stage), 24);
            }
            Ui.Label(this, "Clear a chapter to unlock the next. Upgrades can be bought in SHOP between chapters.", P(0f, -0.62f), 22, Ui.Dim);
        }

        void BuildShop()
        {
            Ui.LabelLeft(this, "UPGRADES", P(-1.38f, 0.45f), 30, Ui.Accent);
            Ui.LabelLeft(this, "UNLOCKS", P(0.1f, 0.45f), 30, Ui.Accent);
            for (int i = 0; i < UpgradeCatalog.Count; i++)
            {
                var def = UpgradeCatalog.All[i];
                int level = profile.UpgradeLevels[i];
                float y = 0.3f - i * 0.11f;
                Ui.LabelLeft(this, def.Name + "  " + level + "/" + def.MaxLevel, P(-1.38f, y), 22, Colors.White);
                string detail = def.Description;
                Ui.LabelLeft(this, detail, P(-1.38f, y - 0.045f), 16, Ui.Dim);
                var upgrade = def.Id;
                bool max = level >= def.MaxLevel;
                int cost = UpgradeCatalog.NextCost(def, level);
                var btn = Ui.Button(this, max ? "MAX" : "BUY " + cost, P(-0.42f, y), new Vector2(0.52f, 0.085f),
                    max ? Ui.Dim : Ui.Gold, null, 20);
                btn.Enabled = !max;
                if (!max) btn.OnPress = () => Purchase(upgrade);
            }
            for (int i = 0; i < UnlockCatalog.All.Length; i++)
            {
                var def = UnlockCatalog.All[i];
                float y = 0.3f - i * 0.11f;
                bool owned = profile.Unlocks.Contains(def.Key);
                Ui.LabelLeft(this, def.Title, P(0.1f, y), 22, owned ? Ui.Dim : Colors.White);
                var unlock = def;
                var btn = Ui.Button(this, owned ? "OWNED" : "BUY " + def.Cost, P(1.12f, y), new Vector2(0.52f, 0.085f),
                    owned ? Ui.Dim : Ui.Gold, null, 20);
                btn.Enabled = !owned;
                if (!owned) btn.OnPress = () => BuyUnlock(unlock);
            }
        }

        void Purchase(UpgradeId id)
        {
            string name = UpgradeCatalog.Get(id).Name;
            bool ok = profile.TryBuyUpgrade(id);
            if (ok) SaveStore.Save(profile);
            app.ShowHub("shop", ok ? name + " upgraded" : "Not enough credits");
        }

        void BuyUnlock(UnlockDef def)
        {
            bool ok = profile.TryBuyUnlock(def);
            if (ok) SaveStore.Save(profile);
            app.ShowHub("shop", ok ? def.Title + " unlocked" : "Not enough credits");
        }

        void BuildBoard()
        {
            Ui.LabelLeft(this, "#", P(-1.38f, 0.45f), 24, Ui.Accent);
            Ui.LabelLeft(this, "CALLSIGN", P(-1.2f, 0.45f), 24, Ui.Accent);
            Ui.Label(this, "SCORE", P(0.55f, 0.45f), 24, Ui.Accent);
            Ui.Label(this, "CHAPTER", P(1.2f, 0.45f), 24, Ui.Accent);
            for (int i = 0; i < Leaderboard.Size; i++)
            {
                float y = 0.3f - i * 0.11f;
                bool has = i < profile.Board.Count;
                var e = has ? profile.Board[i] : null;
                Ui.LabelLeft(this, (i + 1).ToString("00"), P(-1.38f, y), 24, Ui.Dim);
                Ui.LabelLeft(this, has ? e.Name : "-", P(-1.2f, y), 24, Colors.White);
                Ui.Label(this, has ? e.Score.ToString() : "-", P(0.55f, y), 24, Ui.Gold);
                Ui.Label(this, has ? e.Stage.ToString() : "-", P(1.2f, y), 24, Ui.Dim);
            }
        }

        void BuildCodes()
        {
            string entry = app.CodeEntry;
            var shown = new StringBuilder();
            for (int i = 0; i < 4; i++)
            {
                shown.Append(i < entry.Length ? entry[i] : '_');
                if (i < 3) shown.Append("  ");
            }
            Ui.Label(this, shown.ToString(), P(-0.85f, 0.42f), 40, Ui.Accent);

            string[] keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "CLR", "0", "ENTER" };
            for (int k = 0; k < keys.Length; k++)
            {
                string key = keys[k];
                float x = -1.2f + (k % 3) * 0.35f;
                float y = 0.1f - (k / 3) * 0.2f;
                Ui.Button(this, key, P(x, y), new Vector2(0.3f, 0.14f), key == "ENTER" ? Ui.Gold : Ui.Accent, () => Key(key), 26);
            }

            Ui.LabelLeft(this, "CHAPTER CODES", P(0.25f, 0.42f), 28, Ui.Accent);
            for (int ch = 0; ch < StageCatalog.Count; ch++)
            {
                float y = 0.2f - ch * 0.13f;
                var def = CheatCatalog.ForChapter(ch);
                if (def == null) continue;
                bool revealed = profile.Revealed.Contains(def.Code);
                bool used = profile.Redeemed.Contains(def.Code);
                string line = "CH" + (ch + 1) + "   " + (revealed ? def.Code + "   " + (used ? "USED" : "READY") : "????   LOCKED");
                Ui.LabelLeft(this, line, P(0.25f, y), 24, revealed ? Colors.White : Ui.Dim);
                if (revealed && !used)
                    Ui.LabelLeft(this, def.Title + ": " + def.Text, P(0.25f, y - 0.05f), 16, Ui.Dim);
            }
        }

        void Key(string key)
        {
            if (key == "CLR") { app.CodeEntry = ""; app.ShowHub("codes", ""); return; }
            if (key == "ENTER")
            {
                string entry = app.CodeEntry;
                app.CodeEntry = "";
                if (entry.Length < 4) { app.ShowHub("codes", "Enter four digits"); return; }
                string msg = profile.Redeem(entry, out bool ok);
                if (ok) SaveStore.Save(profile);
                app.ShowHub("codes", msg);
                return;
            }
            if (app.CodeEntry.Length < 4) app.CodeEntry += key;
            app.ShowHub("codes", "");
        }

        void BuildOptions()
        {
            Ui.Button(this, "VOICE  " + (profile.TtsOn ? "ON" : "OFF"), P(0f, 0.3f), new Vector2(1.1f, 0.12f), Ui.Accent, () =>
            {
                profile.TtsOn = !profile.TtsOn;
                SaveStore.Save(profile);
                app.ShowHub("options", "");
            }, 26);
            string[] tiers = { "LOW", "MEDIUM", "HIGH" };
            Ui.Button(this, "GRAPHICS  " + tiers[profile.Quality], P(0f, 0.12f), new Vector2(1.1f, 0.12f), Ui.Accent, () =>
            {
                profile.Quality = (profile.Quality + 1) % 3;
                app.ApplyQuality();
                SaveStore.Save(profile);
                app.ShowHub("options", "");
            }, 26);
            Ui.Button(this, "SWARM BENCHMARK", P(0f, -0.06f), new Vector2(1.1f, 0.12f), Ui.Accent, () => app.StartBenchmark(), 26);
            Ui.Button(this, app.ResetArmed ? "PRESS AGAIN TO WIPE" : "RESET CAMPAIGN", P(0f, -0.24f), new Vector2(1.1f, 0.12f), Ui.Warn, () =>
            {
                if (!app.ResetArmed) { app.ResetArmed = true; app.ShowHub("options", "Press again to wipe campaign progress"); return; }
                app.ResetArmed = false;
                profile.ResetCampaign();
                SaveStore.Save(profile);
                app.ShowHub("stages", "Campaign reset");
            }, 26);

            Ui.Label(this, "VOICE MODEL  " + (app.VoiceAvailable ? "FOUND" : "MISSING: run scripts/fetch_voice.py"), P(0f, -0.5f), 22, app.VoiceAvailable ? Colors.White : Ui.Dim);
            Ui.Label(this, "LAST BENCHMARK  " + (profile.BenchmarkMax > 0 ? profile.BenchmarkMax + " visible enemies" : "not run"), P(0f, -0.62f), 22, Colors.White);
            Ui.Label(this, "RENDER  " + (app.XrActive ? "OPENXR HEADSET" : "DESKTOP PREVIEW"), P(0f, -0.74f), 22, Colors.White);
        }
    }
}
