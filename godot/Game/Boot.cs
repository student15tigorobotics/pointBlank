using Godot;
using PointBlank.Core;
using System;

namespace PointBlank
{
    /// <summary>
    /// App shell: world and XR setup, the per-frame loop, and the flow between hub, story, battle and results.
    /// Run with <c>--smoke</c> for a headless self-test (no save file is touched).
    /// </summary>
    public partial class Boot : Node3D
    {
        public static Boot Instance { get; private set; }
        public Profile Profile { get; private set; }
        public readonly Controls Controls = new Controls();
        public string CodeEntry = "";
        public bool ResetArmed;
        public bool VoiceAvailable => voice != null && voice.Available;
        public bool XrActive { get; private set; }

        readonly Quality quality = new Quality();
        Node3D content;
        Godot.Environment env;
        Voice voice;
        Hub hub;
        Dialogue dialogue;
        BattleView view;
        BattleController battle;
        OpenXRInterface xr;
        XRCamera3D xrCam;
        Camera3D deskCam;
        int stageIndex = -1;
        string state = "";

        public override void _Ready()
        {
            Instance = this;
            string[] args = OS.GetCmdlineUserArgs();
            bool smoke = Array.IndexOf(args, "--smoke") >= 0;
            bool desktop = smoke || Array.IndexOf(args, "--desktop") >= 0;

            Profile = smoke ? new Profile() : SaveStore.Load();
            BuildWorld(desktop);
            quality.SetTier(Profile.Quality);
            voice = new Voice();
            AddChild(voice);
            content = new Node3D();
            AddChild(content);
            ApplyTheme(StageCatalog.Themes[0]);

            if (smoke)
            {
                RunSmoke();
                return;
            }
            if (!Profile.PrologueSeen) PlayPrologue();
            else ShowHub("stages", "");
        }

        void BuildWorld(bool desktop)
        {
            var worldEnv = new WorldEnvironment();
            env = new Godot.Environment();
            worldEnv.Environment = env;
            AddChild(worldEnv);
            AddChild(new DirectionalLight3D { LightEnergy = 0.9f, Rotation = new Vector3(-0.9f, 0.3f, 0f) });

            deskCam = new Camera3D { Position = new Vector3(0f, 1.5f, 0f), Fov = 75f };
            AddChild(deskCam);

            if (!desktop)
            {
                xr = XRServer.FindInterface("OpenXR") as OpenXRInterface;
                if (xr != null && xr.Initialize())
                {
                    XRServer.PrimaryInterface = xr;
                    GetViewport().UseXR = true;
                    XrActive = true;
                }
            }

            var origin = new XROrigin3D();
            AddChild(origin);
            xrCam = new XRCamera3D();
            origin.AddChild(xrCam);
            var left = new XRController3D { Tracker = "left_hand" };
            var right = new XRController3D { Tracker = "right_hand" };
            origin.AddChild(left);
            origin.AddChild(right);

            Controls.Xr = XrActive;
            Controls.Left = left;
            Controls.Right = right;
            Controls.Desk = deskCam;
            xrCam.Current = XrActive;
            deskCam.Current = !XrActive;
        }

        void ApplyTheme(ThemeDef t)
        {
            env.BackgroundMode = Godot.Environment.BGMode.Color;
            env.BackgroundColor = Meshes.Hex(t.Fog);
            env.AmbientLightSource = Godot.Environment.AmbientSource.Color;
            env.AmbientLightColor = Meshes.Hex(t.Enemy[0]);
            env.AmbientLightEnergy = 0.5f;
            env.FogEnabled = true;
            env.FogLightColor = Meshes.Hex(t.Fog);
            env.FogDensity = 0.015f;
            env.GlowEnabled = Profile.Quality > 0;
            env.GlowIntensity = 0.7f;
            env.GlowBloom = 0.05f;
        }

        public void ApplyQuality()
        {
            quality.SetTier(Profile.Quality);
            env.GlowEnabled = Profile.Quality > 0;
        }

        public override void _Process(double delta)
        {
            float dt = (float)Math.Min(delta, 0.1);
            Controls.Poll(GetViewport());
            quality.Tick(dt, XrActive ? xr : null, view?.Renderer);

            Pointer[] pointers = Controls.Xr ? new[] { Controls.RightPtr, Controls.LeftPtr } : new[] { Controls.MousePtr };
            bool uiOver = Ui.Update(pointers, Controls.UiPress);

            if (state == "dialogue") dialogue?.Tick(dt, Controls.Advance);
            else if (state == "battle") TickBattle(dt, uiOver);
        }

        // ---- Flow -----------------------------------------------------------------

        void ClearContent()
        {
            Ui.Reset();
            battle = null;
            dialogue = null;
            view = null;
            hub = null;
            foreach (Node child in content.GetChildren()) child.QueueFree();
        }

        public void ShowHub(string tab, string message)
        {
            ClearContent();
            state = "hub";
            ApplyTheme(StageCatalog.Themes[0]);
            hub = new Hub(this, tab, message);
            content.AddChild(hub);
        }

        void PlayPrologue()
        {
            ClearContent();
            state = "dialogue";
            dialogue = new Dialogue(voice, Profile);
            content.AddChild(dialogue);
            dialogue.Play(Story.Prologue, () =>
            {
                Profile.PrologueSeen = true;
                SaveStore.Save(Profile);
                ShowHub("stages", "Welcome, Commander.");
            });
        }

        public void StartStage(int i)
        {
            if (!Profile.CanPlayStage(i))
            {
                ShowHub("stages", "Clear the previous chapter first");
                return;
            }
            stageIndex = i;
            ClearContent();
            var stage = StageCatalog.All[i];
            ApplyTheme(stage.Theme);
            view = new BattleView(stage);
            content.AddChild(view);
            state = "dialogue";
            dialogue = new Dialogue(voice, Profile);
            content.AddChild(dialogue);
            dialogue.Play(Story.Intro[i], BeginBattle);
        }

        void BeginBattle()
        {
            var mods = Profile.ConsumeBattleModifiers();
            SaveStore.Save(Profile);
            battle = new BattleController(view, Profile, mods, false, quality);
            dialogue?.QueueFree();
            dialogue = null;
            state = "battle";
        }

        public void StartBenchmark()
        {
            ClearContent();
            stageIndex = -1;
            ApplyTheme(StageCatalog.Themes[0]);
            view = new BattleView(StageCatalog.All[0]);
            content.AddChild(view);
            var mods = BattleModifiers.Default;
            mods.CoreMaxHp = 1000000;
            quality.Enabled = false;
            battle = new BattleController(view, Profile, mods, true, quality);
            state = "battle";
        }

        void TickBattle(float dt, bool uiOver)
        {
            if (battle == null) return;
            Node3D cam = XrActive ? (Node3D)xrCam : deskCam;
            Vector3 eye = cam.GlobalPosition;
            Vector3 forward = -cam.GlobalTransform.Basis.Z;
            battle.Tick(dt, Controls, uiOver, eye, forward);
            if (battle.Outcome != BattleOutcome.Running) EndBattle(battle.Outcome);
        }

        void EndBattle(BattleOutcome outcome)
        {
            var b = battle;
            battle = null;
            if (b.Benchmark)
            {
                quality.Enabled = true;
                Profile.BenchmarkMax = Math.Max(Profile.BenchmarkMax, b.BenchmarkResult);
                SaveStore.Save(Profile);
                ShowHub("options", "Benchmark: " + b.BenchmarkResult + " visible enemies");
                return;
            }

            bool cleared = outcome == BattleOutcome.Cleared;
            int stars = BattleEconomy.Stars(b.Eco.CoreFraction, cleared);
            int score = Scoring.Compute(b.Eco.Kills, b.Eco.OverkillCredits, stars, b.Eco.EarlyCalls);
            var entry = new ScoreEntry
            {
                Name = Leaderboard.Callsign(Profile.CallsignSeed),
                Score = score,
                Stage = stageIndex + 1,
                Date = DateTime.Now.ToString("yyyy-MM-dd"),
            };
            Profile.CallsignSeed++;
            int rank = Leaderboard.Submit(Profile.Board, entry);
            int payout = Profile.RecordStage(stageIndex, stars, b.Eco.EarnedTotal, out CheatDef revealed);
            SaveStore.Save(Profile);

            ClearContent();
            state = "result";
            ShowResult(outcome, cleared, stars, score, rank, payout, revealed, b.Eco);
        }

        void ShowResult(BattleOutcome outcome, bool cleared, int stars, int score, int rank, int payout, CheatDef revealed, BattleEconomy eco)
        {
            var root = new Node3D();
            content.AddChild(root);
            Vector3 c = new Vector3(0f, 1.5f, -1.7f);
            Ui.Quad(root, c, new Vector2(1.9f, 1.4f), Ui.Panel);
            string title = cleared ? "CHAPTER CLEARED" : outcome == BattleOutcome.Retreated ? "RETREAT" : "CORE LOST";
            Ui.Label(root, title, c + new Vector3(0f, 0.55f, 0.03f), 44, cleared ? Ui.Accent : Ui.Warn);
            Ui.Label(root, "STARS  " + stars + " / 3     BANK  +" + payout, c + new Vector3(0f, 0.36f, 0.03f), 30, Ui.Gold);
            Ui.Label(root, "SCORE  " + score + (rank >= 0 ? "     RANK #" + (rank + 1) : ""), c + new Vector3(0f, 0.2f, 0.03f), 30, Colors.White);
            Ui.Label(root, "KILLS " + eco.Kills + "   OVERKILL " + eco.OverkillCredits + " CR   EARLY CALLS " + eco.EarlyCalls,
                c + new Vector3(0f, 0.04f, 0.03f), 24, Ui.Dim);
            if (revealed != null)
                Ui.Label(root, "CODE REVEALED: " + revealed.Code + "   (enter it in CODES)", c + new Vector3(0f, -0.14f, 0.03f), 24, Ui.Accent);
            Ui.Button(root, "CONTINUE", c + new Vector3(0f, -0.48f, 0.04f), new Vector2(0.8f, 0.16f), Ui.Accent, () =>
            {
                if (cleared) PlayOutro();
                else ShowHub("stages", "Chapter failed. Upgrade in SHOP and try again.");
            }, 30);
        }

        void PlayOutro()
        {
            ClearContent();
            int chapter = stageIndex;
            ApplyTheme(StageCatalog.All[chapter].Theme);
            state = "dialogue";
            dialogue = new Dialogue(voice, Profile);
            content.AddChild(dialogue);
            dialogue.Play(Story.Outro[chapter], () =>
            {
                SaveStore.Save(Profile);
                bool finale = chapter == StageCatalog.Count - 1;
                ShowHub("shop", finale ? "The Last Frequency is over. Thank you for playing." : "Chapter complete. Upgrades are open between chapters.");
            });
        }

        // ---- Headless self-test -------------------------------------------------------

        void RunSmoke()
        {
            int failures = 0;
            void Check(bool ok, string what)
            {
                GD.Print((ok ? "ok   " : "FAIL ") + what);
                if (!ok) failures++;
            }

            foreach (var tab in new[] { "stages", "shop", "board", "codes", "options" })
            {
                ShowHub(tab, "smoke");
                Check(hub != null && hub.GetChildCount() > 0, "hub builds tab " + tab);
            }

            string json = SaveStore.ToJson(Profile);
            var copy = SaveStore.FromJson(json);
            Profile.Bank = 1234;
            copy = SaveStore.FromJson(SaveStore.ToJson(Profile));
            Check(copy.Bank == 1234 && copy.UpgradeLevels.Length == UpgradeCatalog.Count, "profile JSON round-trips");

            ClearContent();
            state = "dialogue";
            dialogue = new Dialogue(voice, Profile);
            content.AddChild(dialogue);
            bool played = false;
            dialogue.Play(Story.Intro[3], () => played = true);
            for (int n = 0; n < 600 && !played; n++) dialogue.Tick(0.1f, n % 15 == 14);
            Check(played, "dialogue plays every line and calls back");

            // Scripted battle: sweep the aim across the table, place and upgrade towers, call waves early.
            foreach (var u in UnlockCatalog.All) if (!Profile.Unlocks.Contains(u.Key)) Profile.Unlocks.Add(u.Key);
            ClearContent();
            var stage = StageCatalog.All[0];
            ApplyTheme(stage.Theme);
            view = new BattleView(stage);
            content.AddChild(view);
            var mods = Profile.ConsumeBattleModifiers();
            mods.CoreMaxHp = 300;
            battle = new BattleController(view, Profile, mods, false, quality);
            state = "battle";

            const float dt = 1f / 30f;
            int ticks = 0, maxVisible = 0;
            Vector3 target = BattleView.TableCenter;
            while (battle.Outcome == BattleOutcome.Running && ticks < 30 * 900)
            {
                ticks++;
                float t = ticks * dt;
                target = BattleView.TableCenter + new Vector3(0.9f * Mathf.Sin(t * 0.5f), 0f, 0.9f * Mathf.Cos(t * 0.37f));
                Vector3 origin = target + new Vector3(0f, 1.2f, 0.6f);
                Controls.MousePtr.Origin = origin;
                Controls.MousePtr.Dir = (target - origin).Normalized();
                Controls.MousePtr.Valid = true;
                Controls.Fire = true;
                Controls.CallWave = ticks % 240 == 1;
                Controls.Place = ticks % 20 == 0;
                Controls.Upgrade = ticks % 150 == 0;
                Controls.Sell = false;
                battle.Tick(dt, Controls, false, origin, (target - origin).Normalized());
                maxVisible = Math.Max(maxVisible, view.Renderer.VisibleTotal);
            }
            Controls.Place = Controls.Upgrade = Controls.CallWave = Controls.Fire = false;
            GD.Print("     outcome " + battle.Outcome + " after " + (ticks * dt).ToString("F0") + " s sim, kills " + battle.Eco.Kills
                + ", towers " + battle.Towers.Towers.Count + ", waves cleared " + battle.Director.WaveIndex
                + ", max visible " + maxVisible);
            Check(battle.Outcome == BattleOutcome.Cleared || battle.Outcome == BattleOutcome.Failed, "scripted battle reaches an outcome");
            Check(battle.Eco.Kills > 100, "battle produces kills");
            Check(maxVisible > 0, "renderer draws enemies");

            // Benchmark path: ramp until the cap, then report.
            StartBenchmark();
            battle.Tick(dt, Controls, false, Vector3.Zero, Vector3.Forward);
            int bench = 0;
            while (battle != null && battle.Outcome == BattleOutcome.Running && bench < 30 * 120)
            {
                bench++;
                battle.Tick(dt, Controls, false, new Vector3(0f, 1.5f, 0.5f), Vector3.Forward);
            }
            Check(battle != null && battle.Outcome == BattleOutcome.BenchmarkDone && battle.BenchmarkResult > 0, "benchmark ramps and reports");
            if (battle != null)
                GD.Print("     benchmark visible " + battle.BenchmarkResult + " over " + (bench * dt).ToString("F0") + " s, alive "
                    + battle.Swarm.AliveCount + ", renderer visible " + view.Renderer.VisibleTotal + ", outcome " + battle.Outcome);

            GD.Print(failures == 0 ? "SMOKE PASSED" : "SMOKE FAILED: " + failures);
            GetTree().Quit(failures == 0 ? 0 : 1);
        }
    }
}
