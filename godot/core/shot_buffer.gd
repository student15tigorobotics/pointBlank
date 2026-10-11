# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name ShotBuffer
extends RefCounted
## Preallocated flat buffer for one frame's attack visuals. Replaces the per-shot Dictionary
## (ShotStyle.make) that heap-allocated on every tower and weapon discharge — up to dozens a
## frame under fire, which was the game's main steady-state allocation churn (owner rule:
## efficiency first, preallocate everything).

const CAP: int = 128

var count: int = 0
var fx: PackedFloat32Array = PackedFloat32Array()
var fy: PackedFloat32Array = PackedFloat32Array()
var fz: PackedFloat32Array = PackedFloat32Array()
var tx: PackedFloat32Array = PackedFloat32Array()
var ty: PackedFloat32Array = PackedFloat32Array()
var tz: PackedFloat32Array = PackedFloat32Array()
var radius: PackedFloat32Array = PackedFloat32Array()
var style: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	fx.resize(CAP)
	fy.resize(CAP)
	fz.resize(CAP)
	tx.resize(CAP)
	ty.resize(CAP)
	tz.resize(CAP)
	radius.resize(CAP)
	style.resize(CAP)


func clear() -> void:
	count = 0


func size() -> int:
	return count


## Records one shot. Over-cap shots are dropped silently — they are visuals only.
func add(from: Vector3, to: Vector3, r: float, s: int) -> void:
	if count >= CAP:
		return
	fx[count] = from.x
	fy[count] = from.y
	fz[count] = from.z
	tx[count] = to.x
	ty[count] = to.y
	tz[count] = to.z
	radius[count] = r
	style[count] = s
	count += 1


func from_v(i: int) -> Vector3:
	return Vector3(fx[i], fy[i], fz[i])


func to_v(i: int) -> Vector3:
	return Vector3(tx[i], ty[i], tz[i])
