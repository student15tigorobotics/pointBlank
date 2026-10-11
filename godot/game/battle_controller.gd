# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name BattleController
extends RefCounted
## Runs one chapter, or the swarm benchmark, on top of a BattleView. Every rule comes from the engine-free core;
## this class translates controller intents into core calls and core events into visuals.
## Port of Game/BattleController.cs with the addendum changes:
## - "MAX LEVEL" at tower level 3 (NO CREDITS otherwise),
## - director.update gets the free-slot room (quality.spawn_cap - alive),
## - per-frame benchmark: last_good, PBBENCH print lines, stop codes, tier applied at start.

enum Outcome { RUNNING, CLEARED, FAILED, RETREATED, BENCHMARK_DONE }

## Benchmark stop codes, as printed in the PBBENCH,RESULT line.
const STOP_OVER_BUDGET: int = 0
const STOP_CAP: int = 1
const STOP_TIME: int = 2
const STOP_ABORTED: int = 3

const BUDGET_MS: float = 1000.0 / 90.0       # 90 Hz frame budget
const BENCH_MIN_ALIVE: int = 400
const BENCH_OVER_FRAMES: int = 30
const BENCH_SPAWN_INTERVAL: float = 0.25
const BENCH_SPAWN_BATCH: int = 120
const BENCH_TIME_LIMIT: float = 90.0
const BENCH_PRINT_INTERVAL: float = 2.0
const HUD_INTERVAL: float = 0.2
const SHOT_DISPLAY_CAP: int = 60
const BUILD_PICK_RADIUS: float = 0.12
const MUZZLE_REACH: float = 2.0          # metres a miss tracer travels down the aim line
const TEXT_HEIGHT: float = 0.25
const CLEAR_TEXT_HEIGHT: float = 0.3
const BENCH_SEED: int = 42

var view: BattleView
var eco: BattleEconomy
var swarm: Swarm
var director: WaveDirector
var towers: TowerField
var weapons: WeaponSystem
var weapons_left: WeaponSystem       # independent cooldown for the dual-wield left hand
var grid: SpatialGrid
var projectiles: Projectiles
var allies: AllySquad
var left_weapon_mode: bool = false   # left hand: false = builder, true = weapon (left X toggles)
var benchmark: bool = false
var outcome: int = Outcome.RUNNING
var benchmark_result: Dictionary = {}     # {alive, visible, tier, stop} once the benchmark has ended
var samples: Array = []                   # [elapsed, alive, visible, avg_ms] every 2 s of benchmark, for a CSV

var _quality: Quality
var _tier: int = 1
var _weapon_kinds: PackedInt32Array = PackedInt32Array()
var _tower_kinds: PackedInt32Array = PackedInt32Array()
var _tower_range: PackedFloat32Array = PackedFloat32Array()   # indexed by Balance.TowerKind
var _weapon_idx: int = 0
var _tower_idx: int = 0
var _spawns: Array = []
var _shots: Array = []
var _occupied: Dictionary = {}            # TowerField.pad_key values of placed towers
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _hp_scale: float = 1.0
var _call_requested: bool = false
var _retreat_requested: bool = false
var _hud_timer: float = 0.0
var _bench_spawn_timer: float = 0.0
var _bench_elapsed: float = 0.0
var _over_streak: int = 0
var _last_alive: int = 0                  # last_good: alive at the last in-budget frame
var _last_visible: int = 0                # last_good: visible at the last in-budget frame
var _win_time: float = 0.0
var _win_ms: float = 0.0
var _win_frames: int = 0
var _impacts: Array = []                  # flat [x, y, z, style, killed] runs from Projectiles.tick
var _prev_phase: int = WaveDirector.Phase.PREP
var _prev_core_hp: int = -1
var _muzzle_ptr: Array = [Pointer.new(), Pointer.new()]   # fire-origin scratch per hand
var _charge: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])  # boulder wind-up per hand
var _was_fire: Array = [false, false]
var _saber_sfx_cd: float = 0.0

const MUZZLE_LEN: float = 0.21            # gun length: bolts leave from the muzzle tip
const CHARGE_MAX: float = 1.2             # seconds to a full boulder wind-up


func _init(view_ref: BattleView, profile_ref: Profile, mods: BattleModifiers, bench: bool, quality_ref: Quality) -> void:
	view = view_ref
	benchmark = bench
	_quality = quality_ref
	_tier = profile_ref.quality
	eco = BattleEconomy.new(mods)
	swarm = Swarm.new(view.path, Balance.MAX_ENEMIES)
	director = WaveDirector.new(view.stage)
	towers = TowerField.new()
	weapons = WeaponSystem.new()
	weapons_left = WeaponSystem.new()
	grid = SpatialGrid.new()
	projectiles = Projectiles.new()
	allies = AllySquad.new(view.path)
	towers.damage_mult = mods.tower_damage_mult
	weapons.damage_mult = mods.weapon_damage_mult
	weapons.cooldown_mult = mods.weapon_cooldown_mult
	weapons_left.damage_mult = mods.weapon_damage_mult
	weapons_left.cooldown_mult = mods.weapon_cooldown_mult
	_hp_scale = float(view.stage["hp_scale"])
	_rng.seed = BENCH_SEED

	# The benchmark fires only the blaster and builds nothing.
	for k in Balance.WEAPON_LAST + 1:
		var owned: bool = (k == Balance.WeaponKind.BLASTER) if bench else profile_ref.has_weapon(k)
		if owned:
			_weapon_kinds.append(k)
	for k in Balance.TOWER_LAST + 1:
		if not bench and profile_ref.has_tower(k):
			_tower_kinds.append(k)
		_tower_range.append(float(Balance.tower(k)["range"]))

	# The benchmark starts at the saved graphics tier. Battles get their spawn cap from Boot.
	if bench:
		_quality.set_tier(_tier)
		view.renderer.mesh_budget = _quality.mesh_budget

	view.call_button.callback = Callable(self, "_on_call_pressed")
	view.retreat_button.callback = Callable(self, "_on_retreat_pressed")
	view.hud_tower.text = ""


func weapon_kind() -> int:
	if _weapon_kinds.size() == 0:
		return Balance.WeaponKind.BLASTER
	return _weapon_kinds[_weapon_idx]


func tower_choice() -> int:
	if _tower_kinds.size() == 0:
		return Balance.TowerKind.TURRET
	return _tower_kinds[_tower_idx]


## One frame. eye and forward are world-space head pose values.
func tick(dt: float, controls: Controls, ui_over: bool, eye: Vector3, forward: Vector3) -> void:
	if outcome != Outcome.RUNNING:
		return
	var overkill_before: int = eco.overkill_credits
	_shots.clear()

	if _retreat_requested or controls.menu:
		if benchmark:
			_finish_benchmark(STOP_ABORTED)
		else:
			outcome = Outcome.RETREATED
		return

	if not benchmark and (_call_requested or controls.call_wave):
		var bonus: int = director.call_early(eco.early_bonus_mult, eco)
		if bonus > 0:
			view.float_text("EARLY CALL +" + str(bonus), Vector3(0.0, CLEAR_TEXT_HEIGHT, 0.0), Ui.GOLD)
			Audio.play("early_call")
	_call_requested = false
	_retreat_requested = false

	if benchmark:
		_benchmark_ramp(dt)
	else:
		_spawns.clear()
		director.update(dt, swarm.alive_count, _spawns, _quality.spawn_cap - swarm.alive_count)
		for k in _spawns:
			if swarm.alive_count >= _quality.spawn_cap:
				break
			swarm.spawn(k, _hp_scale, _rng.randf())
		if director.just_cleared:
			var clear_bonus: int = BattleEconomy.wave_clear_bonus(director.cleared_wave_index)
			eco.earn(clear_bonus)
			view.float_text("WAVE CLEAR +" + str(clear_bonus), Vector3(0.0, CLEAR_TEXT_HEIGHT, 0.0), Ui.ACCENT)
			Audio.play("wave.clear")
		if director.phase == WaveDirector.Phase.ACTIVE and _prev_phase == WaveDirector.Phase.PREP:
			Audio.play("wave.start")
		_prev_phase = director.phase

	# Enemy body collision runs in battles; the benchmark skips it to keep measuring the renderer.
	swarm.step(dt, eco, null if benchmark else grid)
	grid.rebuild(swarm)
	towers.tick(dt, swarm, eco, _shots, grid)
	weapons.tick(dt)
	weapons_left.tick(dt)

	if controls.toggle_left and not benchmark:
		left_weapon_mode = not left_weapon_mode
		view.float_text("LEFT: WEAPON" if left_weapon_mode else "LEFT: BUILDER", Vector3(0.0, CLEAR_TEXT_HEIGHT, 0.0), Ui.ACCENT)
		Audio.play("ui.click")

	# Weapon hands. The right hand always fires; the left fires too when toggled to weapon mode.
	_fire_hand(0, controls.aim_pointer(), controls.fire, weapons, dt, ui_over)
	if left_weapon_mode and not benchmark:
		_fire_hand(1, controls.place_pointer(), controls.fire_left, weapons_left, dt, ui_over)

	# Lemming allies brawl the swarm; the view animates them.
	if not benchmark:
		allies.tick(dt, swarm, grid, eco)
		view.draw_allies(allies, dt)

	# Travelling bolts: advance, land hits, and show their impacts.
	_impacts.clear()
	projectiles.tick(dt, swarm, grid, eco, _impacts)
	var imp: int = 0
	while imp < _impacts.size():
		var at := Vector3(_impacts[imp], _impacts[imp + 1], _impacts[imp + 2])
		view.shoot(ShotStyle.make(at, at, 0.03, ShotStyle.Style.BURST))
		imp += 5
	view.draw_bolts(projectiles)

	# Death explosions: light, fire and sound for every enemy that went down this frame.
	if not benchmark and swarm.death_count > 0:
		for di in swarm.death_count:
			view.explosion(Vector3(swarm.death_x[di], swarm.death_y[di], swarm.death_z[di]))
		Audio.play("explosion", -4.0, 0.18)
	swarm.clear_deaths()

	if controls.weapon_step != 0 and _weapon_kinds.size() > 0:
		_weapon_idx = posmod(_weapon_idx + controls.weapon_step, _weapon_kinds.size())
	if controls.tower_step != 0 and _tower_kinds.size() > 0:
		_tower_idx = posmod(_tower_idx + controls.tower_step, _tower_kinds.size())

	_handle_build(controls, ui_over)

	var aim: Pointer = controls.aim_pointer()
	if controls.upgrade and aim.valid and not ui_over:
		var local_aim: Array = view.local_ray(aim)
		var tp: Array = view.table_point(local_aim[0], local_aim[1])
		if tp[0]:
			var xz: Vector2 = tp[1]
			var t: TowerInstance = towers.pick(xz.x, xz.y, BUILD_PICK_RADIUS)
			if t != null:
				var ok: bool = towers.upgrade(t, eco)
				var msg: String
				var col: Color
				if ok:
					msg = "LEVEL " + str(t.level)
					col = Ui.GOLD
					Audio.play("tower.upgrade")
				elif t.level >= Balance.MAX_TOWER_LEVEL:
					msg = "MAX LEVEL"
					col = Ui.WARN
				else:
					msg = "NO CREDITS"
					col = Ui.WARN
				view.float_text(msg, Vector3(xz.x, TEXT_HEIGHT, xz.y), col)

	# Core damage feedback: leaks this frame dropped the core.
	if not benchmark:
		if _prev_core_hp >= 0 and eco.core_hp < _prev_core_hp:
			Audio.play("core.damage", 0.0, 0.05)
		_prev_core_hp = eco.core_hp

	var shown: int = 0
	for s in _shots:
		if shown >= SHOT_DISPLAY_CAP:
			break
		shown += 1
		view.shoot(s)
	if eco.overkill_credits > overkill_before and _shots.size() > 0:
		var last: Dictionary = _shots[_shots.size() - 1]
		var last_to: Vector3 = last["to"]
		view.float_text("OVERKILL +" + str(eco.overkill_credits - overkill_before), Vector3(last_to.x, last_to.y + 0.05, last_to.z), Ui.GOLD)
		Audio.play("overkill", -6.0)

	view.sync_towers(towers.towers)
	view.tick_fx(dt)
	var inv: Transform3D = view.global_transform.affine_inverse()
	view.renderer.draw(swarm, inv * eye, inv.basis * forward)

	_hud_timer -= dt
	if _hud_timer <= 0.0:
		_hud_timer = HUD_INTERVAL
		_update_hud()

	if benchmark:
		_benchmark_frame(dt)
		return
	if eco.core_destroyed():
		outcome = Outcome.FAILED
	elif director.phase == WaveDirector.Phase.FINISHED:
		outcome = Outcome.CLEARED


## One hand's weapon handling for this frame. hand: 0 = right, 1 = left. The fire origin is
## pushed MUZZLE_LEN down the aim ray so bolts leave from the gun's muzzle tip, not the grip.
func _fire_hand(hand: int, ptr: Pointer, held: bool, ws: WeaponSystem, dt: float, ui_over: bool) -> void:
	var kind: int = weapon_kind()
	var was: bool = _was_fire[hand]
	_was_fire[hand] = held and ptr.valid and not ui_over
	if not ptr.valid:
		return
	var mp: Pointer = _muzzle_ptr[hand]
	mp.origin = ptr.origin + ptr.dir * MUZZLE_LEN
	mp.dir = ptr.dir
	mp.valid = true
	var lr: Array = view.local_ray(mp)
	var o: Vector3 = lr[0]
	var d: Vector3 = lr[1]

	if kind == Balance.WeaponKind.SABER:
		if held and not ui_over:
			_saber_slash(o, d, ws, dt)
		return

	if kind == Balance.WeaponKind.SQUAD:
		# Point at the roadway and squeeze: a squad of lemmings drops there and marches
		# against the flow, brawling everything it meets.
		if held and not ui_over and ws.ready():
			var tp: Array = view.table_point(o, d)
			if tp[0]:
				var xz: Vector2 = tp[1]
				var squad_stats: Dictionary = Balance.weapon(kind)
				var made: int = allies.spawn_at(_nearest_path_dist(xz), int(squad_stats["count"]))
				if made > 0:
					ws.cooldown = float(squad_stats["cooldown"]) * ws.cooldown_mult
					view.float_text("LEMMINGS x%d" % made, Vector3(xz.x, TEXT_HEIGHT, xz.y), Ui.ACCENT)
					Audio.play("tower.place", -2.0, 0.1)
		return

	if kind == Balance.WeaponKind.BOULDER:
		var stats: Dictionary = Balance.weapon(kind)
		if held and not ui_over and ws.ready():
			_charge[hand] = minf(_charge[hand] + dt, CHARGE_MAX)
		elif was and not (held and not ui_over) and _charge[hand] > 0.05 and ws.ready():
			# Release: hurl the ball. Speed, arc and roll distance scale with the wind-up.
			var t: float = _charge[hand] / CHARGE_MAX
			var vel: Vector3 = d * lerpf(1.6, 4.4, t)
			vel.y += lerpf(0.5, 1.1, t)
			projectiles.fire_ball(o, vel, float(stats["range"]) * lerpf(0.35, 1.0, t),
				float(stats["damage"]) * ws.damage_mult)
			ws.cooldown = float(stats["cooldown"]) * ws.cooldown_mult
			_charge[hand] = 0.0
			Audio.play("shot.rail", -3.0, 0.1)
		if not held:
			_charge[hand] = 0.0
		return

	if held and not ui_over:
		# ready() tells us the shot will actually discharge this frame (not blocked by cooldown).
		var discharged: bool = ws.ready()
		var before: int = _shots.size()
		var launched: int = ws.try_fire(kind, o, d, swarm, eco, _shots, projectiles)
		if discharged:
			Audio.play(_fire_sound(kind), -2.0, 0.06)
			# Instant weapons that connect with nothing draw nothing, so the trigger felt dead.
			if launched == 0 and _shots.size() == before:
				view.shoot(ShotStyle.make(o, o + d * MUZZLE_REACH, 0.0, ShotStyle.Style.BOLT))


## Along-path distance of the point on the lane nearest to xz (battlefield-local).
func _nearest_path_dist(xz: Vector2) -> float:
	var path: BattlePath = view.path
	var best_d2: float = INF
	var best_dist: float = 0.0
	for s in path.segment_count():
		var ax: float = path.vx[s]
		var az: float = path.vz[s]
		var ex: float = path.vx[s + 1] - ax
		var ez: float = path.vz[s + 1] - az
		var ll: float = ex * ex + ez * ez
		if ll < 1e-8:
			continue
		var t: float = clampf(((xz.x - ax) * ex + (xz.y - az) * ez) / ll, 0.0, 1.0)
		var dx: float = xz.x - (ax + ex * t)
		var dz: float = xz.y - (az + ez * t)
		var d2: float = dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best_dist = path.cum[s] + sqrt(ll) * t
	return best_dist


## Continuous plasma-saber damage: enemies near the blade line melt at damage-per-second.
func _saber_slash(o: Vector3, d: Vector3, ws: WeaponSystem, dt: float) -> void:
	var stats: Dictionary = Balance.weapon(Balance.WeaponKind.SABER)
	var blade: float = float(stats["range"])
	var dps: float = float(stats["damage"]) * ws.damage_mult
	var reach: float = float(stats["radius"]) + 0.05
	_saber_sfx_cd -= dt
	var touched: bool = false
	for s in [0.2, 0.5, 0.8]:
		var p: Vector3 = o + d * (blade * float(s))
		_impacts_scratch.clear()
		_impacts_scratch = grid.collect(p.x, p.z, reach, _impacts_scratch)
		for k in _impacts_scratch.size():
			var e: int = _impacts_scratch[k]
			var ey: float = swarm.y[e] - p.y
			if absf(ey) > 0.12:
				continue
			Combat.hit(swarm, e, dps * dt, eco)
			touched = true
	if touched and _saber_sfx_cd <= 0.0:
		_saber_sfx_cd = 0.18
		Audio.play("shot.arc", -8.0, 0.2)


var _impacts_scratch: PackedInt32Array = PackedInt32Array()


## SFX key for a weapon discharge. Nova shares the explosion sample; it is a burst weapon.
static func _fire_sound(kind: int) -> String:
	if kind == Balance.WeaponKind.SCATTER:
		return "shot.scatter"
	if kind == Balance.WeaponKind.RAIL:
		return "shot.rail"
	if kind == Balance.WeaponKind.ARC:
		return "shot.arc"
	if kind == Balance.WeaponKind.NOVA:
		return "explosion"
	return "shot.blaster"


func _on_call_pressed() -> void:
	_call_requested = true


func _on_retreat_pressed() -> void:
	_retreat_requested = true


func _handle_build(controls: Controls, ui_over: bool) -> void:
	# A left hand in weapon mode fires instead of building; every build affordance sleeps.
	if benchmark or _tower_kinds.size() == 0 or left_weapon_mode:
		view.set_hover_pad(-1)
		view.hide_ring()
		view.hide_tower_ghost()
		return

	var place_p: Pointer = controls.place_pointer()
	var local_place: Array = view.local_ray(place_p)
	var po: Vector3 = local_place[0]
	var pd: Vector3 = local_place[1]
	var pad: int = -1
	var spot: Vector2 = Vector2.ZERO
	if place_p.valid and not ui_over:
		var pu: Array = view.pad_under(po, pd)
		pad = pu[0]
		spot = pu[1]
	view.set_hover_pad(pad)

	if pad >= 0:
		view.show_ring(spot, _tower_range[tower_choice()])
		# A translucent stand-in of the selected tower on the pad, so you see what you are
		# about to build, not just its range (owner ask). Hidden the frame it becomes real.
		if controls.place:
			view.hide_tower_ghost()
		else:
			view.show_tower_ghost(tower_choice(), spot)
		if controls.place and controls.sell:
			_sell_near(spot)
		elif controls.place:
			_place_at(spot)
		return

	view.hide_tower_ghost()
	if controls.place and controls.sell and place_p.valid and not ui_over:
		var tp: Array = view.table_point(po, pd)
		if tp[0]:
			_sell_near(tp[1])
			view.hide_ring()
			return
	view.hide_ring()


func _place_at(spot: Vector2) -> void:
	var kind: int = tower_choice()
	var cost: int = eco.tower_cost(kind)
	if not towers.can_place_at(spot.x, spot.y, view.path, _occupied):
		return
	var t: TowerInstance = towers.place(kind, spot.x, spot.y, cost, eco)
	if t == null:
		view.float_text("NEED " + str(cost) + " CR", Vector3(spot.x, TEXT_HEIGHT, spot.y), Ui.WARN)
		return
	_occupied[TowerField.pad_key(spot.x, spot.y)] = true
	view.float_text("-" + str(cost), Vector3(spot.x, TEXT_HEIGHT, spot.y), Ui.GOLD)
	Audio.play("tower.place")


func _sell_near(at: Vector2) -> void:
	var t: TowerInstance = towers.pick(at.x, at.y, BUILD_PICK_RADIUS)
	if t == null:
		return
	_occupied.erase(TowerField.pad_key(t.x, t.z))
	var refund: int = towers.sell(t, eco)
	view.float_text("+" + str(refund), Vector3(t.x, TEXT_HEIGHT, t.z), Ui.ACCENT)
	Audio.play("tower.sell")


## Benchmark spawn ramp: 120 drones every 0.25 s until the enemy cap is reached.
func _benchmark_ramp(dt: float) -> void:
	_bench_spawn_timer -= dt
	if _bench_spawn_timer <= 0.0:
		_bench_spawn_timer = BENCH_SPAWN_INTERVAL
		var n: int = 0
		while n < BENCH_SPAWN_BATCH and swarm.alive_count < Balance.MAX_ENEMIES:
			swarm.spawn(Balance.EnemyKind.DRONE, 1.0, _rng.randf())
			n += 1


## Per-frame benchmark measurement, run after the renderer has drawn this frame.
func _benchmark_frame(dt: float) -> void:
	var frame_ms: float = dt * 1000.0
	var alive: int = swarm.alive_count
	var vis_count: int = view.renderer.visible_total()
	_bench_elapsed += dt

	if alive >= BENCH_MIN_ALIVE:
		if frame_ms <= BUDGET_MS * 1.1:
			_last_alive = alive
			_last_visible = vis_count
			_over_streak = 0
		else:
			_over_streak += 1

	_win_time += dt
	_win_ms += frame_ms
	_win_frames += 1
	if _win_time >= BENCH_PRINT_INTERVAL:
		var avg_ms: float = _win_ms / float(_win_frames)
		print("PBBENCH,%.1f,%d,%d,%.2f,%d" % [_bench_elapsed, alive, vis_count, avg_ms, _tier])
		samples.append([_bench_elapsed, alive, vis_count, avg_ms])
		_win_time = 0.0
		_win_ms = 0.0
		_win_frames = 0

	if _over_streak >= BENCH_OVER_FRAMES:
		_finish_benchmark(STOP_OVER_BUDGET)
	elif alive >= Balance.MAX_ENEMIES:
		_finish_benchmark(STOP_CAP)
	elif _bench_elapsed > BENCH_TIME_LIMIT:
		_finish_benchmark(STOP_TIME)


## Ends the benchmark with last_good as the result. stop is one of the STOP_ codes.
func _finish_benchmark(stop: int) -> void:
	print("PBBENCH,RESULT,%d,%d,%d,%.2f,%d" % [_last_alive, _last_visible, _tier, BUDGET_MS, stop])
	benchmark_result = {"alive": _last_alive, "visible": _last_visible, "tier": _tier, "stop": stop}
	outcome = Outcome.BENCHMARK_DONE


func _update_hud() -> void:
	view.hud_credits.text = "CREDITS  " + str(eco.credits)
	view.hud_core.text = "CORE  " + str(eco.core_hp) + " / " + str(eco.core_max_hp)
	if benchmark:
		view.hud_wave.text = "BENCHMARK  alive " + str(swarm.alive_count)
		view.hud_tower.text = "visible " + str(view.renderer.visible_total()) + "  (mesh " + str(view.renderer.visible_meshes) + ")"
		view.hud_weapon.text = ""
		view.hud_note.text = "Raise until frames drop, then the count is saved."
		return

	var phase_text: String
	if director.phase == WaveDirector.Phase.PREP:
		phase_text = "NEXT IN " + str(ceili(director.prep_remaining)) + "s"
	else:
		phase_text = "ALIVE " + str(swarm.alive_count)
	view.hud_wave.text = "WAVE " + str(director.wave_index + 1) + " / " + str(director.wave_count()) + "   " + phase_text
	if _tower_kinds.size() > 0:
		var kind: int = tower_choice()
		view.hud_tower.text = "TOWER  " + str(Balance.tower(kind)["name"]) + "  " + str(eco.tower_cost(kind)) + " CR"
	else:
		view.hud_tower.text = "TOWER  none unlocked"
	view.hud_weapon.text = "WEAPON  " + str(Balance.weapon(weapon_kind())["name"])
	view.hud_note.text = ("L-trig FIRE (weapon mode)  L-X: builder  R-B upgrade   |   BOTH grips: move/zoom" if left_weapon_mode
		else "L-trig place  R-trig fire  L-grip sell  L-X: left weapon  R-B upgrade   |   BOTH grips: move/zoom")
