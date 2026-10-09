# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name SpatialGrid
extends RefCounted
## Uniform XZ grid over [-EXTENT, EXTENT]^2 with CELL-sized cells. New in the GDScript port
## (the C# battle used brute-force scans). Rebuilt once per frame from the swarm by a counting sort
## into packed arrays. After the first build, rebuilds allocate nothing.
##
## Cell c holds enemies at cell_items[cell_start[c] .. cell_start[c + 1] - 1].
## cell_x / cell_z hold the positions as of the last rebuild, aligned with cell_items.

const CELL: float = 0.25
const EXTENT: float = 2.0
const SIDE: int = 16   # cells per axis = 2 * EXTENT / CELL

var cell_start: PackedInt32Array = PackedInt32Array()   # SIDE * SIDE + 1 entries
var cell_items: PackedInt32Array = PackedInt32Array()   # enemy slot indices, grouped by cell
var cell_x: PackedFloat32Array = PackedFloat32Array()   # snapshot x, aligned with cell_items
var cell_z: PackedFloat32Array = PackedFloat32Array()   # snapshot z, aligned with cell_items

var _swarm: Swarm = null
var _cell_of: PackedInt32Array = PackedInt32Array()     # per-slot cell id scratch, -1 when dead
var _cursor: PackedInt32Array = PackedInt32Array()


## Rebuilds the grid from the alive enemies. Call after Swarm.step each frame.
func rebuild(swarm: Swarm) -> void:
	_swarm = swarm
	var cells: int = SIDE * SIDE
	var cap: int = swarm.capacity
	if cell_start.size() != cells + 1:
		cell_start.resize(cells + 1)
		_cursor.resize(cells)
	if _cell_of.size() != cap:
		_cell_of.resize(cap)
		cell_items.resize(cap)
		cell_x.resize(cap)
		cell_z.resize(cap)

	cell_start.fill(0)
	var alive: PackedByteArray = swarm.alive
	var xs: PackedFloat32Array = swarm.x
	var zs: PackedFloat32Array = swarm.z
	var high: int = swarm.high_water

	# Pass 1: count per cell.
	for i in range(high):
		if alive[i] == 0:
			_cell_of[i] = -1
			continue
		var c: int = _cell_id(xs[i], zs[i])
		_cell_of[i] = c
		cell_start[c + 1] += 1

	# Prefix sums: cell_start[c] becomes the first index of cell c.
	for c in range(cells):
		cell_start[c + 1] += cell_start[c]
	for c in range(cells):
		_cursor[c] = cell_start[c]

	# Pass 2: scatter.
	for i in range(high):
		var cid: int = _cell_of[i]
		if cid < 0:
			continue
		var k: int = _cursor[cid]
		_cursor[cid] = k + 1
		cell_items[k] = i
		cell_x[k] = xs[i]
		cell_z[k] = zs[i]


## Appends the slots within XZ radius of (x, z), using positions as of the last rebuild.
## Dead slots (killed since the rebuild) are skipped. Returns the array with hits appended.
## PackedInt32Array is passed by value, so callers must assign the result: buf = grid.collect(..., buf).
func collect(x: float, z: float, radius: float, into: PackedInt32Array) -> PackedInt32Array:
	if _swarm == null:
		return into
	var alive: PackedByteArray = _swarm.alive
	var r2: float = radius * radius
	var cx0: int = _axis(x - radius)
	var cx1: int = _axis(x + radius)
	var cz0: int = _axis(z - radius)
	var cz1: int = _axis(z + radius)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var c: int = cz * SIDE + cx
			for k in range(cell_start[c], cell_start[c + 1]):
				var dx: float = cell_x[k] - x
				var dz: float = cell_z[k] - z
				if dx * dx + dz * dz <= r2:
					var i: int = cell_items[k]
					if alive[i] != 0:
						into.append(i)
	return into


## Nearest alive enemy within reach of (x, z), using current swarm positions for distance.
## Returns -1 if none. Ties go to the higher slot index, as in Combat.nearest_in_range.
func nearest(swarm: Swarm, x: float, z: float, reach: float) -> int:
	var reach2: float = reach * reach
	var best_d2: float = reach2
	var found: int = -1
	var alive: PackedByteArray = swarm.alive
	var xs: PackedFloat32Array = swarm.x
	var zs: PackedFloat32Array = swarm.z
	var cx0: int = _axis(x - reach)
	var cx1: int = _axis(x + reach)
	var cz0: int = _axis(z - reach)
	var cz1: int = _axis(z + reach)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var c: int = cz * SIDE + cx
			for k in range(cell_start[c], cell_start[c + 1]):
				var i: int = cell_items[k]
				if alive[i] == 0:
					continue
				var dx: float = xs[i] - x
				var dz: float = zs[i] - z
				var d2: float = dx * dx + dz * dz
				if d2 > reach2:
					continue
				if found < 0 or d2 < best_d2 or (d2 == best_d2 and i > found):
					best_d2 = d2
					found = i
	return found


## Clamped cell index along one axis. Monotone, so cells covering a query range always cover
## every enemy inside that range, including enemies that sit outside the grid.
static func _axis(v: float) -> int:
	var c: int = int(floor((v + EXTENT) / CELL))
	return clampi(c, 0, SIDE - 1)


static func _cell_id(px: float, pz: float) -> int:
	return _axis(pz) * SIDE + _axis(px)
