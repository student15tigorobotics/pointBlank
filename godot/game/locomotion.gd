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
## Two-handed "grab the world" movement for XR, modelled on SurfaceForge2's proven scheme.
## Hold both grips to seize the world: moving both hands together drags it, twisting them yaws
## it (rate-clamped for comfort), and changing the distance between them zooms (uniform scale).
## Click both thumbsticks to recenter.
##
## It transforms a world-root Node3D, never the player rig, so it never fights the headset's
## tracking. Per SF2's fix (owner 2026-10-10: midpoint-pivot drifted objects sideways and forced
## refocusing), zoom and yaw pivot about the VISOR/head camera, so whatever you look at stays on
## its gaze ray. Translation alone follows the hand midpoint, which is what a grab should feel like.

const GRIP_ON: float = 0.6        # grip must pass this to start a grab (hysteresis high edge)
const GRIP_OFF: float = 0.4       # grab ends when either grip drops below this
const MIN_SCALE: float = 0.25     # smallest the world may shrink to (player feels giant)
const MAX_SCALE: float = 5.0      # largest the world may grow to (player feels tiny)
const MAX_OFFSET: float = 8.0     # metres the world root may stray from home, per axis
const YAW_CLAMP: float = 0.14     # max world yaw per frame, radians (SF2 comfort limit)

var _left: XRController3D
var _right: XRController3D
var _world: Node3D
var _cam: Node3D                  # head camera; zoom and yaw pivot here
var _active: bool = false
var _recenter_down: bool = false

# Previous-frame gesture state, so each frame applies only its incremental change.
var _prev_mid: Vector3 = Vector3.ZERO
var _prev_dist: float = 1.0
var _prev_yaw: float = 0.0


func _init(left: XRController3D, right: XRController3D, world: Node3D, cam: Node3D) -> void:
	_left = left
	_right = right
	_world = world
	_cam = cam


## Call every frame. Returns true while a grab is active, so the caller can swallow game input.
func update() -> bool:
	if _left == null or _right == null or _world == null:
		_active = false
		return false
	if not _hand_active(_left) or not _hand_active(_right):
		_active = false
		return false

	# Recenter on both thumbstick clicks (edge). Rescues the world if a gesture leaves it adrift.
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
	var mid: Vector3 = (pl + pr) * 0.5
	var span: Vector3 = pr - pl
	var dist: float = maxf(span.length(), 0.02)
	var yaw: float = atan2(span.x, span.z)

	if not _active:
		_active = true
		_prev_mid = mid
		_prev_dist = dist
		_prev_yaw = yaw
		_pulse()
		return true

	# Translation: the grabbed world follows the hands.
	_world.global_position += mid - _prev_mid

	var pivot: Vector3 = _cam.global_position if _cam != null else mid

	# Zoom: incremental factor, clamped so the world can never be lost, pivoting on the head.
	var cur_scale: float = _world.global_transform.basis.get_scale().x
	if cur_scale > 1e-5:
		var want: float = clampf(cur_scale * (dist / _prev_dist), MIN_SCALE, MAX_SCALE)
		_scale_about(want / cur_scale, pivot)

	# Yaw: twist both hands to turn, rate-limited so it can't whip the view.
	var dyaw: float = clampf(wrapf(yaw - _prev_yaw, -PI, PI), -YAW_CLAMP, YAW_CLAMP)
	if absf(dyaw) > 0.0001:
		_yaw_about(dyaw, pivot)

	_clamp_offset()
	_prev_mid = mid
	_prev_dist = dist
	_prev_yaw = yaw
	return true


## Cancels any grab in progress. Call when the scene changes under the player.
func reset() -> void:
	_active = false
	_recenter_down = false


func active() -> bool:
	return _active


## Scales the world by f about a world-space pivot (x' = pivot + f * (x - pivot)).
func _scale_about(f: float, pivot: Vector3) -> void:
	var s := Transform3D(Basis().scaled(Vector3(f, f, f)), pivot * (1.0 - f))
	_world.global_transform = s * _world.global_transform


## Rotates the world by angle about the vertical axis through a world-space pivot.
func _yaw_about(angle: float, pivot: Vector3) -> void:
	var r := Basis(Vector3.UP, angle)
	var t := Transform3D(r, pivot - r * pivot)
	_world.global_transform = t * _world.global_transform


## Keeps the world root within reach so it cannot be dragged out of sight.
func _clamp_offset() -> void:
	var t: Transform3D = _world.transform
	t.origin.x = clampf(t.origin.x, -MAX_OFFSET, MAX_OFFSET)
	t.origin.y = clampf(t.origin.y, -MAX_OFFSET, MAX_OFFSET)
	t.origin.z = clampf(t.origin.z, -MAX_OFFSET, MAX_OFFSET)
	_world.transform = t


## A short dual pulse marks the moment a grab takes hold, as SF2 does on zoom start.
func _pulse() -> void:
	if _left.has_method("trigger_haptic_pulse"):
		_left.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.02, 0.0)
		_right.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.02, 0.0)


## A controller counts only while it is actually tracked, so a put-down hand cannot grab.
static func _hand_active(c: XRController3D) -> bool:
	if c.has_method("get_is_active"):
		return c.get_is_active()
	return true
