# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name Swarm
extends RefCounted
## Enemy simulation in struct-of-arrays layout. Port of Swarm.cs.
## Pure logic: the engine layer only reads positions. Dead slots are recycled through a
## free list so spawning is O(1). Per-enemy data lives in packed float32 arrays, as the
## C# floats did. Each enemy keeps a monotonic segment hint (seg) so Step never scans the path.

const ENEMY_KINDS: int = 5
const LANE_HALF: float = 0.07        # lateral room either side of the path centre line
const DEATH_CAP: int = 32            # death events kept per frame for the view's explosions
const SEP_RADIUS_MUL: float = 0.85   # body radius = scale * this, for enemy-vs-enemy pushes

var capacity: int = 0
var alive_count: int = 0
var high_water: int = 0   # first never-used slot; iteration runs to here

# Deaths recorded since the last clear_deaths(), as positions the view can explode at.
var death_count: int = 0
var death_x: PackedFloat32Array = PackedFloat32Array()
var death_y: PackedFloat32Array = PackedFloat32Array()
var death_z: PackedFloat32Array = PackedFloat32Array()

var x: PackedFloat32Array = PackedFloat32Array()
var y: PackedFloat32Array = PackedFloat32Array()
var z: PackedFloat32Array = PackedFloat32Array()
var hp: PackedFloat32Array = PackedFloat32Array()
var max_hp: PackedFloat32Array = PackedFloat32Array()
var dist: PackedFloat32Array = PackedFloat32Array()
var speed: PackedFloat32Array = PackedFloat32Array()
var slow_left: PackedFloat32Array = PackedFloat32Array()
var slow_mul: PackedFloat32Array = PackedFloat32Array()
var seed_v: PackedFloat32Array = PackedFloat32Array()
var heading: PackedFloat32Array = PackedFloat32Array()
var kind: PackedInt32Array = PackedInt32Array()
var alive: PackedByteArray = PackedByteArray()   # 1 = alive
var seg: PackedInt32Array = PackedInt32Array()   # current segment index (monotonic hint)
var lane: PackedFloat32Array = PackedFloat32Array()  # lateral offset from the path centre, +-LANE_HALF
var clump_count: PackedInt32Array = PackedInt32Array()  # 1 = individual; N>1 = a merged crowd of N
var extra_reward: PackedInt32Array = PackedInt32Array() # credits carried by absorbed members
var clump_core_damage: PackedInt32Array = PackedInt32Array()  # core damage the whole body deals on a leak (sum over members)

var path: BattlePath

var _free: PackedInt32Array = PackedInt32Array()
var _free_count: int = 0
var _hover: PackedFloat32Array = PackedFloat32Array()      # per EnemyKind, cached so Place never allocates
var _base_hp: PackedFloat32Array = PackedFloat32Array()    # per EnemyKind
var _base_speed: PackedFloat32Array = PackedFloat32Array() # per EnemyKind
var _vx: PackedFloat32Array
var _vz: PackedFloat32Array
var _cum: PackedFloat32Array
var _last_seg: int = 0
var _radius: PackedFloat32Array = PackedFloat32Array()   # per EnemyKind body radius
var _core_damage: PackedInt32Array = PackedInt32Array()  # per EnemyKind core damage on leak
var _sep_buf: PackedInt32Array = PackedInt32Array()      # neighbour scratch for _separate


func _init(p: BattlePath, cap: int) -> void:
	path = p
	capacity = cap
	x.resize(cap)
	y.resize(cap)
	z.resize(cap)
	hp.resize(cap)
	max_hp.resize(cap)
	dist.resize(cap)
	speed.resize(cap)
	slow_left.resize(cap)
	slow_mul.resize(cap)
	seed_v.resize(cap)
	heading.resize(cap)
	kind.resize(cap)
	alive.resize(cap)
	seg.resize(cap)
	lane.resize(cap)
	clump_count.resize(cap)
	extra_reward.resize(cap)
	clump_core_damage.resize(cap)
	_free.resize(cap)
	var cells: int = MERGE_SIDE * MERGE_SIDE
	_merge_count.resize(cells)
	_merge_head.resize(cells)
	_merge_next.resize(cap)
	death_x.resize(DEATH_CAP)
	death_y.resize(DEATH_CAP)
	death_z.resize(DEATH_CAP)

	_hover.resize(ENEMY_KINDS)
	_base_hp.resize(ENEMY_KINDS)
	_base_speed.resize(ENEMY_KINDS)
	_radius.resize(ENEMY_KINDS)
	_core_damage.resize(ENEMY_KINDS)
	for k in range(ENEMY_KINDS):
		var st: Dictionary = Balance.enemy(k)
		_hover[k] = st["hover"]
		_base_hp[k] = st["hp"]
		_base_speed[k] = st["speed"]
		_radius[k] = float(st["scale"]) * SEP_RADIUS_MUL
		_core_damage[k] = int(st["core_damage"])

	_vx = path.vx
	_vz = path.vz
	_cum = path.cum
	_last_seg = _vx.size() - 2


## Spawns one enemy at the path start. Returns the slot, or -1 when full.
func spawn(kind_i: int, hp_scale: float, seed_value: float) -> int:
	if alive_count >= capacity:
		return -1
	var i: int
	if _free_count > 0:
		_free_count -= 1
		i = _free[_free_count]
	else:
		i = high_water
		high_water += 1

	kind[i] = kind_i
	var max_v: float = _base_hp[kind_i] * hp_scale
	hp[i] = max_v
	max_hp[i] = max_v
	speed[i] = _base_speed[kind_i] * (0.9 + 0.2 * seed_value)
	dist[i] = -seed_value * 0.12   # slight stagger so spawns don't stack on one point
	slow_left[i] = 0.0
	slow_mul[i] = 1.0
	seed_v[i] = seed_value
	alive[i] = 1
	alive_count += 1
	seg[i] = 0
	lane[i] = (seed_value * 2.0 - 1.0) * LANE_HALF * 0.8
	clump_count[i] = 1
	extra_reward[i] = 0
	clump_core_damage[i] = _core_damage[kind_i]
	_place(i)
	return i


func kill(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	alive_count -= 1
	_free[_free_count] = i
	_free_count += 1
	if death_count < DEATH_CAP:
		death_x[death_count] = x[i]
		death_y[death_count] = y[i]
		death_z[death_count] = z[i]
		death_count += 1


## Forgets the recorded deaths. The controller calls this after spawning their explosions.
func clear_deaths() -> void:
	death_count = 0


## Writes hit points for slot i. Combat uses this instead of writing the packed array from outside.
func set_hp(i: int, value: float) -> void:
	hp[i] = value


## Advances every enemy along the path. Enemies reaching the core deal core damage and are removed.
## grid (last frame's snapshot) enables body collision: enemies push each other sideways within
## the lane and a blocked follower stalls behind the body in front, so crowds weave through gaps
## or jam up instead of passing through each other. Pass null (benchmark) to skip collision.
func step(dt: float, economy: BattleEconomy, grid: SpatialGrid = null) -> void:
	var plen: float = path.length
	var n: int = high_water
	for i in range(n):
		if alive[i] == 0:
			continue

		if slow_left[i] > 0.0:
			slow_left[i] -= dt
			if slow_left[i] <= 0.0:
				slow_left[i] = 0.0
				slow_mul[i] = 1.0

		var advance: float = speed[i] * slow_mul[i] * dt
		if grid != null:
			advance = _separate(i, advance, dt, grid)
		dist[i] += advance
		if dist[i] >= plen:
			# A merged crowd leaks as one group: every member counts, the core takes the summed damage.
			if clump_count[i] > 1:
				economy.on_leak_group(clump_core_damage[i], clump_count[i])
			else:
				economy.on_leak(kind[i])
			kill(i)
			continue
		_place(i)


## Collision against last frame's neighbour snapshot. Returns the (possibly cancelled) forward
## advance and nudges lane[i] away from overlapping bodies. A body ahead blocks; bodies beside
## push sideways, so enemies slip through gaps when there is room and trap each other when not.
func _separate(i: int, advance: float, dt: float, grid: SpatialGrid) -> float:
	var ri: float = _radius[kind[i]]
	var reach: float = ri + 0.22       # covers the largest neighbour radius (Titan)
	_sep_buf.clear()
	_sep_buf = grid.collect(x[i], z[i], reach, _sep_buf)
	if _sep_buf.size() <= 1:
		return advance
	var hd: float = heading[i]
	var hx: float = sin(hd)
	var hz: float = cos(hd)
	var push: float = 0.0
	var blocked: bool = false
	var checked: int = 0
	for k in _sep_buf.size():
		var j: int = _sep_buf[k]
		if j == i or alive[j] == 0:
			continue
		var ddx: float = x[j] - x[i]
		var ddz: float = z[j] - z[i]
		var rr: float = ri + _radius[kind[j]]
		var d2: float = ddx * ddx + ddz * ddz
		if d2 >= rr * rr:
			continue
		var ahead: float = ddx * hx + ddz * hz
		var lateral: float = ddx * hz - ddz * hx   # +: neighbour is to the right
		var overlap: float = rr - sqrt(maxf(d2, 1e-8))
		if ahead > 0.0 and ahead > absf(lateral):
			blocked = true                          # body in front: stall this frame
		push -= (overlap if lateral > 0.0 else -overlap)
		checked += 1
		if checked >= 6:
			break
	if checked > 0:
		lane[i] = clampf(lane[i] + clampf(push, -0.3 * dt, 0.3 * dt) * 6.0, -LANE_HALF, LANE_HALF)
	return 0.0 if blocked else advance


## Applies a slow, keeping the strongest active slow.
func slow(i: int, mult: float, seconds: float) -> void:
	if alive[i] == 0:
		return
	if slow_left[i] <= 0.0 or mult < slow_mul[i]:
		slow_mul[i] = mult
	slow_left[i] = maxf(slow_left[i], seconds)


## Writes position, height, heading and segment hint for slot i from dist[i].
func _place(i: int) -> void:
	var d: float = dist[i]
	var s: int = seg[i]
	# Hint correction: step back if d is behind the hint, then forward while the next vertex is still behind d.
	# Dist only grows during play, so the forward loop is the common case. Result equals the C# linear scan.
	while s > 0 and _cum[s] >= d:
		s -= 1
	while s < _last_seg and _cum[s + 1] < d:
		s += 1
	seg[i] = s

	var ax: float = _vx[s]
	var az: float = _vz[s]
	var ex: float = _vx[s + 1] - ax
	var ez: float = _vz[s + 1] - az
	var hl: float = sqrt(ex * ex + ez * ez)
	var hx: float = 0.0
	var hz: float = 1.0
	if hl > 1e-6:
		hx = ex / hl
		hz = ez / hl

	var px: float
	var pz: float
	if d <= 0.0:
		# Spawn stagger: extrapolate behind the first vertex along its heading (s is 0 here).
		px = ax + hx * d
		pz = az + hz * d
	else:
		var seg_len: float = _cum[s + 1] - _cum[s]
		var t: float = 0.0
		if seg_len > 1e-6:
			t = (d - _cum[s]) / seg_len
		px = ax + ex * t
		pz = az + ez * t

	# Lateral lane offset, perpendicular to the segment heading (right-hand side positive).
	var l: float = lane[i]
	x[i] = px + hz * l
	z[i] = pz - hx * l
	y[i] = _hover[kind[i]] + 0.02 * seed_v[i]
	heading[i] = atan2(hx, hz)


# ---- Crowd merging (persistent clumps) --------------------------------------------------------
# Once CLUMP_THRESHOLD enemies pack one cell they MERGE into a single real enemy with summed
# hit points and carried rewards, and stay merged until defeated (owner 2026-10-12: per-frame
# re-binning in the renderer was wasted computation). merge_crowds is called a couple of times
# a second by the controller, never per frame.

const CLUMP_THRESHOLD: int = 30
const MERGE_CELL: float = 0.25
const MERGE_SIDE: int = 16

var _merge_count: PackedInt32Array = PackedInt32Array()
var _merge_head: PackedInt32Array = PackedInt32Array()
var _merge_next: PackedInt32Array = PackedInt32Array()


func merge_crowds() -> void:
	if alive_count < CLUMP_THRESHOLD:
		return
	_merge_count.fill(0)
	_merge_head.fill(-1)
	for i in high_water:
		if alive[i] == 0:
			continue
		var c: int = _merge_cell(x[i], z[i])
		_merge_count[c] += clump_count[i]
		_merge_next[i] = _merge_head[c]
		_merge_head[c] = i
	for c in MERGE_SIDE * MERGE_SIDE:
		if _merge_count[c] < CLUMP_THRESHOLD:
			continue
		# Survivor: the member furthest along the path (an existing clump wins), so the merged
		# body never teleports backward. Everyone else is absorbed silently - no death event.
		var survivor: int = -1
		var i2: int = _merge_head[c]
		while i2 >= 0:
			if survivor < 0 or clump_count[i2] > clump_count[survivor] \
					or (clump_count[i2] == clump_count[survivor] and dist[i2] > dist[survivor]):
				survivor = i2
			i2 = _merge_next[i2]
		var total_hp: float = 0.0
		var total_max: float = 0.0
		var total_n: int = 0
		var total_reward: int = 0
		var total_core: int = 0
		i2 = _merge_head[c]
		while i2 >= 0:
			total_hp += hp[i2]
			total_max += max_hp[i2]
			total_n += clump_count[i2]
			total_reward += extra_reward[i2]
			total_core += clump_core_damage[i2]
			if i2 != survivor:
				total_reward += int(Balance.enemy(kind[i2])["reward"])
				alive[i2] = 0
				alive_count -= 1
				_free[_free_count] = i2
				_free_count += 1
			i2 = _merge_next[i2]
		hp[survivor] = total_hp
		max_hp[survivor] = total_max
		clump_count[survivor] = total_n
		extra_reward[survivor] = total_reward
		clump_core_damage[survivor] = total_core


func _merge_cell(px: float, pz: float) -> int:
	var cx: int = clampi(int((px + 2.0) / MERGE_CELL), 0, MERGE_SIDE - 1)
	var cz: int = clampi(int((pz + 2.0) / MERGE_CELL), 0, MERGE_SIDE - 1)
	return cz * MERGE_SIDE + cx
