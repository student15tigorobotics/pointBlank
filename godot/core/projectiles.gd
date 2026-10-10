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

var _buf: PackedInt32Array = PackedInt32Array()
var _next: int = 0


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


## Advances every bolt and lands hits. Appends [x, y, z, style, killed] per impact to `impacts`
## (flat runs of 5). A bolt that exhausts its range dies without an impact entry.
func tick(dt: float, swarm: Swarm, grid: SpatialGrid, economy: BattleEconomy, impacts: Array) -> void:
	if alive_count == 0:
		return
	for i in CAP:
		if alive[i] == 0:
			continue
		var travel: float = speed[i] * dt
		if travel > left[i]:
			travel = left[i]
		px[i] += dx[i] * travel
		py[i] += dy[i] * travel
		pz[i] += dz[i] * travel
		left[i] -= travel

		# Ground or range out: the bolt fizzles with a small impact so misses still read.
		var fizzled: bool = left[i] <= 0.0 or py[i] < -0.02

		var hit: int = -1
		if not fizzled and swarm.alive_count > 0:
			_buf.clear()
			_buf = grid.collect(px[i], pz[i], HIT_RADIUS * 2.0, _buf)
			var best: float = HIT_RADIUS * HIT_RADIUS
			for k in _buf.size():
				var e: int = _buf[k]
				var ex: float = swarm.x[e] - px[i]
				var ey: float = swarm.y[e] - py[i]
				var ez: float = swarm.z[e] - pz[i]
				var d2: float = ex * ex + ey * ey + ez * ez
				if d2 <= best:
					best = d2
					hit = e
		if hit < 0 and not fizzled:
			continue

		alive[i] = 0
		alive_count -= 1
		var killed: bool = false
		if hit >= 0:
			killed = Combat.hit(swarm, hit, damage[i], economy)
		if hit >= 0 or left[i] <= 0.0 or py[i] < -0.02:
			impacts.append(px[i])
			impacts.append(py[i])
			impacts.append(pz[i])
			impacts.append(style[i])
			impacts.append(killed)
