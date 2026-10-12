# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Sim
extends RefCounted
## Authoritative step for one sector. The engine layer feeds commands in and reads state back out.
##
## cmd keys (all optional): aim (Vector2 yaw/pitch delta, rad), move_x, move_y (-1..1), scope (bool),
## focus_held (bool), fire_held (bool), fire_pressed (bool), dodge_pressed (bool), dodge_dir (float),
## select (int weapon, -1 for none), cycle (int -1/0/+1).

var sector := 0
var difficulty := 0
var mods: Dictionary = {}
var station: Station
var weapons: Weapons
var projectiles: PLProjectiles
var enemies: Array = []
var schedule: Array = []
var time := 0.0
var score := 0
var combo := 0
var combo_mult := 1
var kills := 0
var shots := 0
var hits := 0
var snaps := 0
var finished := false
var won := false
var clean := false

var _rng: Rng
var _diff: Dictionary
var _next_item := 0
var _last_group := -1
var _next_id := 1
var _last_kill_time := -1000.0
var _ctx: Dictionary = {}


func _init(sector_index: int, diff_level: int, seed_value: int, mods_in: Dictionary = {}) -> void:
	sector = clampi(sector_index, 0, Sectors.count() - 1)
	difficulty = diff_level
	mods = Upgrades.with_defaults(mods_in)
	_rng = Rng.new(seed_value)
	_diff = PLBalance.difficulty(diff_level)
	station = Station.new(mods)
	weapons = Weapons.new(mods)
	projectiles = PLProjectiles.new()
	schedule = Sectors.schedule(sector, diff_level, Rng.new(seed_value * 7919 + sector + 1))
	_ctx = {"rail": Vector3.ZERO, "fire_mult": float(_diff.fire_mult)}


## Advances the sector by dt real seconds. Returns the events raised this step.
func step(dt: float, cmd: Dictionary) -> Array:
	var events: Array = []
	if finished or dt <= 0.0:
		return events
	_apply_controls(dt, cmd, events)
	station.step(dt)
	weapons.update(dt)
	var fire_events := weapons.try_fire(dt, cmd, station, station.muzzle(), station.forward(),
		projectiles, enemies, _rng)
	for ev in fire_events:
		if ev.type == "shot":
			shots += int(ev.count)
	events.append_array(fire_events)
	var sim_dt := dt * (PLBalance.FOCUS_TIME_SCALE if station.focusing else 1.0)
	time += sim_dt
	_spawn_due(events)
	_run_ai(sim_dt, events)
	_run_projectiles(sim_dt, events)
	_process_kills(events)
	_cleanup(sim_dt)
	_check_end(events)
	return events


func accuracy() -> float:
	return float(hits) / maxf(1.0, float(shots))


func alive_count() -> int:
	var n := 0
	for e: Enemy in enemies:
		if e.alive:
			n += 1
	return n


## Seconds left before the combo chain drops.
func combo_left() -> float:
	return maxf(0.0, PLBalance.COMBO_WINDOW - (time - _last_kill_time))


func _apply_controls(dt: float, cmd: Dictionary, events: Array) -> void:
	var aim: Vector2 = cmd.get("aim", Vector2.ZERO)
	station.set_aim(aim.x, aim.y)
	station.move_rail(float(cmd.get("move_x", 0.0)), float(cmd.get("move_y", 0.0)), dt)
	station.scoping = bool(cmd.get("scope", false))
	station.focus_held = bool(cmd.get("focus_held", false))
	var sel := int(cmd.get("select", -1))
	if sel >= 0 and sel != weapons.current:
		weapons.select(sel)
		events.append({"type": "weapon", "weapon": weapons.current})
	var cyc := int(cmd.get("cycle", 0))
	if cyc != 0:
		weapons.cycle(cyc)
		events.append({"type": "weapon", "weapon": weapons.current})
	if bool(cmd.get("dodge_pressed", false)) and station.dodge(float(cmd.get("dodge_dir", 1.0))):
		events.append({"type": "dodge", "dir": station.dodge_dir})


func _spawn_due(events: Array) -> void:
	while _next_item < schedule.size() and float(schedule[_next_item].t) <= time:
		var item: Dictionary = schedule[_next_item]
		_next_item += 1
		var group := int(item.group)
		var boss: bool = item.boss
		if boss:
			events.append({"type": "boss_warning", "kind": int(item.kind)})
		elif group != _last_group:
			events.append({"type": "wave_start", "wave": group})
		_last_group = group
		var yaw := _rng.range_f(-1.2, 1.2)
		var pitch := _rng.range_f(-0.1, 0.6)
		var dist := _rng.range_f(PLBalance.SPAWN_MIN, PLBalance.SPAWN_MAX)
		for i in int(item.count):
			var dir_pos := PLBalance.aim_dir(yaw + _rng.range_f(-0.06, 0.06), pitch + _rng.range_f(-0.04, 0.04))
			var d := clampf(dist + _rng.range_f(-40.0, 40.0), PLBalance.SPAWN_MIN, PLBalance.SPAWN_MAX)
			var e := _make_enemy(int(item.kind), dir_pos * d, group, boss, float(item.get("hp_mult", 1.0)))
			if boss:
				events.append({"type": "boss_spawn", "enemy_id": e.id, "kind": e.kind})


func _make_enemy(kind: int, pos: Vector3, group: int, boss: bool, hp_mult: float) -> Enemy:
	var def: Dictionary = PLBalance.ENEMY_DEFS[kind]
	var e := Enemy.new()
	e.id = _next_id
	_next_id += 1
	e.kind = kind
	e.pos = pos
	e.radius = float(def.radius)
	e.max_hp = float(def.hp) * float(_diff.hp_mult) * hp_mult
	e.hp = e.max_hp
	e.weak_radius = float(def.weak_radius)
	e.weak_dist = float(def.weak_dist)
	e.points = int(def.points)
	e.group = group
	e.boss = boss
	e.fire_timer = float(def.interval)
	e.launch_timer = 4.0 if kind == PLBalance.Kind.CARRIER else 0.0
	enemies.append(e)
	return e


func _run_ai(sim_dt: float, events: Array) -> void:
	_ctx.rail = station.rail_point()
	var out: Array = []
	for e: Enemy in enemies:
		if e.alive:
			EnemyAI.step(e, sim_dt, _ctx, _rng, out)
	for ev in out:
		match ev.type:
			"launch":
				_launch(ev, events)
			"crash":
				_crash(ev, events)
			"enemy_fire":
				_resolve_fire(ev, events)
			_:
				events.append(ev)


func _launch(ev: Dictionary, events: Array) -> void:
	for i in int(ev.count):
		var off := Vector3(_rng.range_f(-6.0, 6.0), _rng.range_f(-3.0, 3.0), _rng.range_f(-6.0, 6.0))
		_make_enemy(int(ev.kind), ev.pos + off, int(ev.group), false, 1.0)
	events.append({"type": "launch", "kind": int(ev.kind), "count": int(ev.count), "pos": ev.pos})


func _crash(ev: Dictionary, events: Array) -> void:
	events.append({"type": "crash", "kind": int(ev.kind), "pos": ev.pos})
	var r := station.take_damage(float(ev.damage), "crash")
	events.append({"type": "player_hit", "kind": "crash", "damage": float(ev.damage),
		"applied_hull": r.applied_hull, "applied_shield": r.applied_shield, "blocked": r.blocked, "pos": ev.pos})


func _resolve_fire(ev: Dictionary, events: Array) -> void:
	if String(ev.mode) == "shell":
		projectiles.fire_enemy_shell(ev.from, ev.to, PLBalance.SHELL_SPEED, float(ev.damage))
		events.append({"type": "enemy_fire", "kind": int(ev.kind), "mode": "shell", "from": ev.from, "to": ev.to})
		return
	var rail_xy := Vector2(station.rail.x, station.rail.y)
	if Vector2(ev.to.x, ev.to.y).distance_to(rail_xy) > PLBalance.BEAM_RADIUS:
		events.append({"type": "enemy_fire", "kind": int(ev.kind), "mode": "beam", "from": ev.from, "to": ev.to, "hit": false})
		return
	var r := station.take_damage(float(ev.damage), "beam")
	events.append({"type": "enemy_fire", "kind": int(ev.kind), "mode": "beam", "from": ev.from, "to": ev.to, "hit": not r.blocked})
	events.append({"type": "player_hit", "kind": "beam", "damage": float(ev.damage),
		"applied_hull": r.applied_hull, "applied_shield": r.applied_shield, "blocked": r.blocked, "pos": station.rail_point()})


func _run_projectiles(sim_dt: float, events: Array) -> void:
	for ev in projectiles.step(sim_dt, enemies, station):
		if ev.type == "hit":
			hits += 1
		events.append(ev)


func _process_kills(events: Array) -> void:
	for e: Enemy in enemies:
		if not e.alive or e.hp > 0.0:
			continue
		e.alive = false
		e.dead_timer = PLBalance.DEATH_TIME
		kills += 1
		if time - _last_kill_time <= PLBalance.COMBO_WINDOW:
			combo += 1
		else:
			combo = 1
		_last_kill_time = time
		var mult := PLScoring.combo_mult(combo)
		if mult > combo_mult:
			events.append({"type": "combo", "mult": mult, "chain": combo})
		combo_mult = mult
		var snap := e.first_seen_age >= 0.0 and e.age - e.first_seen_age <= PLBalance.SNAP_WINDOW
		var weak := e.last_crit
		var pts := PLScoring.kill_points(e.points, combo_mult, weak, snap)
		score += pts
		events.append({"type": "kill", "enemy_id": e.id, "kind": e.kind, "points": pts,
			"weak": weak, "snap": snap, "boss": e.boss, "pos": e.pos})
		if snap:
			snaps += 1
			events.append({"type": "snap", "enemy_id": e.id, "pos": e.pos})
		if weak:
			events.append({"type": "weak_hit", "enemy_id": e.id, "pos": e.pos})


func _cleanup(sim_dt: float) -> void:
	var i := enemies.size() - 1
	while i >= 0:
		var e: Enemy = enemies[i]
		if not e.alive:
			e.dead_timer -= sim_dt
			if e.dead_timer <= 0.0:
				enemies.remove_at(i)
		i -= 1


func _check_end(events: Array) -> void:
	if station.hull <= 0.0:
		finished = true
		won = false
		events.append({"type": "game_over", "score": score})
		return
	if _next_item >= schedule.size() and alive_count() == 0:
		finished = true
		won = true
		clean = station.damage_taken_sector <= 0.0
		var bonus := PLScoring.sector_bonus(sector, clean)
		score += bonus
		events.append({"type": "sector_clear", "bonus": bonus, "clean": clean})
