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
	swarm.kill(i)
	return true


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


## Appends every alive enemy within XZ radius of (x, z) to into, in ascending slot order.
## Returns the array with hits appended. PackedInt32Array is passed by value, so callers must
## assign the result: buf = Combat.collect(..., buf).
static func collect(swarm: Swarm, x: float, z: float, radius: float, into: PackedInt32Array) -> PackedInt32Array:
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
			into.append(i)
	return into
