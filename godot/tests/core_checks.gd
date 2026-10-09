extends SceneTree
## Port of tests/CoreChecks/Program.cs. Run with:
##   godot --headless -s res://tests/core_checks.gd
## Prints one ok/FAIL line per check, then "N passed, M failed", and quits with 0 on success or 1 on failure.

const EPS: float = 0.00001

var _passed: int = 0
var _failed: int = 0


func _check(condition: bool, check_name: String) -> void:
	if condition:
		_passed += 1
		print("  ok   " + check_name)
	else:
		_failed += 1
		print("  FAIL " + check_name)


func _init() -> void:
	_test_stage_catalog()
	_test_battle_path()
	_test_combat_and_economy()
	_test_swarm_and_waves()
	_test_weapons()
	_test_towers()
	_test_profile()
	_test_leaderboard()
	print()
	print(str(_passed) + " passed, " + str(_failed) + " failed")
	quit(0 if _failed == 0 else 1)


## Mirrors BattlePath.Sample from the C# source using only contract calls.
## Returns [position on the XZ plane (y = 0), unit heading (y = 0)].
func _sample(bp: BattlePath, d: float) -> Array:
	var seg: int = bp.locate(d)
	var xz: Vector2
	if d >= bp.length:
		xz = Vector2(bp.vx[bp.vx.size() - 1], bp.vz[bp.vz.size() - 1])
	else:
		xz = bp.position_on(seg, d)
	var h: Vector2 = bp.heading_of(seg)
	return [Vector3(xz.x, 0.0, xz.y), Vector3(h.x, 0.0, h.y)]


func _test_stage_catalog() -> void:
	print("Stage catalog")
	var stages: Array = StageCatalog.all()
	_check(StageCatalog.count() == 6, "six chapters")
	for st in stages:
		var index_text: String = str(st["index"])
		var xz: PackedFloat32Array = st["path"]
		var bpath := BattlePath.new(xz)
		var inside := true
		for v in xz:
			if absf(v) > Balance.FIELD_HALF:
				inside = false
		_check(inside, "stage " + index_text + " path stays inside the battlefield")
		_check(bpath.length > 6.0 and bpath.length < 16.0, "stage " + index_text + " path length " + ("%.1f" % bpath.length) + " m")
		_check(st["waves"].size() == StageCatalog.WAVES_PER_STAGE, "stage " + index_text + " has " + str(StageCatalog.WAVES_PER_STAGE) + " waves")
	var last_wave_total := 0
	for w in stages[5]["waves"]:
		last_wave_total = maxi(last_wave_total, w["total_count"])
	print("  info peak wave size in chapter 6: " + str(last_wave_total))


func _test_battle_path() -> void:
	print("BattlePath")
	var p := BattlePath.new(PackedFloat32Array([0.0, 0.0, 1.0, 0.0, 1.0, 1.0]))
	_check(absf(p.length - 2.0) < EPS, "length of L-shaped path")
	var sampled_mid: Array = _sample(p, 1.5)
	var mid: Vector3 = sampled_mid[0]
	var dir: Vector3 = sampled_mid[1]
	_check(absf(mid.x - 1.0) < EPS and absf(mid.z - 0.5) < EPS, "sample midpoint of second segment")
	_check(absf(dir.z - 1.0) < EPS, "heading on second segment")
	var back: Vector3 = _sample(p, -0.5)[0]
	_check(absf(back.x + 0.5) < EPS, "negative distance extrapolates backwards")
	_check(absf(p.distance_to(0.5, 0.2) - 0.2) < EPS, "distance to path")


func _test_combat_and_economy() -> void:
	print("Combat and economy")
	var hp_result: Array = Combat.apply_to_hp(5.0, 9.0)
	var over: float = hp_result[1]
	var killed: bool = hp_result[2]
	_check(killed and absf(over - 4.0) < EPS, "overkill is damage beyond remaining hp")
	var eco := BattleEconomy.new(BattleModifiers.defaults())
	eco.on_kill(Balance.EnemyKind.DRONE, 4.0)
	_check(eco.credits == 2 and eco.overkill_credits == 1, "drone kill pays reward plus overkill (ratio 0.25)")
	eco.on_leak(Balance.EnemyKind.BRUTE)
	_check(eco.core_hp == Balance.BASE_CORE_HP - 5, "brute leak costs 5 core hp")
	_check(BattleEconomy.early_call_bonus(25.0, 1.0) == 250, "early call bonus is 10 credits per second remaining")
	_check(BattleEconomy.stars(0.85, true) == 3 and BattleEconomy.stars(0.5, true) == 2 and BattleEconomy.stars(0.1, true) == 1 and BattleEconomy.stars(1.0, false) == 0, "star thresholds")
	var mods_start := BattleModifiers.defaults()
	mods_start.start_credits = 500
	var eco_start := BattleEconomy.new(mods_start)
	_check(eco_start.credits == 500 and eco_start.earned_total == 0, "starting credits are not counted as earned")
	eco_start.earn(25)
	_check(eco_start.credits == 525 and eco_start.earned_total == 25, "earned credits still count toward earned_total")


func _test_swarm_and_waves() -> void:
	print("Swarm and waves")
	var stage: Dictionary = StageCatalog.all()[0]
	var swarm := Swarm.new(BattlePath.new(stage["path"]), Balance.MAX_ENEMIES)
	var eco2 := BattleEconomy.new(BattleModifiers.defaults())
	var director := WaveDirector.new(stage)
	var spawns: Array = []
	var spawned_total: int = 0
	var early_ok: bool = director.call_early(1.0, eco2) > 0
	_check(early_ok, "early call starts wave 1 and pays a bonus")
	var expected: int = stage["waves"][0]["total_count"]
	var dt: float = 1.0 / 72.0
	# Frame budget matches the C# loop (72 frames per second for up to 600 seconds).
	for _frame in 72 * 600:
		if director.phase == WaveDirector.Phase.FINISHED:
			break
		spawns.clear()
		director.update(dt, swarm.alive_count, spawns)
		for k in spawns:
			swarm.spawn(k, stage["hp_scale"], float(spawned_total % 100) / 100.0)
			spawned_total += 1
		swarm.step(dt, eco2)
		# Kill everything in the field so the wave can clear.
		if director.wave_index == 0 and spawned_total == expected:
			for i in swarm.high_water:
				if swarm.alive[i] == 1:
					Combat.hit(swarm, i, 1000000.0, eco2)
		if director.just_cleared:
			break
	_check(spawned_total == expected, "wave 1 spawns exactly its configured count (" + str(spawned_total) + "/" + str(expected) + ")")
	_check(director.just_cleared or director.wave_index >= 1, "wave clears when the field is empty")

	var swarm2 := Swarm.new(BattlePath.new(stage["path"]), 10)
	var eco3 := BattleEconomy.new(BattleModifiers.defaults())
	for _i in 10:
		swarm2.spawn(Balance.EnemyKind.DRONE, 1.0, 0.5)
	_check(swarm2.spawn(Balance.EnemyKind.DRONE, 1.0, 0.5) == -1, "spawning stops at capacity")
	swarm2.step(60.0, eco3)
	_check(swarm2.alive_count == 0 and eco3.leaks == 10 and eco3.core_hp == Balance.BASE_CORE_HP - 10, "drones that walk the whole path leak")
	var reused: int = swarm2.spawn(Balance.EnemyKind.WALKER, 1.0, 0.5)
	_check(reused >= 0 and swarm2.high_water == 10, "dead slots are recycled")

	var big := Swarm.new(BattlePath.new(StageCatalog.all()[5]["path"]), Balance.MAX_ENEMIES)
	var eco_big := BattleEconomy.new(BattleModifiers.defaults())
	for i in 5000:
		big.spawn(Balance.EnemyKind.DRONE, 1.0, float(i % 97) / 97.0)
	var t0: int = Time.get_ticks_usec()
	for _f in 200:
		big.step(1.0 / 72.0, eco_big)
	var elapsed_us: int = Time.get_ticks_usec() - t0
	var elapsed_ms: float = float(elapsed_us) / 1000.0
	print("  info 200 frames of 5000-enemy steps: " + str(int(elapsed_ms)) + " ms total (" + ("%.3f" % (elapsed_ms / 200.0)) + " ms/frame on this host)")

	# Spawn room: with no free slots nothing is emitted, and the pending spawns come out on a later frame.
	var room_stage: Dictionary = StageCatalog.all()[0]
	var room_total: int = room_stage["waves"][0]["total_count"]
	var room_director := WaveDirector.new(room_stage)
	room_director.call_early(1.0, BattleEconomy.new(BattleModifiers.defaults()))
	var room_spawns: Array = []
	for _pass in 5:
		room_director.update(1000.0, 0, room_spawns, 0)
	_check(room_spawns.is_empty() and room_director.phase == WaveDirector.Phase.ACTIVE, "zero spawn room emits nothing and keeps the wave pending")
	room_director.update(1000.0, 0, room_spawns)
	_check(room_spawns.size() == room_total, "pending spawns are emitted on a later frame once room is free")
	var limited_director := WaveDirector.new(room_stage)
	limited_director.call_early(1.0, BattleEconomy.new(BattleModifiers.defaults()))
	var limited_spawns: Array = []
	limited_director.update(1000.0, 0, limited_spawns, 3)
	_check(limited_spawns.size() == mini(3, room_total), "room caps the spawns emitted in one frame")


func _test_weapons() -> void:
	print("Weapons")
	var stage: Dictionary = StageCatalog.all()[0]
	var s3 := Swarm.new(BattlePath.new(stage["path"]), 50)
	var eco4 := BattleEconomy.new(BattleModifiers.defaults())
	var ahead: int = s3.spawn(Balance.EnemyKind.BRUTE, 1.0, 0.5)
	s3.x[ahead] = 0.0
	s3.y[ahead] = 0.05
	s3.z[ahead] = 1.0
	var weapons := WeaponSystem.new()
	var shots: Array = []
	var hits: int = weapons.try_fire(Balance.WeaponKind.BLASTER, Vector3(0.0, 0.05, 0.0), Vector3(0.0, 0.0, 1.0), s3, eco4, shots)
	var brute_hp: float = Balance.enemy(Balance.EnemyKind.BRUTE)["hp"]
	_check(hits == 1 and s3.hp[ahead] < brute_hp, "blaster hits enemy on the aim axis")
	_check(not weapons.ready(), "weapon goes on cooldown after firing")
	var off_axis: int = s3.spawn(Balance.EnemyKind.DRONE, 1.0, 0.1)
	s3.x[off_axis] = 0.6
	s3.y[off_axis] = 0.0
	s3.z[off_axis] = 0.2
	weapons.tick(5.0)
	var rail_hits: int = weapons.try_fire(Balance.WeaponKind.RAIL, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), s3, eco4, shots)
	_check(rail_hits >= 1 and s3.alive[ahead] == 1, "rail line damages enemies along the line")
	_check(s3.alive[off_axis] == 1, "rail ignores enemies off the line")

	# Rail: an enemy behind the origin is ignored even when it sits inside the radius of the origin.
	var rail_swarm := Swarm.new(BattlePath.new(stage["path"]), 10)
	var rail_eco := BattleEconomy.new(BattleModifiers.defaults())
	var behind: int = rail_swarm.spawn(Balance.EnemyKind.DRONE, 1.0, 0.1)
	rail_swarm.x[behind] = 0.0
	rail_swarm.y[behind] = 0.0
	rail_swarm.z[behind] = -0.01
	var in_front: int = rail_swarm.spawn(Balance.EnemyKind.DRONE, 1.0, 0.1)
	rail_swarm.x[in_front] = 0.0
	rail_swarm.y[in_front] = 0.0
	rail_swarm.z[in_front] = 0.5
	var rail_shots: Array = []
	var rail_only := WeaponSystem.new()
	var rail_only_hits: int = rail_only.try_fire(Balance.WeaponKind.RAIL, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), rail_swarm, rail_eco, rail_shots)
	_check(rail_swarm.alive[behind] == 1 and rail_swarm.alive[in_front] == 0 and rail_only_hits == 1, "rail ignores enemies behind the origin")

	# Nova: the table-plane hit is used when it lies ahead of the origin.
	var nova_swarm := Swarm.new(BattlePath.new(stage["path"]), 10)
	var nova_eco := BattleEconomy.new(BattleModifiers.defaults())
	var table_hit: int = nova_swarm.spawn(Balance.EnemyKind.DRONE, 1.0, 0.1)
	nova_swarm.x[table_hit] = 0.0
	nova_swarm.y[table_hit] = 0.0
	nova_swarm.z[table_hit] = 0.0
	var nova_shots: Array = []
	var nova_table := WeaponSystem.new()
	var nova_table_hits: int = nova_table.try_fire(Balance.WeaponKind.NOVA, Vector3(0.0, 0.5, 0.0), Vector3(0.0, -1.0, 0.0), nova_swarm, nova_eco, nova_shots)
	_check(nova_table_hits == 1 and nova_swarm.alive[table_hit] == 0, "nova bursts where the aim crosses the table")

	# Nova: when the table plane is behind the origin, the burst lands at origin + dir * range.
	var nova_back_swarm := Swarm.new(BattlePath.new(stage["path"]), 10)
	var nova_back_eco := BattleEconomy.new(BattleModifiers.defaults())
	var range_hit: int = nova_back_swarm.spawn(Balance.EnemyKind.DRONE, 1.0, 0.1)
	nova_back_swarm.x[range_hit] = 0.0
	nova_back_swarm.y[range_hit] = 0.0
	nova_back_swarm.z[range_hit] = 5.36
	var nova_range := WeaponSystem.new()
	var nova_range_hits: int = nova_range.try_fire(Balance.WeaponKind.NOVA, Vector3(0.0, -0.5, 0.0), Vector3(0.0, -0.5, 1.0), nova_back_swarm, nova_back_eco, nova_shots)
	_check(nova_range_hits == 1 and nova_back_swarm.alive[range_hit] == 0, "nova falls back to origin + dir * range when the table is behind")


func _test_towers() -> void:
	print("Towers")
	var stage: Dictionary = StageCatalog.all()[0]
	var towers := TowerField.new()
	var tower_mods := BattleModifiers.new()
	tower_mods.core_max_hp = 20
	tower_mods.overkill_ratio = 0.25
	tower_mods.early_bonus_mult = 1.0
	tower_mods.tower_cost_mult = 1.0
	tower_mods.weapon_damage_mult = 1.0
	tower_mods.tower_damage_mult = 1.0
	tower_mods.weapon_cooldown_mult = 1.0
	tower_mods.start_credits = 500
	var eco5 := BattleEconomy.new(tower_mods)
	var placed: TowerInstance = towers.place(Balance.TowerKind.TURRET, 0.0, 0.0, 60, eco5)
	_check(placed != null and eco5.credits == 440, "placing a tower spends credits")
	var s4 := Swarm.new(BattlePath.new(stage["path"]), 20)
	var target: int = s4.spawn(Balance.EnemyKind.DRONE, 1.0, 0.2)
	s4.x[target] = 0.1
	s4.y[target] = 0.0
	s4.z[target] = 0.0
	var tower_shots: Array = []
	towers.tick(0.1, s4, eco5, tower_shots, null)
	_check(tower_shots.size() == 1 and s4.alive[target] == 0, "turret kills an enemy in range")
	_check(placed != null and towers.upgrade(placed, eco5) and placed.level == 2, "tower upgrades to level 2")
	_check(placed != null and towers.sell(placed, eco5) > 0, "selling refunds part of the investment")

	# Upgrade cost goes through the economy's tower cost multiplier: round(36 * 0.84) = 30.
	var disc_mods := BattleModifiers.new()
	disc_mods.tower_cost_mult = 0.84
	disc_mods.start_credits = 500
	var eco_disc := BattleEconomy.new(disc_mods)
	var disc_towers := TowerField.new()
	var disc_turret: TowerInstance = disc_towers.place(Balance.TowerKind.TURRET, 0.0, 0.0, 60, eco_disc)
	var credits_before_upgrade: int = eco_disc.credits
	var disc_upgraded: bool = disc_turret != null and disc_towers.upgrade(disc_turret, eco_disc)
	_check(disc_upgraded and credits_before_upgrade - eco_disc.credits == 30, "level-1 turret upgrade costs round(36 * 0.84) = 30 with the tower cost multiplier")


func _test_profile() -> void:
	print("Profile, upgrades, cheats")
	var prof := Profile.new()
	prof.bank = 1000
	_check(prof.try_buy_upgrade(UpgradeCatalog.UpgradeId.CORE_ARMOR) and prof.bank == 880, "upgrade purchase deducts the level-1 price")
	var mods: BattleModifiers = prof.consume_battle_modifiers()
	_check(mods.core_max_hp == Balance.BASE_CORE_HP + 5, "core armor level adds 5 hp")
	_check(prof.try_buy_unlock(UnlockCatalog.all()[0]) and prof.has_weapon(Balance.WeaponKind.SCATTER), "unlock grants the weapon")
	_check(not prof.try_buy_unlock(UnlockCatalog.all()[0]), "unlocks cannot be bought twice")
	var denied: Dictionary = prof.redeem("1974")
	var ok_denied: bool = denied.get("ok", false)
	_check(not ok_denied and denied.get("message", "") == "ACCESS DENIED", "cheat code is locked until its chapter is cleared")
	var rec: Dictionary = prof.record_stage(0, 3, 1000)
	var payout: int = rec["payout"]
	var revealed: Dictionary = rec["revealed"]
	_check(payout == 200 + 450 + 300 and not revealed.is_empty() and revealed.get("code", "") == "1974", "clearing chapter 1 pays out and reveals code 1974")
	var bank_before: int = prof.bank
	var ok_redeem: bool = prof.redeem("1974")["ok"]
	_check(ok_redeem and prof.bank == bank_before + 750, "revealed code grants its bank bonus")
	var ok_twice: bool = prof.redeem("1974")["ok"]
	_check(not ok_twice, "codes redeem only once")
	_check(prof.can_play_stage(1) and not prof.can_play_stage(2), "stage 2 stays locked until stage 1 is cleared")
	prof.redeem("1974")
	prof.revealed.append("9001")
	var arsenal: bool = prof.redeem("9001")["ok"]
	_check(arsenal and prof.has_tower(Balance.TowerKind.SNIPER) and prof.has_weapon(Balance.WeaponKind.NOVA), "arsenal key unlocks every weapon and tower")

	var gate_prof := Profile.new()
	gate_prof.set_flag("gate_alpha")
	gate_prof.set_flag("intro_seen")
	gate_prof.set_flag("gate_beta")
	_check(gate_prof.has_flag("gate_beta") and not gate_prof.has_flag("gate_alpha") and gate_prof.has_flag("intro_seen"), "only one gate flag is kept and other flags are untouched")
	gate_prof.set_flag("gate_beta")
	_check(gate_prof.flags.size() == 2, "setting the same gate flag again does not duplicate it")

	var pend_prof := Profile.new()
	pend_prof.pending = ["NOT_A_CHEAT", "OVERKILL_BOOST"]
	var pend_mods: BattleModifiers = pend_prof.consume_battle_modifiers()
	_check(absf(pend_mods.overkill_ratio - Balance.BASE_OVERKILL_RATIO * 2.0) < EPS and pend_prof.pending.is_empty(), "unknown pending names are ignored and the queue is cleared")

	var bench_prof := Profile.new()
	bench_prof.benchmark_max = 2400
	bench_prof.benchmark_visible = 1800
	bench_prof.benchmark_tier = 2
	var bench_back: Profile = Profile.from_dict(bench_prof.to_dict())
	_check(bench_back.benchmark_max == 2400 and bench_back.benchmark_visible == 1800 and bench_back.benchmark_tier == 2, "benchmark alive, visible and tier survive a dict round trip")
	var bench_json: Dictionary = {"benchmark_visible": 1800.0, "benchmark_tier": 2.0}
	var bench_float: Profile = Profile.from_dict(bench_json)
	_check(bench_float.benchmark_visible == 1800 and bench_float.benchmark_tier == 2, "benchmark numbers loaded from JSON floats become ints")
	_check(Profile.new().benchmark_tier == -1 and Profile.from_dict({}).benchmark_tier == -1, "benchmark tier defaults to -1 when missing")


func _test_leaderboard() -> void:
	print("Leaderboard")
	var board: Array = []
	for i in 12:
		Leaderboard.submit(board, {"name": "P" + str(i), "score": i * 100 + 50, "stage": 0, "date": ""})
	_check(board.size() == Leaderboard.SIZE and board[0]["score"] == 1150, "board keeps top ten, best first")
	_check(Leaderboard.submit(board, {"name": "low", "score": 10, "stage": 0, "date": ""}) == -1, "low score does not qualify")
	_check(Leaderboard.submit(board, {"name": "mid", "score": 600, "stage": 0, "date": ""}) >= 0, "mid score ranks in")
	_check(Leaderboard.callsign(42) == Leaderboard.callsign(42), "callsigns are deterministic")
	_check(Leaderboard.callsign(-2147483648) == "NEON-SENTRY-62", "callsign for int.MIN uses posmod and stays in the word lists")
