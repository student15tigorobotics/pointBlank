using Godot;
using PointBlank.Core;
using System;
using System.Collections.Generic;

namespace PointBlank
{
    public enum BattleOutcome { Running, Cleared, Failed, Retreated, BenchmarkDone }

    /// <summary>
    /// Runs one chapter, or the swarm benchmark, on top of a BattleView. Every rule comes from the engine-free Core;
    /// this class translates controller intents into Core calls and Core events into visuals.
    /// </summary>
    public sealed class BattleController
    {
        public readonly BattleView View;
        public readonly BattleEconomy Eco;
        public readonly Swarm Swarm;
        public readonly WaveDirector Director;
        public readonly TowerField Towers = new TowerField();
        public readonly WeaponSystem Weapons = new WeaponSystem();
        public readonly bool Benchmark;
        public BattleOutcome Outcome { get; private set; } = BattleOutcome.Running;
        public int BenchmarkResult { get; private set; }

        readonly WeaponKind[] weapons;
        readonly TowerKind[] towers;
        int weaponIdx, towerIdx;
        readonly List<EnemyKind> spawns = new List<EnemyKind>();
        readonly List<Shot> shots = new List<Shot>();
        readonly HashSet<long> occupied = new HashSet<long>();
        readonly Random rng = new Random(42);
        readonly Quality quality;
        bool callRequested, retreatRequested;
        int stableVisible;
        float overBudget, benchSpawnTimer, benchElapsed, hudTimer;

        public BattleController(BattleView view, Profile profile, BattleModifiers mods, bool benchmark, Quality quality)
        {
            View = view;
            Benchmark = benchmark;
            this.quality = quality;
            Eco = new BattleEconomy(mods);
            Swarm = new Swarm(view.Path, Balance.MaxEnemies);
            Director = new WaveDirector(view.Stage);
            Towers.DamageMult = mods.TowerDamageMult;
            Weapons.DamageMult = mods.WeaponDamageMult;
            Weapons.CooldownMult = mods.WeaponCooldownMult;

            var w = new List<WeaponKind>();
            foreach (WeaponKind k in Enum.GetValues(typeof(WeaponKind))) if (benchmark ? k == WeaponKind.Blaster : profile.HasWeapon(k)) w.Add(k);
            weapons = w.ToArray();
            var t = new List<TowerKind>();
            foreach (TowerKind k in Enum.GetValues(typeof(TowerKind))) if (!benchmark && profile.HasTower(k)) t.Add(k);
            towers = t.ToArray();

            view.CallButton.OnPress = () => callRequested = true;
            view.RetreatButton.OnPress = () => retreatRequested = true;
            View.HudTower.Text = "";
        }

        public WeaponKind Weapon => weapons[weaponIdx];
        public TowerKind TowerChoice => towers.Length > 0 ? towers[towerIdx] : TowerKind.Turret;

        static int Wrap(int i, int n) => ((i % n) + n) % n;

        /// <summary>One frame. <paramref name="eye"/> and <paramref name="forward"/> are world-space head pose values.</summary>
        public void Tick(float dt, Controls c, bool uiOver, Vector3 eye, Vector3 forward)
        {
            if (Outcome != BattleOutcome.Running) return;
            int overkillBefore = Eco.OverkillCredits;
            shots.Clear();

            if (retreatRequested || c.Menu)
            {
                Outcome = BattleOutcome.Retreated;
                return;
            }

            if (!Benchmark && (callRequested || c.CallWave))
            {
                int bonus = Director.CallEarly(Eco.EarlyBonusMult, Eco);
                if (bonus > 0) View.Float("EARLY CALL +" + bonus, new Vector3(0f, 0.3f, 0f), Ui.Gold);
            }
            callRequested = false;
            retreatRequested = false;

            if (Benchmark)
            {
                BenchmarkTick(dt);
            }
            else
            {
                spawns.Clear();
                Director.Update(dt, Swarm.AliveCount, spawns);
                foreach (var k in spawns)
                {
                    if (Swarm.AliveCount >= quality.SpawnCap) break;
                    Swarm.Spawn(k, View.Stage.HpScale, (float)rng.NextDouble());
                }
                if (Director.JustCleared)
                {
                    int bonus = BattleEconomy.WaveClearBonus(Director.ClearedWaveIndex);
                    Eco.Earn(bonus);
                    View.Float("WAVE CLEAR +" + bonus, new Vector3(0f, 0.3f, 0f), Ui.Accent);
                }
            }

            Swarm.Step(dt, Eco);
            Towers.Tick(dt, Swarm, Eco, shots);
            Weapons.Tick(dt);

            View.ToLocal(c.Aim, out Vector3 aimO, out Vector3 aimD);
            if (c.Aim.Valid && c.Fire && !uiOver)
                Weapons.TryFire(Weapon, aimO.ToCore(), aimD.ToCore(), Swarm, Eco, shots);

            if (c.WeaponStep != 0 && weapons.Length > 0) weaponIdx = Wrap(weaponIdx + c.WeaponStep, weapons.Length);
            if (c.TowerStep != 0 && towers.Length > 0) towerIdx = Wrap(towerIdx + c.TowerStep, towers.Length);

            HandleBuild(c, uiOver);

            if (c.Upgrade && c.Aim.Valid && !uiOver && View.TablePoint(aimO, aimD, out Vector2 upXZ))
            {
                var t = Towers.Pick(upXZ.X, upXZ.Y, 0.12f);
                if (t != null)
                {
                    bool ok = Towers.Upgrade(t, Eco);
                    View.Float(ok ? "LEVEL " + t.Level : "NO CREDITS", new Vector3(upXZ.X, 0.25f, upXZ.Y), ok ? Ui.Gold : Ui.Warn);
                }
            }

            int shownShots = 0;
            foreach (var s in shots)
            {
                if (shownShots++ >= 60) break;
                View.Shoot(s);
            }
            if (Eco.OverkillCredits > overkillBefore && shots.Count > 0)
            {
                var last = shots[shots.Count - 1].To;
                View.Float("OVERKILL +" + (Eco.OverkillCredits - overkillBefore), new Vector3(last.X, last.Y + 0.05f, last.Z), Ui.Gold);
            }

            View.SyncTowers(Towers.Towers);
            View.TickFx(dt);
            var inv = View.GlobalTransform.AffineInverse();
            View.Renderer.Draw(Swarm, inv * eye, inv.Basis * forward);

            hudTimer -= dt;
            if (hudTimer <= 0f) { hudTimer = 0.2f; UpdateHud(); }

            if (!Benchmark)
            {
                if (Eco.CoreDestroyed) Outcome = BattleOutcome.Failed;
                else if (Director.Phase == WavePhase.Finished) Outcome = BattleOutcome.Cleared;
            }
        }

        void HandleBuild(Controls c, bool uiOver)
        {
            if (Benchmark || towers.Length == 0) { View.SetHoverPad(-1); View.HideRing(); return; }

            View.ToLocal(c.PlacePtr, out Vector3 po, out Vector3 pd);
            Vector2 spot = Vector2.Zero;
            int pad = c.PlacePtr.Valid && !uiOver ? View.PadUnder(po, pd, out spot) : -1;
            View.SetHoverPad(pad);
            if (pad >= 0)
            {
                View.ShowRing(spot, Balance.Tower(TowerChoice).Range);
                if (c.Place && c.Sell) SellNear(spot);
                else if (c.Place) PlaceAt(spot);
            }
            else if (c.Place && c.Sell && c.PlacePtr.Valid && !uiOver && View.TablePoint(po, pd, out Vector2 xz))
            {
                SellNear(xz);
                View.HideRing();
            }
            else
            {
                View.HideRing();
            }
        }

        void PlaceAt(Vector2 spot)
        {
            var kind = TowerChoice;
            int cost = Eco.TowerCost(kind);
            if (!Towers.CanPlaceAt(spot.X, spot.Y, View.Path, occupied))
            {
                return;
            }
            var t = Towers.Place(kind, spot.X, spot.Y, cost, Eco);
            if (t == null)
            {
                View.Float("NEED " + cost + " CR", new Vector3(spot.X, 0.25f, spot.Y), Ui.Warn);
                return;
            }
            occupied.Add(TowerField.PadKey(spot.X, spot.Y));
            View.Float("-" + cost, new Vector3(spot.X, 0.25f, spot.Y), Ui.Gold);
        }

        void SellNear(Vector2 at)
        {
            var t = Towers.Pick(at.X, at.Y, 0.12f);
            if (t == null) return;
            occupied.Remove(TowerField.PadKey(t.X, t.Z));
            int refund = Towers.Sell(t, Eco);
            View.Float("+" + refund, new Vector3(t.X, 0.25f, t.Z), Ui.Accent);
        }

        void BenchmarkTick(float dt)
        {
            benchSpawnTimer -= dt;
            if (benchSpawnTimer <= 0f)
            {
                benchSpawnTimer = 0.25f;
                for (int n = 0; n < 120 && Swarm.AliveCount < Balance.MaxEnemies; n++)
                    Swarm.Spawn(EnemyKind.Drone, 1f, (float)rng.NextDouble());
            }

            benchElapsed += dt;
            if (Swarm.AliveCount < 400) return;

            // Stop when frames stay over budget, when the cap is reached, or after a fixed window. Leaking drones
            // can keep the live count below the cap, so the window is what ends a healthy run.
            if (quality.AvgMs > Quality.BudgetMs * 1.08f)
            {
                overBudget += dt;
                if (overBudget > 1.5f) { Finish(stableVisible); return; }
            }
            else
            {
                overBudget = 0f;
                stableVisible = Math.Max(stableVisible, View.Renderer.VisibleTotal);
            }
            if (Swarm.AliveCount >= Balance.MaxEnemies || benchElapsed > 45f) Finish(stableVisible);
        }

        void Finish(int result)
        {
            BenchmarkResult = result;
            Outcome = BattleOutcome.BenchmarkDone;
        }

        void UpdateHud()
        {
            View.HudCredits.Text = "CREDITS  " + Eco.Credits;
            View.HudCore.Text = "CORE  " + Eco.CoreHp + " / " + Eco.CoreMaxHp;
            if (Benchmark)
            {
                View.HudWave.Text = "BENCHMARK  alive " + Swarm.AliveCount;
                View.HudTower.Text = "visible " + View.Renderer.VisibleTotal + "  (mesh " + View.Renderer.VisibleMeshes + ")";
                View.HudWeapon.Text = "";
                View.HudNote.Text = "Raise until frames drop, then the count is saved.";
                return;
            }
            string phase = Director.Phase == WavePhase.Prep
                ? "NEXT IN " + Mathf.CeilToInt(Director.PrepRemaining) + "s"
                : "ALIVE " + Swarm.AliveCount;
            View.HudWave.Text = "WAVE " + (Director.WaveIndex + 1) + " / " + Director.WaveCount + "   " + phase;
            View.HudTower.Text = towers.Length > 0
                ? "TOWER  " + Balance.Tower(TowerChoice).Name + "  " + Eco.TowerCost(TowerChoice) + " CR"
                : "TOWER  none unlocked";
            View.HudWeapon.Text = "WEAPON  " + Balance.Weapon(Weapon).Name;
            View.HudNote.Text = "L-trigger place   R-trigger fire   L-grip sell   R-B upgrade";
        }
    }
}
