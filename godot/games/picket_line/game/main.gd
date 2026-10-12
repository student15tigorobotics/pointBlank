# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
extends Node3D
## Flow controller. Owns the Run and the live Sim, and wires input, world, HUD, menus, audio and saves together.
## Flow: title -> briefing -> play -> sector result -> upgrades -> briefing ... -> debrief.

enum State { TITLE, BRIEFING, PLAY, PAUSED, UPGRADE, SECTOR_RESULT, DEBRIEF }

## Emitted when the player asks to go back to the game list. The launcher frees this game on receipt.
signal menu_requested

const MISSIONS := [
	"Hold the picket line. Pick off the scout screen before it reaches the hull.",
	"The debris field hides gunships. Break their guns first, then the carrier.",
	"Ion storms scramble the sensors. Bombers come in fast: shoot them early.",
	"Carrier lane. The flagship launches scouts. Strike its core when the plating opens.",
	"Gunships hold at range and fire telegraphed shells. Keep moving, keep firing.",
	"The dreadnought fights in three phases. Each phase launches a drone swarm.",
]

var settings: Dictionary = {}
var scores: Array = []
var run: Run = null
var sim: Sim = null
var state := State.TITLE
var difficulty := PLBalance.Diff.ENSIGN
var world: World
var hud: Hud
var menus: Menus
var input: GameInput
var audio: GameAudio

var _last_scoping := false
var _last_focusing := false
var _boss_on := false
var _bonus := 0
var _current_screen := ""
var _options_from_pause := false


func _ready() -> void:
	settings = Save.load_settings()
	scores = Save.load_scores()
	GameInput.install()

	world = World.new()
	add_child(world)
	world.build(settings)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)
	hud = Hud.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(hud)
	hud.build()
	hud.set_camera(world.camera())

	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	menus = Menus.new()
	menus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(menus)
	menus.build()
	menus.action.connect(_on_action)

	input = GameInput.new()
	add_child(input)
	audio = GameAudio.new()
	add_child(audio)
	audio.build()

	_apply_settings()
	_show_title()


func _process(delta: float) -> void:
	match state:
		State.PLAY:
			_tick_play(delta)
		State.PAUSED:
			world.render(sim, 0.0, settings)
			hud.render(sim, 0.0, _hud_settings())


func _tick_play(dt: float) -> void:
	if Input.is_action_just_pressed("pause"):
		_open_pause()
		return
	var cmd := input.poll(dt, settings)
	var events := sim.step(dt, cmd)
	_react(events)
	world.render(sim, dt, settings)
	hud.render(sim, dt, _hud_settings())
	if sim.finished:
		_finish_sector()


func _react(events: Array) -> void:
	world.handle_events(events)
	hud.handle_events(events)
	audio.handle_events(events)
	for ev in events:
		if ev.type == "sector_clear":
			_bonus = int(ev.bonus)
	if sim.station.scoping != _last_scoping:
		_last_scoping = sim.station.scoping
		audio.play_sfx("scope_in" if _last_scoping else "scope_out", 1.0, 0.5)
	if sim.station.focusing != _last_focusing:
		_last_focusing = sim.station.focusing
		audio.play_sfx("focus_on" if _last_focusing else "focus_off", 1.0, 0.7)
	var boss := _boss_alive()
	if boss != _boss_on:
		_boss_on = boss
		audio.music("boss" if boss else "combat")


func _boss_alive() -> bool:
	for e: Enemy in sim.enemies:
		if e.alive and e.boss:
			return true
	return false


func _finish_sector() -> void:
	run.finish_sector(sim)
	_set_state(State.SECTOR_RESULT)
	_set_mouse(false)
	world.set_battlefield_visible(false)
	audio.music("victory" if sim.won and run.is_victory() else ("calm" if sim.won else "defeat"))
	var info := Sectors.info(sim.sector)
	_current_screen = "sector_clear"
	menus.show_screen("sector_clear", {
		"name": String(info.name),
		"bonus": _bonus,
		"clean": sim.clean,
		"kills": sim.kills,
		"accuracy": sim.accuracy(),
		"score": sim.score,
		"won": sim.won,
	})


func _start_sector() -> void:
	sim = run.start_sector()
	world.set_sector(sim.sector)
	world.clear_battlefield()
	world.set_battlefield_visible(true)
	_last_scoping = false
	_last_focusing = false
	_boss_on = false
	_bonus = 0
	_set_state(State.PLAY)
	menus.hide_all()
	_set_mouse(true)
	input.clear_mouse()
	audio.music("combat")
	hud.banner("SECTOR %d  %s" % [sim.sector + 1, Sectors.info(sim.sector).name], Color(0.35, 0.85, 1.0), 2.5)


func _show_title() -> void:
	_set_state(State.TITLE)
	sim = null
	_set_mouse(false)
	world.set_battlefield_visible(false)
	world.clear_battlefield()
	_current_screen = "title"
	var best := int(scores[0].score) if not scores.is_empty() else 0
	menus.show_screen("title", {"difficulty": String(PLBalance.difficulty(difficulty).name), "best": best})
	audio.music("menu")


func _show_briefing() -> void:
	_set_state(State.BRIEFING)
	_set_mouse(false)
	var info := Sectors.info(run.sector)
	var boss_name := ""
	if int(info.boss) >= 0:
		boss_name = String(PLBalance.ENEMY_DEFS[int(info.boss)].name)
	var owned_names: Array = []
	for id in run.owned:
		owned_names.append(_upgrade_name(String(id)))
	_current_screen = "briefing"
	menus.show_screen("briefing", {
		"sector_index": run.sector,
		"name": String(info.name),
		"waves": int(info.waves),
		"boss": int(info.boss) >= 0,
		"boss_name": boss_name,
		"owned": owned_names,
		"total_score": run.total_score,
		"mission": MISSIONS[clampi(run.sector, 0, MISSIONS.size() - 1)],
	})
	audio.music("calm")


func _show_upgrades() -> void:
	_set_state(State.UPGRADE)
	_set_mouse(false)
	var offers: Array = []
	for id in run.offer_upgrades():
		var card := _upgrade_card(String(id))
		if not card.is_empty():
			offers.append(card)
	_current_screen = "upgrades"
	menus.show_screen("upgrades", {"offers": offers, "sector_name": String(Sectors.info(run.sector).name)})


func _show_debrief() -> void:
	_set_state(State.DEBRIEF)
	_set_mouse(false)
	world.set_battlefield_visible(false)
	var victory := run.is_victory()
	var rank := SaveData.add_highscore(scores, {
		"name": "PILOT-%03d" % (randi() % 1000),
		"score": run.total_score,
		"sector": run.sector + 1,
		"victory": victory,
	})
	Save.save_scores(scores)
	_current_screen = "debrief"
	menus.show_screen("debrief", {
		"victory": victory,
		"total_score": run.total_score,
		"sector_reached": run.sector + 1,
		"rank": rank,
		"history": run.history,
	})
	audio.music("victory" if victory else "defeat")


func _open_pause() -> void:
	_set_state(State.PAUSED)
	_set_mouse(false)
	_current_screen = "pause"
	menus.show_screen("pause", {})
	audio.ui("ui_select")


func _close_pause() -> void:
	_set_state(State.PLAY)
	_set_mouse(true)
	input.clear_mouse()
	menus.hide_all()


func _on_action(id: String, payload: Variant) -> void:
	if id != "setting":
		audio.ui("ui_click")
	match id:
		"start":
			run = Run.new(randi() % 1000000 + 1, difficulty)
			_show_briefing()
		"cycle_difficulty":
			difficulty = (difficulty + 1) % 3
			_show_title()
		"scores":
			_current_screen = "scores"
			menus.show_screen("scores", {"scores": scores, "highlight_rank": -1})
		"options":
			_options_from_pause = state == State.PAUSED
			_current_screen = "options"
			menus.show_screen("options", {"settings": settings})
		"games":
			menu_requested.emit()
		"quit":
			get_tree().quit()
		"begin":
			_start_sector()
		"abort_run":
			run.over = true
			_show_debrief()
		"pick":
			run.choose(String(payload))
			_show_briefing()
		"continue":
			if run.is_over():
				_show_debrief()
			else:
				_show_upgrades()
		"title":
			_show_title()
		"resume":
			_close_pause()
		"setting":
			_set_setting(payload)
		"back":
			if _current_screen == "options" and _options_from_pause:
				_open_pause()
			else:
				_show_title()


func _set_setting(payload: Variant) -> void:
	var entry: Dictionary = payload
	settings[String(entry.key)] = entry.value
	Save.save_settings(settings)
	_apply_settings()


func _apply_settings() -> void:
	audio.set_volumes(float(settings.master), float(settings.music), float(settings.sfx))
	world.camera().fov = float(settings.fov)


func _hud_settings() -> Dictionary:
	return {"sector_name": String(Sectors.info(sim.sector).name)}


func _upgrade_card(id: String) -> Dictionary:
	for card in Upgrades.pool():
		if String(card.id) == id:
			return card
	return {}


func _upgrade_name(id: String) -> String:
	var card := _upgrade_card(id)
	return String(card.get("name", id))


func _set_state(next: State) -> void:
	state = next


func _set_mouse(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
