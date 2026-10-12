# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Run
extends RefCounted
## One playthrough: six sectors in order, with an upgrade pick after each cleared sector.

var seed_value := 1
var difficulty := 0
var sector := 0
var owned: Array = []
var total_score := 0
var history: Array = []
var pending_offer: Array = []
var over := false
var victory := false
var _rng: Rng


func _init(seed_v: int = 1, diff_level: int = 1) -> void:
	seed_value = seed_v
	difficulty = diff_level
	_rng = Rng.new(seed_v * 31 + 7)


func mods() -> Dictionary:
	return Upgrades.mods_for(owned)


func start_sector() -> Sim:
	return Sim.new(sector, difficulty, seed_value * 97 + sector * 13 + 5, mods())


## Records a finished sector. Returns a summary dictionary and sets up the upgrade offer or the end of the run.
func finish_sector(sim: Sim) -> Dictionary:
	var summary := {"sector": sector, "score": sim.score, "kills": sim.kills,
		"accuracy": sim.accuracy(), "clean": sim.clean, "won": sim.won, "time": sim.time}
	history.append(summary)
	total_score += sim.score
	if not sim.won:
		over = true
	elif sector >= Sectors.count() - 1:
		victory = true
		over = true
	else:
		pending_offer = Upgrades.offer(_rng, owned, 3)
	return summary


func offer_upgrades() -> Array:
	return pending_offer


## Takes an upgrade card (or nothing, with "") and moves on to the next sector.
func choose(id: String) -> void:
	if id != "" and not owned.has(id):
		owned.append(id)
	pending_offer = []
	if not over:
		sector += 1


func is_over() -> bool:
	return over


func is_victory() -> bool:
	return victory
