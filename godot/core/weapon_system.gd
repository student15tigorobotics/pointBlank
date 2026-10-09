# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name WeaponSystem
extends RefCounted
## The player's held weapons. Port of Weapons.cs WeaponSystem.
## Aim is a world ray in table-local space. Aim assist is built in: shots snap to the enemy
## closest to the aim axis inside the weapon's cone.

var cooldown: float = 0.0
var damage_mult: float = 1.0
var cooldown_mult: float = 1.0

# Per-WeaponKind stats, flattened once so firing never builds dictionaries.
var _w_cooldown: PackedFloat32Array = PackedFloat32Array()
var _w_damage: PackedFloat32Array = PackedFloat32Array()
var _w_range: PackedFloat32Array = PackedFloat32Array()
var _w_cone: PackedFloat32Array = PackedFloat32Array()
var _w_radius: PackedFloat32Array = PackedFloat32Array()
var _w_count: PackedInt32Array = PackedInt32Array()

var _scratch: PackedInt32Array = PackedInt32Array()
var _scatter_slot: PackedInt32Array = PackedInt32Array()
var _scatter_cos: PackedFloat64Array = PackedFloat64Array()
# Arc chain set as stamps: _marks[i] == _stamp means enemy i is already in this chain.
var _marks: PackedInt32Array = PackedInt32Array()
var _stamp: int = 0

# Side results of _in_cone(), kept in members so the per-enemy loops allocate nothing.
var _cone_cos: float = 0.0
var _cone_t: float = 0.0


func _init() -> void:
	for k in range(Balance.WeaponKind.NOVA + 1):
		var s: Dictionary = Balance.weapon(k)
		_w_cooldown.append(float(s["cooldown"]))
		_w_damage.append(float(s["damage"]))
		_w_range.append(float(s["range"]))
		_w_cone.append(float(s["cone_deg"]))
		_w_radius.append(float(s["radius"]))
		_w_count.append(int(s["count"]))
	_scatter_slot.resize(16)
	_scatter_cos.resize(16)


func ready() -> bool:
	return cooldown <= 0.0


func tick(dt: float) -> void:
	if cooldown > 0.0:
		cooldown -= dt


## Fires if off cooldown. Returns the number of enemies damaged.
func try_fire(kind: int, origin: Vector3, dir: Vector3, swarm: Swarm, economy: BattleEconomy, shots: Array) -> int:
	if not ready():
		return 0
	cooldown = _w_cooldown[kind] * cooldown_mult
	var dmg: float = _w_damage[kind] * damage_mult
	var d: Vector3 = _normalized(dir)

	if kind == Balance.WeaponKind.BLASTER:
		return _fire_blaster(kind, origin, d, dmg, swarm, economy, shots)
	if kind == Balance.WeaponKind.SCATTER:
		return _fire_scatter(kind, origin, d, dmg, swarm, economy, shots)
	if kind == Balance.WeaponKind.RAIL:
		return _fire_rail(kind, origin, d, dmg, swarm, economy, shots)
	if kind == Balance.WeaponKind.ARC:
		return _fire_arc(kind, origin, d, dmg, swarm, economy, shots)
	return _fire_nova(kind, origin, d, dmg, swarm, economy, shots)


func _fire_blaster(kind: int, o: Vector3, d: Vector3, dmg: float, swarm: Swarm, economy: BattleEconomy, shots: Array) -> int:
	var target: int = _best_in_cone(swarm, o, d, _w_range[kind], _w_cone[kind])
	if target < 0:
		return 0
	shots.append(ShotStyle.make(o, _pos(swarm, target), 0.0, ShotStyle.Style.BOLT))
	Combat.hit(swarm, target, dmg, economy)
	return 1


func _fire_scatter(kind: int, o: Vector3, d: Vector3, dmg: float, swarm: Swarm, economy: BattleEconomy, shots: Array) -> int:
	var cos_cone: float = _cos_deg(_w_cone[kind])
	var reach: float = _w_range[kind]
	var cap: int = mini(_w_count[kind], _scatter_slot.size())
	var n: int = 0
	for i in range(swarm.high_water):
		if not swarm.alive[i]:
			continue
		if not _in_cone(o, d, _pos(swarm, i), reach, cos_cone):
			continue
		var c: float = _cone_cos
		if n < cap:
			_scatter_slot[n] = i
			_scatter_cos[n] = c
			n += 1
			continue
		# Keep the cap enemies closest to the aim axis: replace the weakest kept candidate.
		var worst: int = 0
		for k in range(1, cap):
			if _scatter_cos[k] < _scatter_cos[worst]:
				worst = k
		if c > _scatter_cos[worst]:
			_scatter_slot[worst] = i
			_scatter_cos[worst] = c

	for k in range(n):
		var i: int = _scatter_slot[k]
		shots.append(ShotStyle.make(o, _pos(swarm, i), 0.0, ShotStyle.Style.PELLET))
		Combat.hit(swarm, i, dmg, economy)
	return n


func _fire_rail(kind: int, o: Vector3, d: Vector3, dmg: float, swarm: Swarm, economy: BattleEconomy, shots: Array) -> int:
	var reach: float = _w_range[kind]
	var radius: float = _w_radius[kind]
	shots.append(ShotStyle.make(o, o + d * reach, radius, ShotStyle.Style.BEAM))
	var hits: int = 0
	for i in range(swarm.high_water):
		if not swarm.alive[i]:
			continue
		# Inlined V3.RayDistance. An enemy behind the origin is off the rail even when it is
		# within radius of the origin, so the raw projection must not be negative.
		var p: Vector3 = _pos(swarm, i)
		var t: float = (p - o).dot(d)
		if t < 0.0:
			continue
		var perp: float = (p - (o + d * t)).length()
		if t > reach or perp > radius:
			continue
		Combat.hit(swarm, i, dmg, economy)
		hits += 1
	return hits


func _fire_arc(kind: int, o: Vector3, d: Vector3, dmg: float, swarm: Swarm, economy: BattleEconomy, shots: Array) -> int:
	var current: int = _best_in_cone(swarm, o, d, _w_range[kind], _w_cone[kind])
	if current < 0:
		return 0
	_begin_marks(swarm)
	var links: int = _w_count[kind]
	var radius: float = _w_radius[kind]
	var src: Vector3 = o
	var link: float = dmg
	var hits: int = 0
	var n: int = 0
	while n < links and current >= 0:
		var dst: Vector3 = _pos(swarm, current)
		shots.append(ShotStyle.make(src, dst, 0.0, ShotStyle.Style.CHAIN))
		_marks[current] = _stamp
		Combat.hit(swarm, current, link, economy)
		hits += 1
		src = dst
		link *= 0.85
		current = _nearest_excluding(swarm, src, radius)
		n += 1
	return hits


func _fire_nova(kind: int, o: Vector3, d: Vector3, dmg: float, swarm: Swarm, economy: BattleEconomy, shots: Array) -> int:
	# Land on the table plane where the aim line crosses it, otherwise at max range.
	var reach: float = _w_range[kind]
	var radius: float = _w_radius[kind]
	# The table-plane hit is used only when it lies ahead of the origin (t > 0).
	var plane_t: float = (-o.y / d.y) if d.y < -0.05 else 0.0
	var impact: Vector3
	if plane_t > 0.0:
		impact = o + d * minf(plane_t, reach * 1.5)
	else:
		impact = o + d * reach
	impact.y = 0.0
	shots.append(ShotStyle.make(o, impact, radius, ShotStyle.Style.BURST))

	# PackedArrays are passed by value, so the array returned by collect() must be assigned back.
	_scratch = Combat.collect(swarm, impact.x, impact.z, radius, PackedInt32Array())
	var count: int = _scratch.size()
	for k in range(count):
		var i: int = _scratch[k]
		var dx: float = swarm.x[i] - impact.x
		var dz: float = swarm.z[i] - impact.z
		var falloff: float = 1.0 - 0.5 * sqrt(dx * dx + dz * dz) / radius
		Combat.hit(swarm, i, dmg * falloff, economy)
	return count


## Enemy with the highest cosine to the aim axis inside the cone. Equal cosines: the later index wins (C# >=).
func _best_in_cone(swarm: Swarm, o: Vector3, d: Vector3, reach: float, cone_deg: float) -> int:
	var cos_cone: float = _cos_deg(cone_deg)
	var best: int = -1
	var best_cos: float = cos_cone
	for i in range(swarm.high_water):
		if not swarm.alive[i]:
			continue
		if not _in_cone(o, d, _pos(swarm, i), reach, cos_cone):
			continue
		if _cone_cos >= best_cos:
			best_cos = _cone_cos
			best = i
	return best


## Brute-force nearest alive enemy to src (XZ) not yet in the arc chain. Ties: later index wins (C# <=).
func _nearest_excluding(swarm: Swarm, src: Vector3, radius: float) -> int:
	var best: float = radius * radius
	var found: int = -1
	for i in range(swarm.high_water):
		if not swarm.alive[i] or _marks[i] == _stamp:
			continue
		var dx: float = swarm.x[i] - src.x
		var dz: float = swarm.z[i] - src.z
		var d2: float = dx * dx + dz * dz
		if d2 <= best:
			best = d2
			found = i
	return found


## Sets _cone_cos and _cone_t. Returns true when p is in front of the origin, within reach, and inside the cone.
func _in_cone(o: Vector3, d: Vector3, p: Vector3, reach: float, cos_cone: float) -> bool:
	var v: Vector3 = p - o
	var len_v: float = v.length()
	_cone_t = v.dot(d)
	_cone_cos = _cone_t / len_v if len_v > 1e-6 else 1.0
	return _cone_t > 0.0 and _cone_t <= reach and _cone_cos >= cos_cone


func _begin_marks(swarm: Swarm) -> void:
	_stamp += 1
	if _marks.size() < swarm.capacity:
		_marks.resize(swarm.capacity)


## Same as V3.Normalized: a near-zero vector becomes (0, 0, 1), not zero.
static func _normalized(v: Vector3) -> Vector3:
	var l: float = v.length()
	if l > 1e-6:
		return v * (1.0 / l)
	return Vector3(0.0, 0.0, 1.0)


static func _cos_deg(deg: float) -> float:
	return cos(deg * PI / 180.0)


static func _pos(swarm: Swarm, i: int) -> Vector3:
	return Vector3(swarm.x[i], swarm.y[i], swarm.z[i])
