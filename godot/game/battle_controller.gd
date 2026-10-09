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
const TEXT_HEIGHT: float = 0.25
const CLEAR_TEXT_HEIGHT: float = 0.3
const BENCH_SEED: int = 42

var view: BattleView
var eco: BattleEconomy
var swarm: Swarm
var director: WaveDirector
var towers: TowerField
var weapons: WeaponSystem
var grid: SpatialGrid
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
	grid = SpatialGrid.new()
	towers.damage_mult = mods.tower_damage_mult
	weapons.damage_mult = mods.weapon_damage_mult
	weapons.cooldown_mult = mods.weapon_cooldown_mult
	_hp_scale = float(view.stage["hp_scale"])
	_rng.seed = BENCH_SEED

	# The benchmark fires only the blaster and builds nothing.
	for k in Balance.WeaponKind.NOVA + 1:
		var owned: bool = (k == Balance.WeaponKind.BLASTER) if bench else profile_ref.has_weapon(k)
		if owned:
			_weapon_kinds.append(k)
	for k in Balance.TowerKind.SNIPER + 1:
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

	swarm.step(dt, eco)
	grid.rebuild(swarm)
	towers.tick(dt, swarm, eco, _shots, grid)
	weapons.tick(dt)

	var aim: Pointer = controls.aim_pointer()
	var local_aim: Array = view.local_ray(aim)
	var aim_o: Vector3 = local_aim[0]
	var aim_d: Vector3 = local_aim[1]
	if aim.valid and controls.fire and not ui_over:
		weapons.try_fire(weapon_kind(), aim_o, aim_d, swarm, eco, _shots)

	if controls.weapon_step != 0 and _weapon_kinds.size() > 0:
		_weapon_idx = posmod(_weapon_idx + controls.weapon_step, _weapon_kinds.size())
	if controls.tower_step != 0 and _tower_kinds.size() > 0:
		_tower_idx = posmod(_tower_idx + controls.tower_step, _tower_kinds.size())

	_handle_build(controls, ui_over)

	if controls.upgrade and aim.valid and not ui_over:
		var tp: Array = view.table_point(aim_o, aim_d)
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
				elif t.level >= Balance.MAX_TOWER_LEVEL:
					msg = "MAX LEVEL"
					col = Ui.WARN
				else:
					msg = "NO CREDITS"
					col = Ui.WARN
				view.float_text(msg, Vector3(xz.x, TEXT_HEIGHT, xz.y), col)

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


func _on_call_pressed() -> void:
	_call_requested = true


func _on_retreat_pressed() -> void:
	_retreat_requested = true


func _handle_build(controls: Controls, ui_over: bool) -> void:
	if benchmark or _tower_kinds.size() == 0:
		view.set_hover_pad(-1)
		view.hide_ring()
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
		if controls.place and controls.sell:
			_sell_near(spot)
		elif controls.place:
			_place_at(spot)
		return

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


func _sell_near(at: Vector2) -> void:
	var t: TowerInstance = towers.pick(at.x, at.y, BUILD_PICK_RADIUS)
	if t == null:
		return
	_occupied.erase(TowerField.pad_key(t.x, t.z))
	var refund: int = towers.sell(t, eco)
	view.float_text("+" + str(refund), Vector3(t.x, TEXT_HEIGHT, t.z), Ui.ACCENT)


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
	view.hud_note.text = "L-trigger place   R-trigger fire   L-grip sell   R-B upgrade"
