# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name CoreMath
extends RefCounted
## Engine-free math helpers. Port of V3.RayDistance.


## Distance from point p to the ray (origin o, unit direction d), with t clamped to >= 0.
## Returns [distance: float, t: float].
static func ray_point_distance(o: Vector3, d: Vector3, p: Vector3) -> Array:
	var op: Vector3 = p - o
	var t: float = maxf(0.0, op.dot(d))
	var closest: Vector3 = o + d * t
	return [(p - closest).length(), t]
