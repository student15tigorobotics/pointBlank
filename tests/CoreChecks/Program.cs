using System;
using System.Collections.Generic;
using System.Diagnostics;
using PointBlank.Core;

static class Program
{
    static int passed, failed;

    static void Check(bool condition, string name)
    {
        if (condition) { passed++; Console.WriteLine("  ok   " + name); }
        else { failed++; Console.WriteLine("  FAIL " + name); }
    }

    static void Main()
    {
        Console.WriteLine("Stage catalog");
        Check(StageCatalog.Count == 6, "six chapters");
        foreach (var st in StageCatalog.All)
        {
            var path = new BattlePath(st.Path);
            bool inside = true;
            for (int i = 0; i < st.Path.Length; i++) if (Math.Abs(st.Path[i]) > Balance.FieldHalf) inside = false;
            Check(inside, "stage " + st.Index + " path stays inside the battlefield");
            Check(path.Length > 6f && path.Length < 16f, "stage " + st.Index + " path length " + path.Length.ToString("F1") + " m");
            Check(st.Waves.Length == StageCatalog.WavesPerStage, "stage " + st.Index + " has " + StageCatalog.WavesPerStage + " waves");
        }
        int lastWaveTotal = 0;
        foreach (var w in StageCatalog.All[5].Waves) lastWaveTotal = Math.Max(lastWaveTotal, w.TotalCount);
        Console.WriteLine("  info peak wave size in chapter 6: " + lastWaveTotal);

        Console.WriteLine("BattlePath");
        var p = new BattlePath(new float[] { 0f, 0f, 1f, 0f, 1f, 1f });
        Check(Math.Abs(p.Length - 2f) < 1e-5f, "length of L-shaped path");
        V3 dir;
        V3 mid = p.Sample(1.5f, out dir);
        Check(Math.Abs(mid.X - 1f) < 1e-5f && Math.Abs(mid.Z - 0.5f) < 1e-5f, "sample midpoint of second segment");
        Check(Math.Abs(dir.Z - 1f) < 1e-5f, "heading on second segment");
        V3 back = p.Sample(-0.5f, out dir);
        Check(Math.Abs(back.X + 0.5f) < 1e-5f, "negative distance extrapolates backwards");
        Check(Math.Abs(p.DistanceTo(0.5f, 0.2f) - 0.2f) < 1e-5f, "distance to path");

        Console.WriteLine("Combat and economy");
        float hp = 5f;
        bool killed;
        float over = Combat.ApplyToHp(ref hp, 9f, out killed);
        Check(killed && Math.Abs(over - 4f) < 1e-5f, "overkill is damage beyond remaining hp");
        var eco = new BattleEconomy(BattleModifiers.Default);
        eco.OnKill(EnemyKind.Drone, 4f);
        Check(eco.Credits == 2 && eco.OverkillCredits == 1, "drone kill pays reward plus overkill (ratio 0.25)");
        eco.OnLeak(EnemyKind.Brute);
        Check(eco.CoreHp == Balance.BaseCoreHp - 5, "brute leak costs 5 core hp");
        Check(BattleEconomy.EarlyCallBonus(25f, 1f) == 250, "early call bonus is 10 credits per second remaining");
        Check(BattleEconomy.Stars(0.85f, true) == 3 && BattleEconomy.Stars(0.5f, true) == 2 && BattleEconomy.Stars(0.1f, true) == 1 && BattleEconomy.Stars(1f, false) == 0, "star thresholds");

        Console.WriteLine("Swarm and waves");
        var stage = StageCatalog.All[0];
        var swarm = new Swarm(new BattlePath(stage.Path), Balance.MaxEnemies);
        var eco2 = new BattleEconomy(BattleModifiers.Default);
        var dir2 = new WaveDirector(stage);
        var spawns = new List<EnemyKind>();
        int spawnedTotal = 0;
        int calls = 0;
        bool earlyOk = dir2.CallEarly(1f, eco2) > 0;
        Check(earlyOk, "early call starts wave 1 and pays a bonus");
        int expected = stage.Waves[0].TotalCount;
        float dt = 1f / 72f;
        var sw = Stopwatch.StartNew();
        for (int frame = 0; frame < 72 * 600 && dir2.Phase != WavePhase.Finished; frame++)
        {
            spawns.Clear();
            dir2.Update(dt, swarm.AliveCount, spawns);
            foreach (var k in spawns)
            {
                swarm.Spawn(k, stage.HpScale, (spawnedTotal % 100) / 100f);
                spawnedTotal++;
            }
            swarm.Step(dt, eco2);
            // Kill everything in the field so the wave can clear.
            calls++;
            if (dir2.WaveIndex == 0 && spawnedTotal == expected)
                for (int i = 0; i < swarm.HighWater; i++) if (swarm.Alive[i]) Combat.Hit(swarm, i, 1e6f, eco2);
            if (dir2.JustCleared) break;
        }
        Check(spawnedTotal == expected, "wave 1 spawns exactly its configured count (" + spawnedTotal + "/" + expected + ")");
        Check(dir2.JustCleared || dir2.WaveIndex >= 1, "wave clears when the field is empty");

        var swarm2 = new Swarm(new BattlePath(stage.Path), 10);
        var eco3 = new BattleEconomy(BattleModifiers.Default);
        for (int i = 0; i < 10; i++) swarm2.Spawn(EnemyKind.Drone, 1f, 0.5f);
        Check(swarm2.Spawn(EnemyKind.Drone, 1f, 0.5f) == -1, "spawning stops at capacity");
        swarm2.Step(60f, eco3);
        Check(swarm2.AliveCount == 0 && eco3.Leaks == 10 && eco3.CoreHp == Balance.BaseCoreHp - 10, "drones that walk the whole path leak");
        int reused = swarm2.Spawn(EnemyKind.Walker, 1f, 0.5f);
        Check(reused >= 0 && swarm2.HighWater == 10, "dead slots are recycled");

        var big = new Swarm(new BattlePath(StageCatalog.All[5].Path), Balance.MaxEnemies);
        var ecoBig = new BattleEconomy(BattleModifiers.Default);
        for (int i = 0; i < 5000; i++) big.Spawn(EnemyKind.Drone, 1f, (i % 97) / 97f);
        sw.Restart();
        for (int f = 0; f < 200; f++) big.Step(1f / 72f, ecoBig);
        sw.Stop();
        Console.WriteLine("  info 200 frames of 5000-enemy steps: " + sw.ElapsedMilliseconds + " ms total (" + (sw.Elapsed.TotalMilliseconds / 200).ToString("F3") + " ms/frame on this host)");

        Console.WriteLine("Weapons");
        var s3 = new Swarm(new BattlePath(stage.Path), 50);
        var eco4 = new BattleEconomy(BattleModifiers.Default);
        int ahead = s3.Spawn(EnemyKind.Brute, 1f, 0.5f);
        s3.X[ahead] = 0f; s3.Y[ahead] = 0.05f; s3.Z[ahead] = 1f;
        var weapons = new WeaponSystem();
        var shots = new List<Shot>();
        int hits = weapons.TryFire(WeaponKind.Blaster, new V3(0f, 0.05f, 0f), new V3(0f, 0f, 1f), s3, eco4, shots);
        Check(hits == 1 && s3.Hp[ahead] < Balance.Enemy(EnemyKind.Brute).Hp, "blaster hits enemy on the aim axis");
        Check(!weapons.Ready, "weapon goes on cooldown after firing");
        int offAxis = s3.Spawn(EnemyKind.Drone, 1f, 0.1f);
        s3.X[offAxis] = 0.6f; s3.Y[offAxis] = 0f; s3.Z[offAxis] = 0.2f;
        weapons.Tick(5f);
        int railHits = weapons.TryFire(WeaponKind.Rail, new V3(0f, 0f, 0f), new V3(0f, 0f, 1f), s3, eco4, shots);
        Check(railHits >= 1 && s3.Alive[ahead] == true, "rail line damages enemies along the line");
        Check(s3.Alive[offAxis], "rail ignores enemies off the line");

        Console.WriteLine("Towers");
        var towers = new TowerField();
        var eco5 = new BattleEconomy(new BattleModifiers { CoreMaxHp = 20, OverkillRatio = 0.25f, EarlyBonusMult = 1f, TowerCostMult = 1f, WeaponDamageMult = 1f, TowerDamageMult = 1f, WeaponCooldownMult = 1f, StartCredits = 500 });
        var placed = towers.Place(TowerKind.Turret, 0f, 0.0f, 60, eco5);
        Check(placed != null && eco5.Credits == 440, "placing a tower spends credits");
        var s4 = new Swarm(new BattlePath(stage.Path), 20);
        int target = s4.Spawn(EnemyKind.Drone, 1f, 0.2f);
        s4.X[target] = 0.1f; s4.Y[target] = 0f; s4.Z[target] = 0.0f;
        var towerShots = new List<Shot>();
        towers.Tick(0.1f, s4, eco5, towerShots);
        Check(towerShots.Count == 1 && !s4.Alive[target], "turret kills an enemy in range");
        Check(towers.Upgrade(placed, eco5) && placed.Level == 2, "tower upgrades to level 2");
        Check(towers.Sell(placed, eco5) > 0, "selling refunds part of the investment");

        Console.WriteLine("Profile, upgrades, cheats");
        var prof = new Profile { Bank = 1000 };
        Check(prof.TryBuyUpgrade(UpgradeId.CoreArmor) && prof.Bank == 880, "upgrade purchase deducts the level-1 price");
        var mods = prof.ConsumeBattleModifiers();
        Check(mods.CoreMaxHp == Balance.BaseCoreHp + 5, "core armor level adds 5 hp");
        Check(prof.TryBuyUnlock(UnlockCatalog.All[0]) && prof.HasWeapon(WeaponKind.Scatter), "unlock grants the weapon");
        Check(!prof.TryBuyUnlock(UnlockCatalog.All[0]), "unlocks cannot be bought twice");
        CheatDef dummy;
        string denied = prof.Redeem("1974", out bool okDenied);
        Check(!okDenied && denied == "ACCESS DENIED", "cheat code is locked until its chapter is cleared");
        int payout = prof.RecordStage(0, 3, 1000, out dummy);
        Check(payout == 200 + 450 + 300 && dummy != null && dummy.Code == "1974", "clearing chapter 1 pays out and reveals code 1974");
        int bankBefore = prof.Bank;
        prof.Redeem("1974", out bool okRedeem);
        Check(okRedeem && prof.Bank == bankBefore + 750, "revealed code grants its bank bonus");
        prof.Redeem("1974", out bool okTwice);
        Check(!okTwice, "codes redeem only once");
        Check(prof.CanPlayStage(1) && !prof.CanPlayStage(2), "stage 2 stays locked until stage 1 is cleared");
        prof.Redeem("1974", out _);
        prof.Revealed.Add("9001");
        prof.Redeem("9001", out bool arsenal);
        Check(arsenal && prof.HasTower(TowerKind.Sniper) && prof.HasWeapon(WeaponKind.Nova), "arsenal key unlocks every weapon and tower");

        Console.WriteLine("Leaderboard");
        var board = new List<ScoreEntry>();
        for (int i = 0; i < 12; i++) Leaderboard.Submit(board, new ScoreEntry { Name = "P" + i, Score = i * 100 + 50 });
        Check(board.Count == Leaderboard.Size && board[0].Score == 1150, "board keeps top ten, best first");
        Check(Leaderboard.Submit(board, new ScoreEntry { Name = "low", Score = 10 }) == -1, "low score does not qualify");
        Check(Leaderboard.Submit(board, new ScoreEntry { Name = "mid", Score = 600 }) >= 0, "mid score ranks in");
        Check(Leaderboard.Callsign(42) == Leaderboard.Callsign(42), "callsigns are deterministic");

        Console.WriteLine();
        Console.WriteLine(passed + " passed, " + failed + " failed");
        Environment.Exit(failed == 0 ? 0 : 1);
    }
}
