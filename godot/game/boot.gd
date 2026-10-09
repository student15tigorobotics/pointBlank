class_name Boot
extends Node3D
## App shell: world and XR setup, the per-frame loop, and the flow between hub, story, battle and results.
## Port of Game/Boot.cs (main scene script, scenes/main.tscn).
## Run with --smoke for a headless self-test. Smoke never reads or writes the save file.
## Run with --desktop to force the desktop preview.

const STOP_ABORTED: int = 3                 # benchmark stop code: aborted by the menu
const BATTLE_CAP_MIN: int = 800
const SMOKE_SIM_DT: float = 1.0 / 30.0
const SMOKE_BENCH_DT: float = 1.0 / 120.0   # 8.3 ms, inside the 90 Hz budget, so the ramp is not cut short
const SMOKE_BENCH_TICKS: int = 30 * 120
const SMOKE_BATTLE_TICKS: int = 30 * 900

## Shared with hub.gd and dialogue.gd. They read and write these fields directly.
var profile: Profile = null
var controls: Controls = Controls.new()
var code_entry: String = ""
var reset_armed: bool = false
var last_benchmark_aborted: bool = false
var quality: Quality = Quality.new()

var smoke_mode: bool = false
var load_status: String = "missing"
var backup_path: String = ""

var env: Environment = null
var content: Node3D = null
var voice: Voice = null
var hub: Hub = null
var dialogue: Dialogue = null
var view: BattleView = null
var battle: BattleController = null
var xr_iface: OpenXRInterface = null
var xr_cam: XRCamera3D = null
var desk_cam: Camera3D = null
var stage_index: int = -1
var state: String = ""

var _xr_on: bool = false
var _passthrough_on: bool = false
var _benchmark_running: bool = false
var _save_blocked: bool = false
var _outro_chapter: int = -1
var _startup_message: String = ""
var _themes: Array = []
var _stages: Array = []
var _smoke_failures: int = 0
var _smoke_played: bool = false


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	smoke_mode = args.has("--smoke")
	var desktop: bool = smoke_mode or args.has("--desktop")
	_themes = StageCatalog.themes()
	_stages = StageCatalog.all()

	if smoke_mode:
		profile = Profile.new()
	else:
		var loaded: Dictionary = SaveStore.load_profile()
		profile = loaded["profile"]
		load_status = String(loaded["status"])
		backup_path = String(loaded["backup"])
		if load_status == "corrupt":
			_save_blocked = backup_path == ""
			if backup_path != "":
				_startup_message = "Save file was unreadable. Backup kept at " + backup_path.get_file()
			else:
				_startup_message = "Save file was unreadable and could not be backed up. Saving is paused."

	_build_world(desktop)
	quality.set_tier(profile.quality)
	voice = Voice.new()
	add_child(voice)
	content = Node3D.new()
	add_child(content)
	_apply_theme(_themes[0])

	if smoke_mode:
		_run_smoke()
		return
	if not profile.prologue_seen:
		_play_prologue()
	else:
		show_hub("stages", _startup_message)


func _build_world(desktop: bool) -> void:
	var world_env: WorldEnvironment = WorldEnvironment.new()
	env = Environment.new()
	world_env.environment = env
	add_child(world_env)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_energy = 0.9
	sun.rotation = Vector3(-0.9, 0.3, 0.0)
	add_child(sun)

	desk_cam = Camera3D.new()
	desk_cam.position = Vector3(0.0, 1.5, 0.0)
	desk_cam.fov = 75.0
	add_child(desk_cam)

	if not desktop:
		xr_iface = XRServer.find_interface("OpenXR") as OpenXRInterface
		if xr_iface != null and xr_iface.initialize():
			XRServer.primary_interface = xr_iface
			get_viewport().use_xr = true
			_xr_on = true

	var origin: XROrigin3D = XROrigin3D.new()
	add_child(origin)
	xr_cam = XRCamera3D.new()
	origin.add_child(xr_cam)
	var left: XRController3D = XRController3D.new()
	left.tracker = "left_hand"
	var right: XRController3D = XRController3D.new()
	right.tracker = "right_hand"
	origin.add_child(left)
	origin.add_child(right)

	controls.xr = _xr_on
	controls.left = left
	controls.right = right
	controls.desk = desk_cam
	xr_cam.current = _xr_on
	desk_cam.current = not _xr_on


func _apply_theme(t: Dictionary) -> void:
	var fog_color: Color = Meshes.hex_color(int(t["fog"]))
	env.background_mode = Environment.BG_CLEAR_COLOR if _passthrough_on else Environment.BG_COLOR
	env.background_color = fog_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Meshes.hex_color(int(t["enemy"][0]))
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_density = 0.015
	env.glow_enabled = profile.quality > 0
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05


## Applies the saved graphics tier to the governor and the glow setting. Called from the options page.
func apply_quality() -> void:
	quality.set_tier(profile.quality)
	env.glow_enabled = profile.quality > 0


func _process(delta: float) -> void:
	if smoke_mode:
		return
	var dt: float = minf(delta, 0.1)
	controls.poll(get_viewport())
	quality.tick(dt, xr_iface if _xr_on else null, view.renderer if view != null else null)

	var ui_over: bool = Ui.update(controls.ui_pointers(), controls.ui_presses())
	if state == "dialogue":
		if dialogue != null:
			dialogue.tick(dt, controls.advance)
	elif state == "battle":
		_tick_battle(dt, ui_over)


# ---- Services used by hub.gd and dialogue.gd -----------------------------------------------

## Writes the profile to user://profile.json. Save points: prologue end, battle start, battle end, outro end,
## purchases, redeem, dialogue choices and options changes. Does nothing in smoke mode or while a corrupt save
## could not be backed up.
func save() -> void:
	if smoke_mode or _save_blocked:
		return
	if not SaveStore.save_profile(profile):
		push_warning("Profile save failed")


func xr_active() -> bool:
	return _xr_on


func voice_available() -> bool:
	return voice != null and voice.available()


func passthrough_on() -> bool:
	return _passthrough_on


## Switches the HTC passthrough layer on or off. Returns false when it cannot be applied (no XR, or no alpha blend).
func toggle_passthrough() -> bool:
	if not _xr_on:
		return false
	var want: bool = not _passthrough_on
	if not VrPassthrough.set_enabled(xr_iface, get_viewport(), env, want):
		return false
	_passthrough_on = want
	return true


# ---- Flow -----------------------------------------------------------------------------------

func _clear_content() -> void:
	Ui.reset()
	battle = null
	dialogue = null
	view = null
	hub = null
	for child in content.get_children():
		child.queue_free()


func show_hub(tab: String, message: String) -> void:
	_clear_content()
	state = "hub"
	_apply_theme(_themes[0])
	hub = Hub.new(self, tab, message)
	content.add_child(hub)


func _play_prologue() -> void:
	_clear_content()
	state = "dialogue"
	dialogue = Dialogue.new(voice, profile, Callable(self, "save"))
	content.add_child(dialogue)
	dialogue.play(Story.prologue(), Callable(self, "_on_prologue_done"))


func _on_prologue_done() -> void:
	profile.prologue_seen = true
	save()
	show_hub("stages", "Welcome, Commander.")


func start_stage(i: int) -> void:
	if not profile.can_play_stage(i):
		show_hub("stages", "Clear the previous chapter first")
		return
	stage_index = i
	_clear_content()
	var stage: Dictionary = _stages[i]
	_apply_theme(stage["theme"])
	view = BattleView.new(stage)
	content.add_child(view)
	state = "dialogue"
	dialogue = Dialogue.new(voice, profile, Callable(self, "save"))
	content.add_child(dialogue)
	dialogue.play(Story.intro(i), Callable(self, "_begin_battle"))


func _begin_battle() -> void:
	var mods: BattleModifiers = profile.consume_battle_modifiers()
	save()
	_apply_battle_cap()
	battle = BattleController.new(view, profile, mods, false, quality)
	if dialogue != null:
		dialogue.queue_free()
		dialogue = null
	state = "battle"


## Battle spawn cap: the on-device benchmark result when there is one, otherwise the saved tier default.
func _apply_battle_cap() -> void:
	quality.set_tier(profile.quality)
	quality.enabled = true
	if profile.benchmark_max > 0:
		quality.spawn_cap = clampi(profile.benchmark_max, BATTLE_CAP_MIN, Balance.MAX_ENEMIES)


func start_benchmark() -> void:
	_clear_content()
	stage_index = -1
	_apply_theme(_themes[0])
	view = BattleView.new(_stages[0])
	content.add_child(view)
	var mods: BattleModifiers = BattleModifiers.defaults()
	mods.core_max_hp = 1000000
	quality.set_tier(profile.quality)
	quality.enabled = false
	_benchmark_running = true
	battle = BattleController.new(view, profile, mods, true, quality)
	state = "battle"


func _tick_battle(dt: float, ui_over: bool) -> void:
	if battle == null:
		return
	var cam: Node3D = xr_cam if _xr_on else desk_cam
	var eye: Vector3 = cam.global_position
	var forward: Vector3 = -cam.global_transform.basis.z
	battle.tick(dt, controls, ui_over, eye, forward)
	if battle.outcome != BattleController.Outcome.RUNNING:
		_end_battle(battle.outcome)


func _end_battle(outcome: int) -> void:
	var b: BattleController = battle
	battle = null
	if _benchmark_running:
		_benchmark_running = false
		quality.enabled = true
		_finish_benchmark(b, outcome)
		return

	var cleared: bool = outcome == BattleController.Outcome.CLEARED
	var eco: BattleEconomy = b.eco
	var stars: int = BattleEconomy.stars(eco.core_fraction(), cleared)
	var score: int = Scoring.compute(eco.kills, eco.overkill_credits, stars, eco.early_calls)
	var entry: Dictionary = {
		"name": Leaderboard.callsign(profile.callsign_seed),
		"score": score,
		"stage": stage_index + 1,
		"date": Time.get_date_string_from_system(),
	}
	profile.callsign_seed += 1
	var rank: int = Leaderboard.submit(profile.board, entry)
	var record: Dictionary = profile.record_stage(stage_index, stars, eco.earned_total)
	var payout: int = int(record["payout"])
	var revealed: Dictionary = record["revealed"]
	save()

	_clear_content()
	state = "result"
	_show_result(outcome, cleared, stars, score, rank, payout, revealed, eco)


## Benchmark end: an aborted run (stop code 3, or a retreat) is shown as ABORTED and not stored.
func _finish_benchmark(b: BattleController, outcome: int) -> void:
	var r: Dictionary = b.benchmark_result
	var stop_code: int = int(r.get("stop", -1))
	if r.is_empty() or stop_code == STOP_ABORTED or outcome == BattleController.Outcome.RETREATED:
		last_benchmark_aborted = true
		show_hub("options", "Benchmark aborted. Result not stored.")
		return
	profile.benchmark_max = int(r.get("alive", 0))
	profile.benchmark_visible = int(r.get("visible", 0))
	profile.benchmark_tier = int(r.get("tier", profile.quality))
	last_benchmark_aborted = false
	save()
	show_hub("options", "Benchmark: %d visible enemies" % profile.benchmark_visible)


func _show_result(outcome: int, cleared: bool, stars: int, score: int, rank: int, payout: int,
		revealed: Dictionary, eco: BattleEconomy) -> void:
	var root: Node3D = Node3D.new()
	content.add_child(root)
	var c: Vector3 = Vector3(0.0, 1.5, -1.7)
	Ui.quad(root, c, Vector2(1.9, 1.4), Ui.PANEL)
	var title: String = "CHAPTER CLEARED" if cleared else ("RETREAT" if outcome == BattleController.Outcome.RETREATED else "CORE LOST")
	Ui.label(root, title, c + Vector3(0.0, 0.55, 0.03), 44, Ui.ACCENT if cleared else Ui.WARN)
	Ui.label(root, "STARS  %d / 3     BANK  +%d" % [stars, payout], c + Vector3(0.0, 0.36, 0.03), 30, Ui.GOLD)
	var rank_text: String = ("     RANK #%d" % (rank + 1)) if rank >= 0 else ""
	Ui.label(root, "SCORE  %d%s" % [score, rank_text], c + Vector3(0.0, 0.2, 0.03), 30, Color.WHITE)
	Ui.label(root, "KILLS %d   OVERKILL %d CR   EARLY CALLS %d" % [eco.kills, eco.overkill_credits, eco.early_calls],
		c + Vector3(0.0, 0.04, 0.03), 24, Ui.DIM)
	if not revealed.is_empty():
		Ui.label(root, "CODE REVEALED: %s   (enter it in CODES)" % String(revealed["code"]),
			c + Vector3(0.0, -0.14, 0.03), 24, Ui.ACCENT)
	Ui.button(root, "CONTINUE", c + Vector3(0.0, -0.48, 0.04), Vector2(0.8, 0.16), Ui.ACCENT,
		Callable(self, "_on_result_continue").bind(cleared), 30)


func _on_result_continue(cleared: bool) -> void:
	if cleared:
		_play_outro()
	else:
		show_hub("stages", "Chapter failed. Upgrade in SHOP and try again.")


func _play_outro() -> void:
	_clear_content()
	_outro_chapter = stage_index
	_apply_theme(_stages[_outro_chapter]["theme"])
	state = "dialogue"
	dialogue = Dialogue.new(voice, profile, Callable(self, "save"))
	content.add_child(dialogue)
	dialogue.play(Story.outro(_outro_chapter), Callable(self, "_on_outro_done"))


func _on_outro_done() -> void:
	save()
	var finale: bool = _outro_chapter == StageCatalog.count() - 1
	show_hub("shop", "The Last Frequency is over. Thank you for playing." if finale
		else "Chapter complete. Upgrades are open between chapters.")


# ---- Headless self-test ---------------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_smoke_failures += 1


func _on_smoke_dialogue_done() -> void:
	_smoke_played = true


func _run_smoke() -> void:
	_smoke_failures = 0

	for tab in ["stages", "shop", "board", "codes", "options"]:
		show_hub(tab, "smoke")
		_check(hub != null and hub.get_child_count() > 0, "hub builds tab " + tab)

	var first: Profile = SaveStore.from_json(SaveStore.to_json(profile))
	profile.bank = 1234
	var copy: Profile = SaveStore.from_json(SaveStore.to_json(profile))
	_check(copy.bank == 1234 and copy.upgrade_levels.size() == UpgradeCatalog.count() and first.bank == 0,
		"profile JSON round-trips")

	_clear_content()
	state = "dialogue"
	_smoke_played = false
	dialogue = Dialogue.new(voice, profile, Callable(self, "save"))
	content.add_child(dialogue)
	dialogue.play(Story.intro(3), Callable(self, "_on_smoke_dialogue_done"))
	var n: int = 0
	while n < 600 and not _smoke_played:
		dialogue.tick(0.1, n % 15 == 14)
		n += 1
	_check(_smoke_played, "dialogue plays every line and calls back")

	# Scripted battle: sweep the aim across the table, place and upgrade towers, call waves early.
	for u in UnlockCatalog.all():
		var key: String = u["key"]
		if not profile.unlocks.has(key):
			profile.unlocks.append(key)
	_clear_content()
	var stage: Dictionary = _stages[0]
	_apply_theme(stage["theme"])
	view = BattleView.new(stage)
	content.add_child(view)
	var mods: BattleModifiers = profile.consume_battle_modifiers()
	mods.core_max_hp = 300
	battle = BattleController.new(view, profile, mods, false, quality)
	state = "battle"

	var ticks: int = 0
	var max_visible: int = 0
	while battle.outcome == BattleController.Outcome.RUNNING and ticks < SMOKE_BATTLE_TICKS:
		ticks += 1
		var t: float = ticks * SMOKE_SIM_DT
		var target: Vector3 = BattleView.TABLE_CENTER + Vector3(0.9 * sin(t * 0.5), 0.0, 0.9 * cos(t * 0.37))
		var origin: Vector3 = target + Vector3(0.0, 1.2, 0.6)
		var dir: Vector3 = (target - origin).normalized()
		controls.mouse_ptr.origin = origin
		controls.mouse_ptr.dir = dir
		controls.mouse_ptr.valid = true
		controls.fire = true
		controls.call_wave = ticks % 240 == 1
		controls.place = ticks % 20 == 0
		controls.upgrade = ticks % 150 == 0
		controls.sell = false
		battle.tick(SMOKE_SIM_DT, controls, false, origin, dir)
		max_visible = maxi(max_visible, view.renderer.visible_total())
	controls.place = false
	controls.upgrade = false
	controls.call_wave = false
	controls.fire = false
	var outcome_name: String = BattleController.Outcome.keys()[battle.outcome]
	print("     outcome %s after %.0f s sim, kills %d, towers %d, waves cleared %d, max visible %d" % [
		outcome_name, ticks * SMOKE_SIM_DT, battle.eco.kills, battle.towers.towers.size(),
		battle.director.wave_index, max_visible])
	_check(battle.outcome == BattleController.Outcome.CLEARED or battle.outcome == BattleController.Outcome.FAILED,
		"scripted battle reaches an outcome")
	_check(battle.eco.kills > 100, "battle produces kills")
	_check(max_visible > 0, "renderer draws enemies")

	# Benchmark path: ramp until the cap, then report.
	start_benchmark()
	battle.tick(SMOKE_BENCH_DT, controls, false, Vector3.ZERO, Vector3.FORWARD)
	var bench: int = 0
	while battle.outcome == BattleController.Outcome.RUNNING and bench < SMOKE_BENCH_TICKS:
		bench += 1
		battle.tick(SMOKE_BENCH_DT, controls, false, Vector3(0.0, 1.5, 0.5), Vector3.FORWARD)
	var result: Dictionary = battle.benchmark_result
	var stop_code: int = int(result.get("stop", -1))
	_check(battle.outcome == BattleController.Outcome.BENCHMARK_DONE and int(result.get("visible", 0)) > 0
		and int(result.get("alive", 0)) >= 400 and stop_code >= 0 and stop_code <= STOP_ABORTED,
		"benchmark ramps and reports")
	print("     benchmark visible %d over %.0f s, alive %d, renderer visible %d, stop %d, outcome %s" % [
		int(result.get("visible", 0)), bench * SMOKE_BENCH_DT, int(result.get("alive", 0)),
		view.renderer.visible_total(), stop_code, BattleController.Outcome.keys()[battle.outcome]])

	print("SMOKE PASSED" if _smoke_failures == 0 else "SMOKE FAILED: %d" % _smoke_failures)
	get_tree().quit(0 if _smoke_failures == 0 else 1)
