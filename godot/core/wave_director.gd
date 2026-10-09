# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name WaveDirector
extends RefCounted
## Drives one chapter: prep countdown, staggered spawn groups, clear detection and early-call bonuses.
## Pure logic; the caller applies the spawn list to the swarm. Port of WaveDirector.cs.
## stage is a StageCatalog stage dict: stage["waves"] is an Array of { groups: Array, total_count: int },
## and each group is { kind: int, count: int, delay: float, interval: float }.

enum Phase { PREP, ACTIVE, FINISHED }

var phase: int = Phase.PREP
var wave_index: int = 0
var prep_remaining: float = 0.0
var just_cleared: bool = false  # true for one update after a wave is cleared
var cleared_wave_index: int = 0

var _waves: Array = []
var _prep_seconds: float = 0.0
var _wave_time: float = 0.0

# Current wave's groups flattened into packed arrays, rebuilt only when a wave begins.
var _g_kind: PackedInt32Array = PackedInt32Array()
var _g_count: PackedInt32Array = PackedInt32Array()
var _g_interval: PackedFloat64Array = PackedFloat64Array()
var _next_spawn: PackedFloat64Array = PackedFloat64Array()
var _emitted: PackedInt32Array = PackedInt32Array()


func _init(stage: Dictionary, prep_seconds: float = Balance.PREP_SECONDS) -> void:
	_waves = stage["waves"]
	_prep_seconds = prep_seconds
	phase = Phase.PREP
	prep_remaining = prep_seconds
	_begin_arrays()


func wave_count() -> int:
	return _waves.size()


## Starts the wave now. Returns the early-call bonus for the prep time skipped.
func call_early(bonus_mult: float, economy: BattleEconomy) -> int:
	if phase != Phase.PREP:
		return 0
	var bonus: int = BattleEconomy.early_call_bonus(prep_remaining, bonus_mult)
	economy.on_early_call(bonus)
	_begin()
	return bonus


## Advances timers and appends the EnemyKind ints to spawn this frame to spawns.
## alive is the swarm's live count before this frame's spawns are applied.
## room is how many more entries this frame may add (the caller's free enemy slots, counting
## spawns already in the list). Spawns that do not fit stay pending and are emitted on a later frame.
func update(dt: float, alive: int, spawns: Array, room: int = 1000000) -> void:
	just_cleared = false
	if phase == Phase.FINISHED:
		return

	if phase == Phase.PREP:
		prep_remaining -= dt
		if prep_remaining <= 0.0:
			_begin()
		return

	_wave_time += dt
	var budget: int = room - spawns.size()
	var all_emitted: bool = true
	for g in range(_g_count.size()):
		var kind: int = _g_kind[g]
		var total: int = _g_count[g]
		while _emitted[g] < total and _wave_time >= _next_spawn[g] and budget > 0:
			spawns.append(kind)
			_emitted[g] += 1
			_next_spawn[g] += _g_interval[g]
			budget -= 1
		if _emitted[g] < total:
			all_emitted = false

	if all_emitted and alive == 0 and spawns.size() == 0:
		cleared_wave_index = wave_index
		just_cleared = true
		wave_index += 1
		if wave_index >= _waves.size():
			phase = Phase.FINISHED
		else:
			phase = Phase.PREP
			prep_remaining = _prep_seconds
			_begin_arrays()


func _begin() -> void:
	phase = Phase.ACTIVE
	_begin_arrays()


func _begin_arrays() -> void:
	var wave: Dictionary = _waves[wave_index]
	var groups: Array = wave["groups"]
	var n: int = groups.size()
	_g_kind.resize(n)
	_g_count.resize(n)
	_g_interval.resize(n)
	_next_spawn.resize(n)
	_emitted.resize(n)
	for g in range(n):
		var grp: Dictionary = groups[g]
		_g_kind[g] = int(grp["kind"])
		_g_count[g] = int(grp["count"])
		_g_interval[g] = float(grp["interval"])
		_next_spawn[g] = float(grp["delay"])
		_emitted[g] = 0
	_wave_time = 0.0
