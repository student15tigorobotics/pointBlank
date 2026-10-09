class_name Swarm
extends RefCounted
## Enemy simulation in struct-of-arrays layout. Port of Swarm.cs.
## Pure logic: the engine layer only reads positions. Dead slots are recycled through a
## free list so spawning is O(1). Per-enemy data lives in packed float32 arrays, as the
## C# floats did. Each enemy keeps a monotonic segment hint (seg) so Step never scans the path.

const ENEMY_KINDS: int = 5

var capacity: int = 0
var alive_count: int = 0
var high_water: int = 0   # first never-used slot; iteration runs to here

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
	_free.resize(cap)

	_hover.resize(ENEMY_KINDS)
	_base_hp.resize(ENEMY_KINDS)
	_base_speed.resize(ENEMY_KINDS)
	for k in range(ENEMY_KINDS):
		var st: Dictionary = Balance.enemy(k)
		_hover[k] = st["hover"]
		_base_hp[k] = st["hp"]
		_base_speed[k] = st["speed"]

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
	_place(i)
	return i


func kill(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	alive_count -= 1
	_free[_free_count] = i
	_free_count += 1


## Writes hit points for slot i. Combat uses this instead of writing the packed array from outside.
func set_hp(i: int, value: float) -> void:
	hp[i] = value


## Advances every enemy along the path. Enemies reaching the core deal core damage and are removed.
func step(dt: float, economy: BattleEconomy) -> void:
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

		dist[i] += speed[i] * slow_mul[i] * dt
		if dist[i] >= plen:
			economy.on_leak(kind[i])
			kill(i)
			continue
		_place(i)


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

	x[i] = px
	z[i] = pz
	y[i] = _hover[kind[i]] + 0.02 * seed_v[i]
	heading[i] = atan2(hx, hz)
