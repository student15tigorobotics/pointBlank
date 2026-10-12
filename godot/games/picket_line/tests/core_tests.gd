# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
extends SceneTree
## Headless core checks. Run from the repository root:
##   godot --headless --path picket-line -s res://games/picket_line/tests/core_tests.gd

const DT := 1.0 / 60.0

var _count := 0
var _fails := 0


func _init() -> void:
	_test_rng()
	_test_aim()
	_test_enemy_ai()
	_test_weak_core()
	_test_pulse_hits_and_misses()
	_test_weak_crit()
	_test_flak_falloff()
	_test_lance_charge()
	_test_heat_lockout()
	_test_station_damage_and_dodge()
	_test_scoring()
	_test_schedules()
	_test_upgrades()
	_test_run_flow()
	_test_highscores()
	_test_sim_pilot_finishes()
	_test_sim_is_deterministic()
	print("CORE_TESTS %d checks, %d failed" % [_count, _fails])
	quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_count += 1
	if not cond:
		_fails += 1
		print("FAIL: " + label)


func _test_rng() -> void:
	var a := Rng.new(42)
	var b := Rng.new(42)
	var same := true
	for i in 100:
		if a.next() != b.next():
			same = false
	_check(same, "rng: same seed gives same sequence")
	var r := Rng.new(7)
	var in_range := true
	var seen_lo := false
	var seen_hi := false
	for i in 500:
		var v := r.range_i(2, 5)
		if v < 2 or v > 5:
			in_range = false
		seen_lo = seen_lo or v == 2
		seen_hi = seen_hi or v == 5
	_check(in_range and seen_lo and seen_hi, "rng: range_i is inclusive and in bounds")
	var f := Rng.new(9)
	var unit := true
	for i in 1000:
		var x := f.next()
		if x < 0.0 or x >= 1.0:
			unit = false
	_check(unit, "rng: next() stays in [0, 1)")


func _test_aim() -> void:
	var fwd := PLBalance.aim_dir(0.0, 0.0)
	_check(fwd.is_equal_approx(Vector3(0, 0, -1)), "aim: zero angles look down -Z")
	var up := PLBalance.aim_dir(0.0, 0.5)
	_check(up.y > 0.4, "aim: positive pitch looks up")
	var yp := PLBalance.aim_yaw_pitch(PLBalance.aim_dir(0.4, 0.2))
	_check(absf(yp.x - 0.4) < 0.0001 and absf(yp.y - 0.2) < 0.0001, "aim: yaw and pitch round-trip")


func _test_enemy_ai() -> void:
	var rng := Rng.new(1)
	var out: Array = []
	var ctx := {"rail": Vector3.ZERO, "fire_mult": 1.0}
	var scout := Enemy.new()
	scout.kind = PLBalance.Kind.SCOUT
	scout.pos = Vector3(0, 0, -200)
	var t := 0.0
	while scout.alive and t < 12.0:
		EnemyAI.step(scout, DT, ctx, rng, out)
		t += DT
	_check(not scout.alive and out.size() == 1 and out[0].type == "crash", "ai: scout dives and crashes once")
	_check(out.size() == 1 and float(out[0].damage) == 6.0, "ai: scout crash deals 6 hull damage")

	out.clear()
	var gun := Enemy.new()
	gun.kind = PLBalance.Kind.GUNSHIP
	gun.pos = Vector3(0, 0, -400)
	gun.fire_timer = 999.0
	for i in 60 * 20:
		EnemyAI.step(gun, DT, ctx, rng, out)
	var gun_dist := gun.pos.length()
	_check(absf(gun_dist - PLBalance.ATTACK_DIST) < 2.0, "ai: gunship holds at attack range (got %.1f)" % gun_dist)


func _test_weak_core() -> void:
	var ctx := {"rail": Vector3.ZERO, "fire_mult": 1.0}
	var rng := Rng.new(2)
	var out: Array = []
	var c := Enemy.new()
	c.kind = PLBalance.Kind.CARRIER
	c.pos = Vector3(0, 0, -300)
	c.weak_radius = 2.6
	c.weak_dist = 7.5
	c.age = 0.5
	c.fire_timer = 999.0
	EnemyAI.step(c, 0.0, ctx, rng, out)
	_check(c.weak_open, "weak: carrier core open in the first 1.5 s")
	c.age = 2.5
	EnemyAI.step(c, 0.0, ctx, rng, out)
	_check(not c.weak_open, "weak: carrier core closed between 1.5 s and 4 s")


func _test_pulse_hits_and_misses() -> void:
	var station := Station.new()
	var projectiles := PLProjectiles.new()
	var target := _enemy(PLBalance.Kind.DRONE, Vector3(0, 0, -100), 50.0)
	projectiles.fire_player(PLBalance.Weapon.PULSE, Vector3.ZERO, Vector3(0, 0, -1), 9.0, {})
	var hit_ev: Dictionary = {}
	for i in 60:
		for ev in projectiles.step(DT, [target], station):
			if ev.type == "hit":
				hit_ev = ev
	_check(not hit_ev.is_empty() and float(hit_ev.damage) == 9.0 and not hit_ev.crit, "pulse: straight shot hits for 9")
	_check(absf(target.hp - 41.0) < 0.001, "pulse: target loses 9 hp")

	var miss := _enemy(PLBalance.Kind.DRONE, Vector3(60, 0, -100), 2.0)
	projectiles.fire_player(PLBalance.Weapon.PULSE, Vector3.ZERO, Vector3(0, 0, -1), 9.0, {})
	var expired := false
	for i in 60 * 3:
		for ev in projectiles.step(DT, [miss], station):
			if ev.type == "shot_expired":
				expired = true
	_check(expired and miss.hp == miss.max_hp, "pulse: off-axis shot misses and expires")


func _test_weak_crit() -> void:
	var station := Station.new()
	var projectiles := PLProjectiles.new()
	var gun := _enemy(PLBalance.Kind.GUNSHIP, Vector3(0, 0, -100), 170.0)
	gun.weak_radius = 1.1
	gun.weak_dist = 3.4
	gun.weak_offset = Vector3(0, 0, 3.4)
	gun.weak_open = true
	projectiles.fire_player(PLBalance.Weapon.PULSE, Vector3.ZERO, Vector3(0, 0, -1), 9.0, {})
	var ev_hit: Dictionary = {}
	for i in 60:
		for ev in projectiles.step(DT, [gun], station):
			if ev.type == "hit":
				ev_hit = ev
	_check(not ev_hit.is_empty() and ev_hit.crit, "weak: open core registers a crit")
	_check(not ev_hit.is_empty() and absf(float(ev_hit.damage) - 9.0 * PLBalance.WEAK_DAMAGE) < 0.001, "weak: crit deals 2.2x damage")

	var closed := _enemy(PLBalance.Kind.GUNSHIP, Vector3(0, 0, -100), 170.0)
	closed.weak_radius = 1.1
	closed.weak_offset = Vector3(0, 0, 3.4)
	closed.weak_open = false
	projectiles.fire_player(PLBalance.Weapon.PULSE, Vector3.ZERO, Vector3(0, 0, -1), 9.0, {})
	var closed_crit := false
	for i in 60:
		for ev in projectiles.step(DT, [closed], station):
			if ev.type == "hit" and ev.crit:
				closed_crit = true
	_check(not closed_crit, "weak: closed core never crits")


func _test_flak_falloff() -> void:
	var station := Station.new()
	var projectiles := PLProjectiles.new()
	var a := _enemy(PLBalance.Kind.DRONE, Vector3(0, 0, -30), 100.0)
	var b := _enemy(PLBalance.Kind.DRONE, Vector3(3, 0, -30), 100.0)
	projectiles.fire_player(PLBalance.Weapon.FLAK, Vector3.ZERO, Vector3(0, 0, -1), 55.0, {})
	var detonated := false
	for i in 60 * 2:
		for ev in projectiles.step(DT, [a, b], station):
			if ev.type == "detonate":
				detonated = true
	var loss_a := 100.0 - a.hp
	var loss_b := 100.0 - b.hp
	_check(detonated, "flak: detonates on proximity to an alien")
	_check(loss_a > loss_b and loss_b > 0.0, "flak: splash damage falls off with distance (%.1f vs %.1f)" % [loss_a, loss_b])


func _test_lance_charge() -> void:
	var station := Station.new()
	var projectiles := PLProjectiles.new()
	var weapons := Weapons.new()
	weapons.select(PLBalance.Weapon.LANCE)
	var enemies: Array = []
	var rng := Rng.new(3)
	# Tap shorter than charge_min: no shot.
	weapons.try_fire(0.1, {"fire_held": true, "fire_pressed": true}, station, Vector3.ZERO, Vector3(0, 0, -1), projectiles, enemies, rng)
	weapons.try_fire(0.05, {"fire_held": false}, station, Vector3.ZERO, Vector3(0, 0, -1), projectiles, enemies, rng)
	_check(projectiles.active_player().is_empty(), "lance: release before charge_min fires nothing")
	# Full charge: maximum damage.
	weapons.update(2.0)
	weapons.try_fire(1.5, {"fire_held": true}, station, Vector3.ZERO, Vector3(0, 0, -1), projectiles, enemies, rng)
	var ev := weapons.try_fire(0.02, {"fire_held": false}, station, Vector3.ZERO, Vector3(0, 0, -1), projectiles, enemies, rng)
	var shot_ok := false
	for e in ev:
		if e.type == "shot" and float(e.charge) >= 0.999:
			shot_ok = true
	_check(shot_ok, "lance: full charge fires at full power")
	var shots := projectiles.active_player()
	_check(shots.size() == 1 and absf(float(shots[0].damage) - 220.0) < 0.01, "lance: full charge deals 220")


func _test_heat_lockout() -> void:
	var station := Station.new()
	var projectiles := PLProjectiles.new()
	var weapons := Weapons.new()
	var enemies: Array = []
	var rng := Rng.new(4)
	var fired := 0
	var steps := 0
	while not station.overheated and steps < 2000:
		weapons.update(0.09)
		for e in weapons.try_fire(0.09, {"fire_held": true}, station, Vector3.ZERO, Vector3(0, 0, -1), projectiles, enemies, rng):
			if e.type == "shot":
				fired += 1
		steps += 1
	_check(station.overheated and fired > 20, "heat: sustained pulse fire overheats (%d shots)" % fired)
	var before := fired
	for i in 30:
		weapons.update(0.09)
		for e in weapons.try_fire(0.09, {"fire_held": true}, station, Vector3.ZERO, Vector3(0, 0, -1), projectiles, enemies, rng):
			if e.type == "shot":
				fired += 1
	_check(fired == before, "heat: no shots while overheated")
	for i in 600:
		station.step(0.05)
		if not station.overheated:
			break
	_check(not station.overheated and station.heat < PLBalance.HEAT_RECOVER, "heat: cooling below 25 clears the lockout")


func _test_station_damage_and_dodge() -> void:
	var s := Station.new()
	_check(s.dodge(1.0), "dodge: starts when off cooldown")
	_check(not s.dodge(1.0), "dodge: refuses a second dodge during cooldown")
	var blocked := s.take_damage(50.0, "beam")
	_check(blocked.blocked and s.hull == PLBalance.STATION_HULL, "dodge: i-frames block all damage")
	for i in 30:
		s.step(0.02)
	_check(s.iframes <= 0.0, "dodge: i-frames end after 0.28 s")
	var r1 := s.take_damage(50.0, "beam")
	_check(r1.applied_shield == 50.0 and s.hull == PLBalance.STATION_HULL, "shield: absorbs damage before hull")
	var r2 := s.take_damage(60.0, "beam")
	_check(absf(s.hull - (PLBalance.STATION_HULL - 10.0)) < 0.001 and r2.applied_hull == 10.0, "shield: spill-over reaches hull")


func _test_scoring() -> void:
	_check(PLScoring.combo_mult(0) == 1 and PLScoring.combo_mult(3) == 2, "score: combo steps every 3 kills")
	_check(PLScoring.combo_mult(99) == PLBalance.COMBO_MAX, "score: combo capped")
	_check(PLScoring.kill_points(100, 2, true, true) == 350, "score: weak + snap on a 2x chain is 350")
	_check(PLScoring.sector_bonus(0, true) == 1000 + 2000 and PLScoring.sector_bonus(2, false) == 3000, "score: sector bonus with clean bonus")


func _test_schedules() -> void:
	var a := Sectors.schedule(1, PLBalance.Diff.ENSIGN, Rng.new(5))
	var b := Sectors.schedule(1, PLBalance.Diff.ENSIGN, Rng.new(5))
	_check(str(a) == str(b), "schedule: same seed gives same waves")
	var sorted := true
	for i in range(1, a.size()):
		if float(a[i].t) < float(a[i - 1].t):
			sorted = false
	_check(sorted, "schedule: sorted by time")
	_check(a.size() > 0 and bool(a[a.size() - 1].boss) and int(a[a.size() - 1].kind) == PLBalance.Kind.CARRIER,
		"schedule: sector 2 ends with a carrier boss")
	var last5 := Sectors.schedule(5, PLBalance.Diff.ENSIGN, Rng.new(8))
	_check(int(last5[last5.size() - 1].kind) == PLBalance.Kind.DREADNOUGHT, "schedule: sector 6 ends with the dreadnought")
	var cadet_total := _total_count(Sectors.schedule(0, PLBalance.Diff.CADET, Rng.new(1)))
	var commander_total := _total_count(Sectors.schedule(0, PLBalance.Diff.COMMANDER, Rng.new(1)))
	_check(commander_total > cadet_total, "schedule: commander spawns more aliens than cadet (%d vs %d)" % [commander_total, cadet_total])


func _total_count(events: Array) -> int:
	var n := 0
	for ev in events:
		n += int(ev.count)
	return n


func _test_upgrades() -> void:
	_check(int(Upgrades.mods_for(["swarm_pods"]).pods_add) == 2, "upgrades: pods_add adds 2")
	_check(absf(float(Upgrades.mods_for(["heat_sinks", "heat_sinks"]).heat_mult) - 0.5625) < 0.0001, "upgrades: multiplicative mods compound")
	var owned := ["heat_sinks"]
	var offer := Upgrades.offer(Rng.new(11), owned, 3)
	var unique: bool = offer.size() == 3 and offer[0] != offer[1] and offer[1] != offer[2] and offer[0] != offer[2]
	_check(unique and not offer.has("heat_sinks"), "upgrades: offer is 3 distinct unowned cards")


func _test_run_flow() -> void:
	var run := Run.new(3, PLBalance.Diff.ENSIGN)
	var sim := run.start_sector()
	_check(not sim.finished and run.sector == 0, "run: starts at sector 1")
	sim.finished = true
	sim.won = true
	run.finish_sector(sim)
	_check(run.offer_upgrades().size() == 3, "run: a win offers three upgrades")
	run.choose(run.offer_upgrades()[0])
	_check(run.sector == 1 and run.owned.size() == 1, "run: choosing moves to the next sector and keeps the card")
	var lost := Sim.new(1, PLBalance.Diff.ENSIGN, 9)
	lost.won = false
	run.finish_sector(lost)
	_check(run.is_over() and not run.is_victory(), "run: a loss ends the run")


func _test_highscores() -> void:
	var scores: Array = []
	for i in 10:
		scores.append({"score": 1000 - 100 * i})
	var rank := SaveData.add_highscore(scores, {"score": 550})
	_check(rank == 5 and scores.size() == 10, "highscores: 550 ranks 6th and table stays at ten")
	_check(int(scores[0].score) == 1000 and int(scores[scores.size() - 1].score) >= 200, "highscores: sorted, lowest fallen off")
	_check(SaveData.add_highscore(scores, {"score": 50}) == -1 and scores.size() == 10, "highscores: a low score does not make the table")


func _test_sim_pilot_finishes() -> void:
	var sim := Sim.new(0, PLBalance.Diff.ENSIGN, 11)
	var steps := _run_pilot(sim, 60 * 400)
	_check(sim.finished, "sim: sector 1 finishes under a scripted pilot (%d steps)" % steps)
	print("  sector 1 pilot: won=%s score=%d kills=%d accuracy=%.2f" % [sim.won, sim.score, sim.kills, sim.accuracy()])


func _test_sim_is_deterministic() -> void:
	var a := Sim.new(2, PLBalance.Diff.ENSIGN, 77)
	var b := Sim.new(2, PLBalance.Diff.ENSIGN, 77)
	_run_pilot(a, 60 * 30)
	_run_pilot(b, 60 * 30)
	_check(a.score == b.score and a.kills == b.kills and a.shots == b.shots, "sim: same seed and pilot give the same result")


func _run_pilot(sim: Sim, max_steps: int) -> int:
	var steps := 0
	while not sim.finished and steps < max_steps:
		sim.step(DT, _pilot_cmd(sim))
		steps += 1
	return steps


## A simple scripted pilot: track the nearest alien and hold fire.
func _pilot_cmd(sim: Sim) -> Dictionary:
	var target: Enemy = null
	var best := INF
	for e: Enemy in sim.enemies:
		if e.alive and e.pos.length() < best:
			best = e.pos.length()
			target = e
	if target == null:
		return {"fire_held": false}
	var want := PLBalance.aim_yaw_pitch(target.pos)
	var cur := Vector2(sim.station.yaw, sim.station.pitch)
	var d := want - cur
	return {"fire_held": true, "aim": Vector2(clampf(d.x, -0.12, 0.12), clampf(d.y, -0.12, 0.12))}


func _enemy(kind: int, pos: Vector3, hp: float) -> Enemy:
	var e := Enemy.new()
	e.id = randi() % 100000 + 1
	e.kind = kind
	e.pos = pos
	e.radius = float(PLBalance.ENEMY_DEFS[kind].radius)
	e.hp = hp
	e.max_hp = hp
	return e
