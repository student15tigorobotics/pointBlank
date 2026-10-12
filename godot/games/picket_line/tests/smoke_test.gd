# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
extends SceneTree
## Headless smoke run of the real scene. Starts a run, flies a scripted pilot through sectors with the
## real world, HUD and menus, and exercises pause, options, upgrades and debrief.
## Run: godot --headless --path godot -s res://games/picket_line/tests/smoke_test.gd
## A script error printed by Godot counts as a failure, as does not reaching the debrief in the frame budget.

const MainScript := preload("res://games/picket_line/game/main.gd")
const MAX_FRAMES := 60 * 1200
const SETTLE_FRAMES := 30

enum Phase { START, BEGIN, PLAYING, RESULT, UPGRADE, BRIEFING, DEBRIEF }


class PilotInput extends GameInput:
	var main: Node

	func poll(_dt: float, _settings: Dictionary) -> Dictionary:
		var sim: Sim = main.sim
		var target: Enemy = null
		var best := INF
		for e: Enemy in sim.enemies:
			if e.alive and e.pos.length() < best:
				best = e.pos.length()
				target = e
		var cmd := {"fire_held": false, "scope": false, "focus_held": false}
		if target == null:
			return cmd
		var want := PLBalance.aim_yaw_pitch(target.pos)
		var d := want - Vector2(sim.station.yaw, sim.station.pitch)
		cmd.aim = Vector2(clampf(d.x, -0.12, 0.12), clampf(d.y, -0.12, 0.12))
		cmd.fire_held = true
		cmd.scope = best < 300.0
		cmd.focus_held = best < 150.0
		return cmd

	func clear_mouse() -> void:
		pass


var _main: Node
var _frame := 0
var _phase: int = Phase.START
var _phase_frames := 0
var _sectors_played := 0
var _max_kills := 0
var _pause_done := false


func _init() -> void:
	# Headless frames run as fast as the machine allows, so the real frame delta drives the sim clock.
	# A fixed rate keeps a sector's length in frames predictable, and time scale 4 keeps a full run to a few minutes.
	Engine.max_fps = 60
	Engine.time_scale = 4.0
	var main: Node = load("res://games/picket_line/scenes/main.tscn").instantiate()
	root.add_child(main)
	_main = main


func _process(_delta: float) -> bool:
	_frame += 1
	_phase_frames += 1
	if _frame > MAX_FRAMES:
		return _fail("frame budget exhausted in phase %d" % _phase)
	match _phase:
		Phase.START:
			if _phase_frames >= SETTLE_FRAMES:
				_main._on_action("start", null)
				_set_phase(Phase.BEGIN)
		Phase.BEGIN:
			if _main.state != MainScript.State.BRIEFING:
				return _fail("expected briefing before begin, state %d" % _main.state)
			_main._on_action("begin", null)
			var pilot := PilotInput.new()
			pilot.main = _main
			_main.input = pilot
			_set_phase(Phase.PLAYING)
		Phase.PLAYING:
			_max_kills = maxi(_max_kills, _main.sim.kills)
			if _main.state == MainScript.State.PAUSED:
				return false
			if _main.state != MainScript.State.PLAY and _main.state != MainScript.State.SECTOR_RESULT:
				return _fail("unexpected state while playing: %d" % _main.state)
			if _main.state == MainScript.State.SECTOR_RESULT:
				_sectors_played += 1
				_set_phase(Phase.RESULT)
			elif not _pause_done and _phase_frames == 120:
				_exercise_pause()
				_pause_done = true
		Phase.RESULT:
			if _phase_frames < SETTLE_FRAMES:
				return false
			_main._on_action("continue", null)
			if _main.state == MainScript.State.DEBRIEF:
				_set_phase(Phase.DEBRIEF)
			elif _main.state == MainScript.State.UPGRADE:
				_set_phase(Phase.UPGRADE)
			else:
				return _fail("continue led to state %d" % _main.state)
		Phase.UPGRADE:
			var offers: Array = _main.run.offer_upgrades()
			if offers.size() != 3:
				return _fail("expected three upgrade offers, got %d" % offers.size())
			_main._on_action("pick", String(offers[0]))
			_set_phase(Phase.BRIEFING)
		Phase.BRIEFING:
			if _main.state != MainScript.State.BRIEFING:
				return _fail("expected briefing after pick, state %d" % _main.state)
			if _phase_frames < SETTLE_FRAMES:
				return false
			_main._on_action("begin", null)
			var next_pilot := PilotInput.new()
			next_pilot.main = _main
			_main.input = next_pilot
			_set_phase(Phase.PLAYING)
		Phase.DEBRIEF:
			if _main.state != MainScript.State.DEBRIEF:
				return _fail("expected debrief, state %d" % _main.state)
			return _pass()
	return false


func _exercise_pause() -> void:
	_main._open_pause()
	for i in SETTLE_FRAMES:
		_main.world.render(_main.sim, 0.0, _main.settings)
		_main.hud.render(_main.sim, 0.0, {"sector_name": "pause"})
	_main._on_action("options", null)
	_main._on_action("setting", {"key": "fov", "value": 90.0})
	_main._on_action("setting", {"key": "dodge_mode", "value": 1})
	_main._on_action("back", null)
	_main._on_action("resume", null)


func _set_phase(phase: int) -> void:
	_phase = phase
	_phase_frames = 0


func _pass() -> bool:
	print("SMOKE sectors=%d max_kills=%d total_score=%d victory=%s" % [
		_sectors_played, _max_kills, _main.run.total_score, str(_main.run.is_victory())])
	print("SMOKE_OK")
	quit(0)
	return true


func _fail(reason: String) -> bool:
	print("SMOKE_FAIL: " + reason)
	quit(1)
	return true
