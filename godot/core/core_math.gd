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
