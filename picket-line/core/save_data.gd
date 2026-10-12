# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name SaveData
extends RefCounted
## Pure data helpers for settings and high scores. File I/O lives in game/save.gd.

const TOP_COUNT := 10


static func default_settings() -> Dictionary:
	return {
		"sensitivity": 1.0,
		"invert_y": false,
		"fov": 75.0,
		"master": 0.8,
		"music": 0.6,
		"sfx": 0.8,
		"quality": 1,
		"dodge_mode": 0,
		"shake": 1.0,
	}


## Inserts entry into scores (sorted by "score", highest first, ties after older entries), keeps the top ten
## and returns the 0-based rank, or -1 when it did not make the table. scores is updated in place.
static func add_highscore(scores: Array, entry: Dictionary) -> int:
	var idx := 0
	var value := int(entry.get("score", 0))
	while idx < scores.size() and int(scores[idx].get("score", 0)) >= value:
		idx += 1
	scores.insert(idx, entry)
	while scores.size() > TOP_COUNT:
		scores.pop_back()
	return idx if idx < TOP_COUNT else -1
