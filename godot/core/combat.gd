# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name Combat
extends RefCounted
## Damage and target queries. Port of the Combat static class in Combat.cs.


## Applies damage to a hit-points value. Returns [new_hp, overkill, killed].
## overkill = -hp when killed, else 0. When killed, new_hp is clamped to 0.
static func apply_to_hp(hp_value: float, damage: float) -> Array:
	var left: float = hp_value - damage
	if left > 0.0:
		return [left, 0.0, false]
	return [0.0, -left, true]


## Damages one enemy and books the kill and overkill in the economy. Returns true if it died.
## Same maths as apply_to_hp, inlined so a hot hit path does not allocate an Array per call.
static func hit(swarm: Swarm, i: int, damage: float, economy: BattleEconomy) -> bool:
	if swarm.alive[i] == 0 or damage <= 0.0:
		return false
	var left: float = swarm.hp[i] - damage
	if left > 0.0:
		swarm.set_hp(i, left)
		return false
	var overkill: float = -left
	swarm.set_hp(i, 0.0)
	economy.on_kill(swarm.kind[i], overkill)
	# A merged crowd dies as one body but pays out as many (kills + carried rewards).
	if swarm.clump_count[i] > 1:
		economy.bonus_kills(swarm.clump_count[i] - 1, swarm.extra_reward[i])
	swarm.kill(i)
	return true


## Area damage (splash, pulse, line, burst). A merged crowd is many bodies inside the area, so
## it takes the damage once per member. Single-target paths keep hit().
static func hit_area(swarm: Swarm, i: int, damage: float, economy: BattleEconomy) -> bool:
	return hit(swarm, i, damage * float(maxi(1, swarm.clump_count[i])), economy)


## Nearest alive enemy to (x, z) within reach, XZ distance. Brute force over high_water.
## Returns -1 if none. Ties go to the higher slot index (later iteration wins, as in C#).
static func nearest_in_range(swarm: Swarm, x: float, z: float, reach: float) -> int:
	var best: float = reach * reach
	var found: int = -1
	var alive: PackedByteArray = swarm.alive
	var xs: PackedFloat32Array = swarm.x
	var zs: PackedFloat32Array = swarm.z
	var high: int = swarm.high_water
	for i in range(high):
		if alive[i] == 0:
			continue
		var dx: float = xs[i] - x
		var dz: float = zs[i] - z
		var d2: float = dx * dx + dz * dz
		if d2 > best:
			continue
		best = d2
		found = i
	return found


## Caller-owned index buffer for Combat.collect. GDScript passes a PackedInt32Array by value, so a
## write made inside a static function lands on a private copy and the caller never sees it. This
## object holds the array instead; the buffer's own methods write to it in place. Keep one per caller
## as a member.
class IndexBuffer extends RefCounted:
	var items: PackedInt32Array = PackedInt32Array()
	var count: int = 0

	## Grows items to at least `slots` entries. Never shrinks.
	func reserve(slots: int) -> void:
		if items.size() < slots:
			items.resize(slots)

	func clear() -> void:
		count = 0

	## Appends one index. reserve() must have made room first.
	func push(i: int) -> void:
		items[count] = i
		count += 1

	## Replaces the contents with the first n entries of src. With ordered, they come back sorted
	## ascending: entries past n are first set to `slots`, which sorts after every real index, so one
	## native sort orders just the first n. Without it the copy keeps src's order and costs no sort.
	func load_from(src: PackedInt32Array, n: int, slots: int, ordered: bool) -> void:
		reserve(slots)
		if ordered:
			items.fill(slots)
		for k in n:
			items[k] = src[k]
		count = n
		if ordered and n > 1:
			items.sort()


## Writes every alive enemy within XZ radius of (x, z) into `into`, in ascending slot order, and
## returns how many. Replaces the previous contents. into.items must hold at least swarm.capacity
## entries, so call into.reserve(swarm.capacity) before the first collect. Allocates nothing.
static func collect(swarm: Swarm, x: float, z: float, radius: float, into: IndexBuffer) -> int:
	assert(into.items.size() >= swarm.capacity)
	into.clear()
	var r2: float = radius * radius
	var alive: PackedByteArray = swarm.alive
	var xs: PackedFloat32Array = swarm.x
	var zs: PackedFloat32Array = swarm.z
	var high: int = swarm.high_water
	for i in range(high):
		if alive[i] == 0:
			continue
		var dx: float = xs[i] - x
		var dz: float = zs[i] - z
		if dx * dx + dz * dz <= r2:
			into.push(i)
	return into.count

