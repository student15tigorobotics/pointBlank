# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name Projectiles
extends RefCounted
## Travelling weapon bolts in struct-of-arrays layout, engine-free like the rest of core/.
## The blaster and scatter fire these instead of hitscan rays: a bolt flies down the aim line
## at a fixed speed and damages the first enemy it passes within HIT_RADIUS of, so moving
## targets must be led. The view draws alive bolts each frame; impacts come back through the
## `impacts` array passed to tick (triples are appended as flat [x, y, z, style] runs).

const CAP: int = 96
const HIT_RADIUS: float = 0.09   # generous: bolts connect when visually close (owner ask)

var alive_count: int = 0

var px: PackedFloat32Array = PackedFloat32Array()
var py: PackedFloat32Array = PackedFloat32Array()
var pz: PackedFloat32Array = PackedFloat32Array()
var dx: PackedFloat32Array = PackedFloat32Array()
var dy: PackedFloat32Array = PackedFloat32Array()
var dz: PackedFloat32Array = PackedFloat32Array()
var speed: PackedFloat32Array = PackedFloat32Array()
var left: PackedFloat32Array = PackedFloat32Array()   # remaining flight range in metres
var damage: PackedFloat32Array = PackedFloat32Array()
var style: PackedInt32Array = PackedInt32Array()
var alive: PackedByteArray = PackedByteArray()

var kind: PackedByteArray = PackedByteArray()   # 0 = bolt, 1 = rolling ball

const KIND_BOLT: int = 0
const KIND_BALL: int = 1
const BALL_RADIUS: float = 0.05
const BALL_GRAVITY: float = 6.0     # softened for table scale; real 9.8 made throws dive
const BALL_FRICTION: float = 0.32   # fraction of speed lost per second while rolling
const BALL_CRUSH_RADIUS: float = 0.11

var _buf: PackedInt32Array = PackedInt32Array()
var _next: int = 0
var _hit_t: float = 0.0   # side result of _first_contact: entry fraction of the last hit


func _init() -> void:
	px.resize(CAP)
	py.resize(CAP)
	pz.resize(CAP)
	dx.resize(CAP)
	dy.resize(CAP)
	dz.resize(CAP)
	speed.resize(CAP)
	left.resize(CAP)
	damage.resize(CAP)
	style.resize(CAP)
	alive.resize(CAP)
	kind.resize(CAP)


## Launches one bolt. The pool recycles the oldest slot when full, so firing never fails.
func fire(origin: Vector3, dir: Vector3, bolt_speed: float, flight_range: float, dmg: float, style_i: int) -> void:
	var i: int = _next
	_next = (_next + 1) % CAP
	if alive[i] == 0:
		alive_count += 1
	alive[i] = 1
	px[i] = origin.x
	py[i] = origin.y
	pz[i] = origin.z
	dx[i] = dir.x
	dy[i] = dir.y
	dz[i] = dir.z
	speed[i] = bolt_speed
	left[i] = flight_range
	damage[i] = dmg
	style[i] = style_i
	kind[i] = KIND_BOLT


## Hurls a heavy ball: velocity vector (not unit), ballistic drop, then rolls along the table
## crushing everything it touches for `crush_dps` damage per second. flight_range limits the
## total distance travelled.
func fire_ball(origin: Vector3, velocity: Vector3, flight_range: float, crush_dps: float) -> void:
	var i: int = _next
	_next = (_next + 1) % CAP
	if alive[i] == 0:
		alive_count += 1
	alive[i] = 1
	px[i] = origin.x
	py[i] = origin.y
	pz[i] = origin.z
	dx[i] = velocity.x
	dy[i] = velocity.y
	dz[i] = velocity.z
	speed[i] = 1.0
	left[i] = flight_range
	damage[i] = crush_dps
	style[i] = ShotStyle.Style.SHELL
	kind[i] = KIND_BALL


## Advances every bolt and lands hits. Appends [x, y, z, style, killed] per impact to `impacts`
## (flat runs of 5). A bolt that exhausts its range dies without an impact entry. Hits are swept
## along the frame's flight segment, so a long frame cannot skip an enemy.
func tick(dt: float, swarm: Swarm, grid: SpatialGrid, economy: BattleEconomy, impacts: Array) -> void:
	if alive_count == 0:
		return
	for i in CAP:
		if alive[i] == 0:
			continue
		if kind[i] == KIND_BALL:
			_tick_ball(i, dt, swarm, grid, economy, impacts)
			continue
		var travel: float = speed[i] * dt
		if travel > left[i]:
			travel = left[i]
		# The segment flown this frame runs from the old position to the new one. Hits are swept
		# along it, so a long frame cannot carry a bolt clean through an enemy.
		var sx0: float = px[i]
		var sy0: float = py[i]
		var sz0: float = pz[i]
		px[i] += dx[i] * travel
		py[i] += dy[i] * travel
		pz[i] += dz[i] * travel
		left[i] -= travel
		var seg_x: float = px[i] - sx0
		var seg_y: float = py[i] - sy0
		var seg_z: float = pz[i] - sz0

		# Ground or range out: the bolt fizzles with a small impact so misses still read.
		var fizzled: bool = left[i] <= 0.0 or py[i] < -0.02

		var hit: int = -1
		var hit_t: float = 0.0   # where along the segment the hit lands: 0 = start, 1 = end
		if not fizzled and swarm.alive_count > 0:
			# Candidates from the grid cells that cover the whole segment: its midpoint, plus half
			# its length, plus the hit radius.
			var half_len: float = 0.5 * sqrt(seg_x * seg_x + seg_z * seg_z)
			_buf.clear()
			_buf = grid.collect(sx0 + seg_x * 0.5, sz0 + seg_z * 0.5, half_len + HIT_RADIUS * 2.0, _buf)
			hit = _first_contact(swarm, sx0, sy0, sz0, seg_x, seg_y, seg_z)
			hit_t = _hit_t
		if hit < 0 and not fizzled:
			continue

		alive[i] = 0
		alive_count -= 1
		var killed: bool = false
		# The impact sits where the bolt touched the enemy, or at its end when it only fizzled.
		var ix: float = px[i]
		var iy: float = py[i]
		var iz: float = pz[i]
		if hit >= 0:
			ix = sx0 + seg_x * hit_t
			iy = sy0 + seg_y * hit_t
			iz = sz0 + seg_z * hit_t
			killed = Combat.hit(swarm, hit, damage[i], economy)
		if hit >= 0 or left[i] <= 0.0 or py[i] < -0.02:
			impacts.append(ix)
			impacts.append(iy)
			impacts.append(iz)
			impacts.append(style[i])
			impacts.append(killed)


## Earliest enemy whose HIT_RADIUS sphere the frame's segment enters. Returns its slot, or -1.
## The entry fraction (0 = segment start, 1 = segment end) is left in _hit_t. Candidates are the
## grid entries in _buf. Ties go to the later candidate, as the point test did.
func _first_contact(swarm: Swarm, sx0: float, sy0: float, sz0: float, seg_x: float, seg_y: float, seg_z: float) -> int:
	var seg2: float = seg_x * seg_x + seg_y * seg_y + seg_z * seg_z
	var r2: float = HIT_RADIUS * HIT_RADIUS
	var best: int = -1
	var best_t: float = 2.0
	for k in _buf.size():
		var e: int = _buf[k]
		if swarm.alive[e] == 0:
			continue
		# Solve |start + t * seg - enemy|^2 = r^2 for its smallest root t.
		var fx: float = sx0 - swarm.x[e]
		var fy: float = sy0 - swarm.y[e]
		var fz: float = sz0 - swarm.z[e]
		var c: float = fx * fx + fy * fy + fz * fz - r2
		var t: float = 0.0
		if c > 0.0:
			# Starts outside the sphere, so the segment must reach in: a root in [0, 1] is the hit.
			if seg2 <= 1e-12:
				continue
			var hb: float = fx * seg_x + fy * seg_y + fz * seg_z
			var disc: float = hb * hb - seg2 * c
			if disc < 0.0:
				continue
			t = (-hb - sqrt(disc)) / seg2
			if t < 0.0 or t > 1.0:
				continue
		if t <= best_t:
			best_t = t
			best = e
	_hit_t = best_t
	return best


## One frame of a rolling ball: ballistic fall, floor roll with friction, continuous crush.
func _tick_ball(i: int, dt: float, swarm: Swarm, grid: SpatialGrid, economy: BattleEconomy, impacts: Array) -> void:
	dy[i] -= BALL_GRAVITY * dt
	px[i] += dx[i] * dt
	py[i] += dy[i] * dt
	pz[i] += dz[i] * dt
	var flat: float = sqrt(dx[i] * dx[i] + dz[i] * dz[i])
	if py[i] <= BALL_RADIUS:
		py[i] = BALL_RADIUS
		if dy[i] < 0.0:
			dy[i] = 0.0
		var drag: float = maxf(1.0 - BALL_FRICTION * dt, 0.0)
		dx[i] *= drag
		dz[i] *= drag
		flat *= drag
		# Track guidance: a ball rolling on the enemy roadway is gripped by its side rails
		# and steered along the lane like a bowling gutter, mowing down the column.
		_steer_on_track(i, swarm.path, dt, flat)
	left[i] -= flat * dt

	# Crush everything the ball touches; continuous dps melts small enemies on contact.
	if swarm.alive_count > 0:
		_buf.clear()
		_buf = grid.collect(px[i], pz[i], BALL_CRUSH_RADIUS, _buf)
		for k2 in _buf.size():
			Combat.hit(swarm, _buf[k2], damage[i] * dt, economy)

	if left[i] <= 0.0 or (py[i] <= BALL_RADIUS + 0.001 and flat < 0.08):
		alive[i] = 0
		alive_count -= 1
		impacts.append(px[i])
		impacts.append(py[i])
		impacts.append(pz[i])
		impacts.append(int(ShotStyle.Style.SHELL))
		impacts.append(false)


const TRACK_HALF: float = 0.16     # how far from the lane centre the rails still grip
const TRACK_STEER: float = 7.0     # how hard the rails bend the roll onto the lane

## Aligns a grounded ball's velocity with the nearest path segment when it is on the roadway,
## and nudges it toward the centre line. Rolls with the ball's own direction of travel.
func _steer_on_track(i: int, path: BattlePath, dt: float, flat: float) -> void:
	if flat < 0.05 or path == null:
		return
	var best_d2: float = TRACK_HALF * TRACK_HALF
	var tx: float = 0.0
	var tz: float = 0.0
	var cx_: float = 0.0
	var cz_: float = 0.0
	var found: bool = false
	for s in path.segment_count():
		var ax: float = path.vx[s]
		var az: float = path.vz[s]
		var bx: float = path.vx[s + 1]
		var bz: float = path.vz[s + 1]
		var ex: float = bx - ax
		var ez: float = bz - az
		var ll: float = ex * ex + ez * ez
		if ll < 1e-8:
			continue
		var t: float = clampf(((px[i] - ax) * ex + (pz[i] - az) * ez) / ll, 0.0, 1.0)
		var qx: float = ax + ex * t
		var qz: float = az + ez * t
		var ddx: float = px[i] - qx
		var ddz: float = pz[i] - qz
		var d2: float = ddx * ddx + ddz * ddz
		if d2 < best_d2:
			best_d2 = d2
			var inv: float = 1.0 / sqrt(ll)
			tx = ex * inv
			tz = ez * inv
			cx_ = qx
			cz_ = qz
			found = true
	if not found:
		return
	# Follow the tangent in whichever direction the ball is already rolling.
	if dx[i] * tx + dz[i] * tz < 0.0:
		tx = -tx
		tz = -tz
	var w: float = clampf(TRACK_STEER * dt, 0.0, 1.0)
	var want_x: float = tx * flat + (cx_ - px[i]) * 2.0
	var want_z: float = tz * flat + (cz_ - pz[i]) * 2.0
	var wl: float = sqrt(want_x * want_x + want_z * want_z)
	if wl < 1e-6:
		return
	dx[i] = lerpf(dx[i], want_x / wl * flat, w)
	dz[i] = lerpf(dz[i], want_z / wl * flat, w)
