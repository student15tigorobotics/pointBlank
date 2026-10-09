class_name TowerField
extends RefCounted
## Placed towers and their auto-targeting. Port of Towers.cs TowerField.
## Economy decisions are made by the caller through place / sell / upgrade.
## tick() takes an optional SpatialGrid. When it is null, range queries fall back to brute force.

var towers: Array = []
var damage_mult: float = 1.0

var _next_id: int = 1
var _scratch: PackedInt32Array = PackedInt32Array()
# Chain-hit set as stamps: _marks[i] == _stamp means enemy i was hit in the current chain.
var _marks: PackedInt32Array = PackedInt32Array()
var _stamp: int = 0

# Per-TowerKind stats, flattened once so tick() never builds dictionaries.
var _cost: PackedInt32Array = PackedInt32Array()
var _range: PackedFloat32Array = PackedFloat32Array()
var _cooldown: PackedFloat32Array = PackedFloat32Array()
var _damage: PackedFloat32Array = PackedFloat32Array()
var _splash: PackedFloat32Array = PackedFloat32Array()
var _slow: PackedFloat32Array = PackedFloat32Array()
var _slow_seconds: PackedFloat32Array = PackedFloat32Array()
var _chain: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	for k in range(Balance.TowerKind.SNIPER + 1):
		var s: Dictionary = Balance.tower(k)
		_cost.append(int(s["cost"]))
		_range.append(float(s["range"]))
		_cooldown.append(float(s["cooldown"]))
		_damage.append(float(s["damage"]))
		_splash.append(float(s["splash"]))
		_slow.append(float(s["slow"]))
		_slow_seconds.append(float(s["slow_seconds"]))
		_chain.append(int(s["chain"]))


## round(cost * 0.6 * level), as in C# (banker's rounding).
func upgrade_cost(t: TowerInstance) -> int:
	return _round_even(float(_cost[t.kind]) * Balance.TOWER_UPGRADE_COST_FACTOR * float(t.level))


@warning_ignore("integer_division")
func sell_value(t: TowerInstance) -> int:
	return t.spent * Balance.TOWER_SELL_PERCENT / 100


func can_place_at(x: float, z: float, path: BattlePath, occupied: Dictionary) -> bool:
	if towers.size() >= Balance.MAX_TOWERS:
		return false
	if absf(x) > Balance.FIELD_HALF or absf(z) > Balance.FIELD_HALF:
		return false
	if path.distance_to(x, z) < Balance.PAD_CLEARANCE:
		return false
	return not occupied.has(pad_key(x, z))


static func pad_key(x: float, z: float) -> int:
	var ix: int = _round_even(x / Balance.PAD_SPACING)
	var iz: int = _round_even(z / Balance.PAD_SPACING)
	return ix * 100000 + iz


func place(kind: int, x: float, z: float, cost: int, economy: BattleEconomy) -> TowerInstance:
	if not economy.try_spend(cost):
		return null
	var t := TowerInstance.new(_next_id, kind, x, z, cost)
	_next_id += 1
	towers.append(t)
	return t


func sell(t: TowerInstance, economy: BattleEconomy) -> int:
	var idx: int = towers.find(t)
	if idx < 0:
		return 0
	towers.remove_at(idx)
	var refund_amount: int = sell_value(t)
	economy.refund(refund_amount)
	return refund_amount


func upgrade(t: TowerInstance, economy: BattleEconomy) -> bool:
	if t.level >= Balance.MAX_TOWER_LEVEL:
		return false
	var cost: int = upgrade_cost(t)
	if not economy.try_spend(cost):
		return false
	t.spent += cost
	t.level += 1
	return true


## Nearest tower within radius. Equal distances: the later tower wins (C# uses <=).
func pick(x: float, z: float, radius: float) -> TowerInstance:
	var best: TowerInstance = null
	var best_d: float = radius * radius
	for t: TowerInstance in towers:
		var dx: float = t.x - x
		var dz: float = t.z - z
		var d2: float = dx * dx + dz * dz
		if d2 <= best_d:
			best_d = d2
			best = t
	return best


func tick(dt: float, swarm: Swarm, economy: BattleEconomy, shots: Array, grid: SpatialGrid) -> void:
	for t: TowerInstance in towers:
		t.cooldown -= dt
		if t.cooldown > 0.0:
			continue

		var k: int = t.kind
		var steps: float = float(t.level - 1)
		var level_boost: float = pow(Balance.TOWER_UPGRADE_DAMAGE, steps)
		var dmg: float = _damage[k] * damage_mult * level_boost
		t.cooldown = _cooldown[k] * pow(Balance.TOWER_UPGRADE_COOLDOWN, steps)

		if k == Balance.TowerKind.TURRET:
			_fire_single(t, dmg, swarm, economy, shots, grid)
		elif k == Balance.TowerKind.SNIPER:
			_fire_strongest(t, dmg, swarm, economy, shots, grid)
		elif k == Balance.TowerKind.MORTAR:
			_fire_shell(t, dmg, swarm, economy, shots, grid)
		elif k == Balance.TowerKind.TESLA:
			_fire_chain(t, dmg, swarm, economy, shots, grid)
		elif k == Balance.TowerKind.FROST:
			_fire_pulse(t, dmg, swarm, economy, shots, grid)


# Turret: nearest enemy in range, one bolt.
func _fire_single(t: TowerInstance, dmg: float, swarm: Swarm, economy: BattleEconomy, shots: Array, grid: SpatialGrid) -> void:
	var target: int = _nearest(swarm, t.x, t.z, _range[t.kind], grid)
	if target < 0:
		t.cooldown = 0.0
		return
	shots.append(ShotStyle.make(_top(t), _pos(swarm, target), 0.0, ShotStyle.Style.BOLT))
	Combat.hit(swarm, target, dmg, economy)


# Sniper: strongest current hp in range. Equal hp: the lowest index wins, as in C# (strict >).
func _fire_strongest(t: TowerInstance, dmg: float, swarm: Swarm, economy: BattleEconomy, shots: Array, grid: SpatialGrid) -> void:
	_collect(swarm, t.x, t.z, _range[t.kind], grid)
	var best: int = -1
	var best_hp: float = -1.0
	for i in _scratch:
		if not swarm.alive[i]:
			continue
		var hp: float = swarm.hp[i]
		if hp > best_hp or (hp == best_hp and i < best):
			best_hp = hp
			best = i
	if best < 0:
		t.cooldown = 0.0
		return
	shots.append(ShotStyle.make(_top(t), _pos(swarm, best), 0.0, ShotStyle.Style.LANCE))
	Combat.hit(swarm, best, dmg, economy)


# Mortar: nearest enemy is the impact point, splash with linear falloff to half damage at the edge.
func _fire_shell(t: TowerInstance, dmg: float, swarm: Swarm, economy: BattleEconomy, shots: Array, grid: SpatialGrid) -> void:
	var k: int = t.kind
	var target: int = _nearest(swarm, t.x, t.z, _range[k], grid)
	if target < 0:
		t.cooldown = 0.0
		return
	var tx: float = swarm.x[target]
	var tz: float = swarm.z[target]
	var splash: float = _splash[k]
	shots.append(ShotStyle.make(_top(t), Vector3(tx, 0.0, tz), splash, ShotStyle.Style.SHELL))
	_collect(swarm, tx, tz, splash, grid)
	for i in _scratch:
		var dx: float = swarm.x[i] - tx
		var dz: float = swarm.z[i] - tz
		var falloff: float = 1.0 - 0.5 * sqrt(dx * dx + dz * dz) / splash
		Combat.hit(swarm, i, dmg * falloff, economy)


# Tesla: chain of up to Chain+1 hits. Each link decays by 0.85 and never re-hits an enemy.
func _fire_chain(t: TowerInstance, dmg: float, swarm: Swarm, economy: BattleEconomy, shots: Array, grid: SpatialGrid) -> void:
	var k: int = t.kind
	var reach: float = _splash[k]
	var first: int = _nearest(swarm, t.x, t.z, _range[k], grid)
	if first < 0:
		t.cooldown = 0.0
		return

	_begin_marks(swarm)
	var src: Vector3 = _top(t)
	var current: int = first
	var link: float = dmg
	var n: int = 0
	while n <= _chain[k] and current >= 0:
		var dst: Vector3 = _pos(swarm, current)
		shots.append(ShotStyle.make(src, dst, 0.0, ShotStyle.Style.CHAIN))
		_marks[current] = _stamp
		Combat.hit(swarm, current, link, economy)
		src = dst
		link *= 0.85
		current = _nearest_excluding(swarm, dst.x, dst.z, reach, grid)
		n += 1


# Frost: slows and damages every enemy in range, with a visual pulse.
func _fire_pulse(t: TowerInstance, dmg: float, swarm: Swarm, economy: BattleEconomy, shots: Array, grid: SpatialGrid) -> void:
	var k: int = t.kind
	var reach: float = _range[k]
	var anchor: Vector3 = Vector3(t.x, 0.01, t.z)
	shots.append(ShotStyle.make(anchor, anchor, reach, ShotStyle.Style.PULSE))
	_collect(swarm, t.x, t.z, reach, grid)
	var slow_mul: float = _slow[k]
	var slow_secs: float = _slow_seconds[k]
	for i in _scratch:
		swarm.slow(i, slow_mul, slow_secs)
		Combat.hit(swarm, i, dmg, economy)


## Fills _scratch with alive enemy indices within radius, ascending (same order as C# Combat.Collect).
## With a grid the result is sorted so hit order matches the brute-force path.
## PackedArrays are passed by value, so the array returned by collect() must be assigned back.
func _collect(swarm: Swarm, x: float, z: float, radius: float, grid: SpatialGrid) -> void:
	if grid != null:
		_scratch = grid.collect(x, z, radius, PackedInt32Array())
		_scratch.sort()
	else:
		_scratch = Combat.collect(swarm, x, z, radius, PackedInt32Array())


func _nearest(swarm: Swarm, x: float, z: float, reach: float, grid: SpatialGrid) -> int:
	if grid != null:
		return grid.nearest(swarm, x, z, reach)
	return Combat.nearest_in_range(swarm, x, z, reach)


## Nearest alive enemy not yet in the current chain. Equal distances: the highest index wins,
## which is what C#'s ascending scan with <= produces.
func _nearest_excluding(swarm: Swarm, x: float, z: float, reach: float, grid: SpatialGrid) -> int:
	_collect(swarm, x, z, reach, grid)
	var best: float = reach * reach
	var found: int = -1
	for i in _scratch:
		if not swarm.alive[i] or _marks[i] == _stamp:
			continue
		var dx: float = swarm.x[i] - x
		var dz: float = swarm.z[i] - z
		var d2: float = dx * dx + dz * dz
		if d2 > best:
			continue
		if d2 < best or i > found:
			best = d2
			found = i
	return found


func _begin_marks(swarm: Swarm) -> void:
	_stamp += 1
	if _marks.size() < swarm.capacity:
		_marks.resize(swarm.capacity)


static func _top(t: TowerInstance) -> Vector3:
	return Vector3(t.x, 0.12, t.z)


static func _pos(swarm: Swarm, i: int) -> Vector3:
	return Vector3(swarm.x[i], swarm.y[i], swarm.z[i])


## Round half to even, matching C# Math.Round(double).
static func _round_even(x: float) -> int:
	var f: float = floorf(x)
	var diff: float = x - f
	var base: int = int(f)
	if diff > 0.5:
		return base + 1
	if diff < 0.5:
		return base
	return base if base % 2 == 0 else base + 1
