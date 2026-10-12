# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name AllySquad
extends RefCounted
## Drone allies: friendly fighters dropped onto the path, they march AGAINST the enemy flow
## (toward the spawn gate), brawling whatever they meet. An anti-enemy stream rather than a
## bullet or a tower. Engine-free SoA like Swarm; the view draws them from these arrays.

const CAP: int = 24
const SPEED: float = 0.22          # m/s marching toward the spawn gate
const DPS: float = 30.0            # melee damage per second to the enemy being fought
const HURT_PER_SECOND: float = 12.0  # damage an ally takes while brawling
const MAX_HP: float = 60.0
const REACH: float = 0.1           # fight-start distance, and the radius of an ally's stall
const STALL_MUL: float = 0.0       # speed multiplier for enemies within REACH of a live ally (0 = halted)
const STALL_SECONDS: float = 0.2   # outlives a frame, so the stall holds for as long as the ally stands

var alive_count: int = 0
var dist: PackedFloat32Array = PackedFloat32Array()   # along-path position, walks toward 0
var hp: PackedFloat32Array = PackedFloat32Array()
var x: PackedFloat32Array = PackedFloat32Array()
var z: PackedFloat32Array = PackedFloat32Array()
var heading: PackedFloat32Array = PackedFloat32Array()
var fighting: PackedByteArray = PackedByteArray()     # 1 while locked in melee (view: swing anim)
var alive: PackedByteArray = PackedByteArray()

var path: BattlePath
var _buf: PackedInt32Array = PackedInt32Array()


func _init(p: BattlePath) -> void:
	path = p
	dist.resize(CAP)
	hp.resize(CAP)
	x.resize(CAP)
	z.resize(CAP)
	heading.resize(CAP)
	fighting.resize(CAP)
	alive.resize(CAP)


## Drops `count` allies on the path at path-distance d (slightly staggered). Returns spawned.
func spawn_at(d: float, count: int) -> int:
	var made: int = 0
	for i in CAP:
		if made >= count:
			break
		if alive[i] == 1:
			continue
		alive[i] = 1
		alive_count += 1
		dist[i] = clampf(d + float(made) * 0.07, 0.05, path.length - 0.05)
		hp[i] = MAX_HP
		fighting[i] = 0
		_place(i)
		made += 1
	return made


## March, brawl, die. Enemies in reach get melee damage; the ally takes wear in return and
## stands still while fighting. Every enemy in reach is also stalled (swarm.slow), so a thick
## column jams behind the ally: bodies against bodies.
func tick(dt: float, swarm: Swarm, grid: SpatialGrid, economy: BattleEconomy) -> void:
	if alive_count == 0:
		return
	for i in CAP:
		if alive[i] == 0:
			continue
		# Find the closest live enemy in reach.
		_buf.clear()
		_buf = grid.collect(x[i], z[i], REACH, _buf)
		var target: int = -1
		var best: float = REACH * REACH
		for k in _buf.size():
			var e: int = _buf[k]
			if swarm.alive[e] == 0:
				continue
			# Every live enemy in reach is stalled, not only the one being fought: a body in the
			# way blocks the whole contact.
			swarm.slow(e, STALL_MUL, STALL_SECONDS)
			var dx: float = swarm.x[e] - x[i]
			var dz: float = swarm.z[e] - z[i]
			var d2: float = dx * dx + dz * dz
			if d2 <= best:
				best = d2
				target = e
		if target >= 0:
			fighting[i] = 1
			Combat.hit(swarm, target, DPS * dt, economy)
			hp[i] -= HURT_PER_SECOND * dt
			if hp[i] <= 0.0:
				alive[i] = 0
				alive_count -= 1
			continue
		fighting[i] = 0
		dist[i] -= SPEED * dt
		if dist[i] <= 0.03:
			# Reached the spawn gate with nothing left to fight: the ally retires.
			alive[i] = 0
			alive_count -= 1
			continue
		_place(i)


func _place(i: int) -> void:
	var seg: int = path.locate(dist[i])
	var p: Vector2 = path.position_on(seg, dist[i])
	var h: Vector2 = path.heading_of(seg)
	x[i] = p.x
	z[i] = p.y
	heading[i] = atan2(-h.x, -h.y)   # facing against the enemy flow
