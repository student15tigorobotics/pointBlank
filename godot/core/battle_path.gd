# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name BattlePath
extends RefCounted
## Polyline the swarm walks along, in table-local XZ meters. Port of BattlePath.cs.

var length: float = 0.0
var vx: PackedFloat32Array = PackedFloat32Array()   # vertex x
var vz: PackedFloat32Array = PackedFloat32Array()   # vertex z
var cum: PackedFloat32Array = PackedFloat32Array()  # cumulative arc length at each vertex


## xz: x,z pairs. Needs at least two points.
func _init(xz: PackedFloat32Array) -> void:
	var n: int = xz.size() >> 1
	assert(n >= 2, "A path needs at least two points.")
	vx.resize(n)
	vz.resize(n)
	cum.resize(n)
	for i in range(n):
		vx[i] = xz[i * 2]
		vz[i] = xz[i * 2 + 1]
	for i in range(1, n):
		var dx: float = vx[i] - vx[i - 1]
		var dz: float = vz[i] - vz[i - 1]
		cum[i] = cum[i - 1] + sqrt(dx * dx + dz * dz)
	length = cum[n - 1]


func start() -> Vector3:
	return Vector3(vx[0], 0.0, vz[0])


func end() -> Vector3:
	var last: int = vx.size() - 1
	return Vector3(vx[last], 0.0, vz[last])


func segment_count() -> int:
	return vx.size() - 1


## Segment index for arc length d, clamped to [0, segment_count() - 1].
## Smallest i with cum[i + 1] >= d, same rule as the C# linear scan.
func locate(d: float) -> int:
	var lo: int = 0
	var hi: int = vx.size() - 2
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if cum[mid + 1] < d:
			lo = mid + 1
		else:
			hi = mid
	return lo


## Point (x, z) on segment seg at arc length d. d below the segment start extrapolates
## along the segment heading (used for d < 0 on the first segment).
func position_on(seg: int, d: float) -> Vector2:
	var h: Vector2 = heading_of(seg)
	if d < cum[seg]:
		var back: float = d - cum[seg]
		return Vector2(vx[seg] + h.x * back, vz[seg] + h.y * back)
	var seg_len: float = cum[seg + 1] - cum[seg]
	var t: float = 0.0
	if seg_len > 1e-6:
		t = (d - cum[seg]) / seg_len
	return Vector2(vx[seg] + (vx[seg + 1] - vx[seg]) * t, vz[seg] + (vz[seg + 1] - vz[seg]) * t)


## Unit xz direction of segment seg. Degenerate segments give (0, 1), as in C#.
func heading_of(seg: int) -> Vector2:
	var dx: float = vx[seg + 1] - vx[seg]
	var dz: float = vz[seg + 1] - vz[seg]
	var l: float = sqrt(dx * dx + dz * dz)
	if l > 1e-6:
		return Vector2(dx / l, dz / l)
	return Vector2(0.0, 1.0)


## Shortest XZ distance from a point to any segment of the path.
func distance_to(x: float, z: float) -> float:
	var best: float = INF
	var n: int = vx.size()
	for i in range(n - 1):
		var ax: float = vx[i]
		var az: float = vz[i]
		var ex: float = vx[i + 1] - ax
		var ez: float = vz[i + 1] - az
		var len2: float = ex * ex + ez * ez
		var t: float = 0.0
		if len2 > 1e-9:
			t = clampf(((x - ax) * ex + (z - az) * ez) / len2, 0.0, 1.0)
		var cx: float = ax + ex * t - x
		var cz: float = az + ez * t - z
		var d: float = sqrt(cx * cx + cz * cz)
		if d < best:
			best = d
	return best
