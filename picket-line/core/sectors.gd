# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Sectors
extends RefCounted
## Six sectors with themed spawn pools. Bosses end sectors 2, 4 and 6 (indices 1, 3 and 5).
## Pool entries are [Balance.Kind value, weight]. Kinds: 0 Scout, 1 Drone, 2 Gunship, 3 Bomber, 4 Carrier, 5 Dreadnought.

const INFO := [
	{"name": "Outer Picket", "pool": [[0, 4], [1, 3]], "waves": 7, "length": 75.0, "boss": -1, "boss_hp": 1.0},
	{"name": "Debris Field", "pool": [[0, 3], [1, 3], [2, 2]], "waves": 9, "length": 95.0, "boss": 4, "boss_hp": 1.0},
	{"name": "Ion Storm", "pool": [[0, 2], [1, 3], [2, 2], [3, 2]], "waves": 10, "length": 110.0, "boss": -1, "boss_hp": 1.0},
	{"name": "Carrier Lane", "pool": [[0, 3], [1, 2], [2, 2], [4, 1]], "waves": 11, "length": 120.0, "boss": 4, "boss_hp": 1.4},
	{"name": "Shattered Ring", "pool": [[0, 2], [1, 3], [2, 3], [3, 2]], "waves": 12, "length": 125.0, "boss": -1, "boss_hp": 1.0},
	{"name": "Dreadnought Gate", "pool": [[0, 2], [1, 2], [2, 2], [3, 2], [4, 1]], "waves": 13, "length": 140.0, "boss": 5, "boss_hp": 1.0},
]


static func count() -> int:
	return INFO.size()


static func info(index: int) -> Dictionary:
	return INFO[clampi(index, 0, INFO.size() - 1)]


## Spawn events sorted by time: {t, kind, count, group, boss, hp_mult}. The boss, when present, is the last event.
static func schedule(index: int, diff: int, rng: Rng) -> Array:
	var sector: Dictionary = info(index)
	var mult: float = float(Balance.difficulty(diff).spawn_mult)
	var waves := int(sector.waves)
	var length := float(sector.length)
	var pool: Array = sector.pool
	var out: Array = []
	for w in waves:
		var ramp := 1.0 + 0.2 * float(w) / float(waves)
		var t := (float(w) + 0.5) / float(waves) * length * 0.9 + rng.range_f(-1.5, 1.5)
		out.append(_group(_pick(rng, pool), maxf(0.5, t), w + 1, mult, ramp, rng))
		if rng.chance(0.4):
			out.append(_group(_pick(rng, pool), maxf(0.5, t) + 4.0, w + 1, mult, ramp, rng))
	if int(sector.boss) >= 0:
		out.append({"t": length * 0.92, "kind": int(sector.boss), "count": 1, "group": 900,
			"boss": true, "hp_mult": float(sector.boss_hp)})
	out.sort_custom(func(a, b): return float(a.t) < float(b.t))
	return out


static func _group(kind: int, t: float, group: int, mult: float, ramp: float, rng: Rng) -> Dictionary:
	var def: Dictionary = Balance.ENEMY_DEFS[kind]
	var spawn: Vector2i = def.spawn
	var base := rng.range_i(spawn.x, spawn.y)
	var count := maxi(1, roundi(float(base) * ramp * mult))
	return {"t": t, "kind": kind, "count": count, "group": group, "boss": false, "hp_mult": 1.0}


static func _pick(rng: Rng, pool: Array) -> int:
	var total := 0
	for p in pool:
		total += int(p[1])
	var r := rng.range_i(1, total)
	for p in pool:
		r -= int(p[1])
		if r <= 0:
			return int(p[0])
	return int(pool[0][0])
