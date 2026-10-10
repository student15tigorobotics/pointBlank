# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name Locomotion
extends RefCounted
## Two-handed "grab the world" movement for XR. Hold both grips to seize the world: moving
## both hands together drags it, twisting them yaws it, and changing the distance between
## them zooms (uniform scale, hands apart = zoom in). Click both thumbsticks to recenter.
##
## It transforms a world-root Node3D, never the player rig, so it never fights the headset's
## own tracking. The whole similarity (translate + yaw + scale) is glued to the two hands with
## one formula, so the world point under each hand stays under that hand until a clamp bites.

const GRIP_ON: float = 0.6        # grip must pass this to start a grab (hysteresis high edge)
const GRIP_OFF: float = 0.4       # grab ends when either grip drops below this
const MIN_SCALE: float = 0.25     # smallest the world may shrink to (player feels giant)
const MAX_SCALE: float = 5.0      # largest the world may grow to (player feels tiny)
const MAX_OFFSET: float = 8.0     # metres the world root may stray from home, per axis

var _left: XRController3D
var _right: XRController3D
var _world: Node3D
var _active: bool = false
var _recenter_down: bool = false

# Grab anchors, captured when both grips first close.
var _start_world: Transform3D = Transform3D.IDENTITY
var _c0: Vector3 = Vector3.ZERO   # hand midpoint at grab start (world)
var _d0: float = 1.0              # hand separation at grab start
var _a0: float = 0.0              # hand-line yaw at grab start


func _init(left: XRController3D, right: XRController3D, world: Node3D) -> void:
	_left = left
	_right = right
	_world = world


## Call every frame. Returns true while a grab is active, so the caller can swallow game input.
func update() -> bool:
	if _left == null or _right == null or _world == null:
		_active = false
		return false
	if not _hand_active(_left) or not _hand_active(_right):
		_active = false
		return false

	# Recenter on both thumbstick clicks (edge). Handy if a zoom or drag leaves the world adrift.
	var rc: bool = _left.is_button_pressed("primary_click") and _right.is_button_pressed("primary_click")
	if rc and not _recenter_down:
		_world.transform = Transform3D.IDENTITY
		_active = false
	_recenter_down = rc

	var lg: float = _left.get_float("grip")
	var rg: float = _right.get_float("grip")
	var both: bool = (lg > GRIP_OFF and rg > GRIP_OFF) if _active else (lg > GRIP_ON and rg > GRIP_ON)
	if not both:
		_active = false
		return false

	var pl: Vector3 = _left.global_transform.origin
	var pr: Vector3 = _right.global_transform.origin
	var c: Vector3 = (pl + pr) * 0.5
	var span: Vector3 = pr - pl
	var d: float = maxf(span.length(), 0.02)
	var a: float = atan2(span.x, span.z)

	if not _active:
		_active = true
		_start_world = _world.transform
		_c0 = c
		_d0 = d
		_a0 = a
		return true

	var s: float = d / _d0
	var dyaw: float = a - _a0
	var basis := Basis(Vector3.UP, dyaw).scaled(Vector3(s, s, s))
	var sim := Transform3D(basis, c - basis * _c0)
	_world.transform = _clamp(sim * _start_world)
	return true


## Cancels any grab in progress. Call when the scene changes under the player.
func reset() -> void:
	_active = false
	_recenter_down = false


func active() -> bool:
	return _active


## Keeps the world within scale and distance limits so a wild gesture can never lose it.
func _clamp(t: Transform3D) -> Transform3D:
	var scale: float = t.basis.get_scale().x
	if scale > 1e-5:
		var want: float = clampf(scale, MIN_SCALE, MAX_SCALE)
		if not is_equal_approx(want, scale):
			t.basis = t.basis.scaled(Vector3.ONE * (want / scale))
	var o: Vector3 = t.origin
	o.x = clampf(o.x, -MAX_OFFSET, MAX_OFFSET)
	o.y = clampf(o.y, -MAX_OFFSET, MAX_OFFSET)
	o.z = clampf(o.z, -MAX_OFFSET, MAX_OFFSET)
	t.origin = o
	return t


## A controller counts only while it is actually tracked, so a put-down hand cannot grab.
static func _hand_active(c: XRController3D) -> bool:
	if c.has_method("get_is_active"):
		return c.get_is_active()
	return true
