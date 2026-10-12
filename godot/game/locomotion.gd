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
## it (rate-limited in degrees per second for comfort), and changing the distance between them
## zooms (uniform scale). Click both thumbsticks to recenter.
##
## It transforms a world-root Node3D, never the player rig, so it never fights the headset's
## tracking. Zoom and yaw pivot on the point between the two hands, which is the grab itself
## (owner preference 2026-10-10, after trying a head-camera pivot); translation follows that point.
## While a battle table is in the world, a grab cannot leave it over the player: its footprint
## stays at least TABLE_GAP metres from the head in XZ, and its underside stays above the floor.

const GRIP_ON: float = 0.6        # grip must pass this to start a grab (hysteresis high edge)
const GRIP_OFF: float = 0.4       # grab ends when either grip drops below this
const MIN_SCALE: float = 0.5      # smallest the world may shrink to
const MAX_SCALE: float = 1.5      # largest the world may grow to
const ZOOM_STEP_MAX: float = 1.1  # largest zoom factor per frame, and its inverse for shrinking
const DIST_MIN: float = 0.15      # hand separation used for zoom gain never drops below this, metres
const MAX_OFFSET: float = 8.0     # metres the world root may stray from home, per axis
const YAW_RATE_MAX: float = 577.0 # max world yaw, degrees per second (0.14 rad per frame at 72 Hz)
const MAX_DT: float = 0.1         # frame time used for the yaw rate is capped, so a hitch cannot whip the view
const TABLE_HALF: float = 1.6     # battle table top is 3.2 m square (battle_view.gd)
const TABLE_UNDERSIDE: float = -0.06  # bottom of the table slab, relative to the battle view origin
const TABLE_GAP: float = 0.6      # clearance kept between the head and the table footprint, metres

var _left: XRController3D
var _right: XRController3D
var _world: Node3D
var _cam: Node3D                  # head camera; the table must keep clear of it
var _active: bool = false
var _recenter_down: bool = false
var _last_usec: int = 0           # clock at the previous update(), for the yaw rate limit

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
	var dt: float = _frame_dt()
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
	var dist: float = maxf(span.length(), DIST_MIN)
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

	# Zoom/yaw pivot on the point between the two hands — the grab itself (owner preference
	# 2026-10-10 after trying head-pivot: "move by user visor center is not good").
	var pivot: Vector3 = mid

	# Zoom: incremental factor, capped per frame and clamped in scale, pivoting on the grab point.
	var cur_scale: float = _world.global_transform.basis.get_scale().x
	if cur_scale > 1e-5:
		var step: float = clampf(dist / _prev_dist, 1.0 / ZOOM_STEP_MAX, ZOOM_STEP_MAX)
		var want: float = clampf(cur_scale * step, MIN_SCALE, MAX_SCALE)
		_scale_about(want / cur_scale, pivot)

	# Yaw: twist both hands to turn, rate-limited in degrees per second so it feels the same at any refresh rate.
	var max_step: float = deg_to_rad(YAW_RATE_MAX) * dt
	var dyaw: float = clampf(wrapf(yaw - _prev_yaw, -PI, PI), -max_step, max_step)
	if absf(dyaw) > 0.0001:
		_yaw_about(dyaw, pivot)

	_clamp_offset()
	_clamp_table()
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


## Keeps the battle table out of the player's way. Its footprint (the 3.2 m square top) stays at
## least TABLE_GAP from the head in XZ, and its underside stays at or above the floor. Only the
## world root moves, so the table keeps the scale and yaw the grab gave it. No table, no clamp.
func _clamp_table() -> void:
	var table: Node3D = _find_table()
	if table == null or _cam == null:
		return
	var tx: Transform3D = _world.global_transform * table.transform
	var s: float = tx.basis.x.length()
	if s < 1e-5:
		return
	# Table axes in XZ. Yaw only, so these stay horizontal and orthonormal.
	var ax: Vector3 = Vector3(tx.basis.x.x, 0.0, tx.basis.x.z).normalized()
	var az: Vector3 = Vector3(tx.basis.z.x, 0.0, tx.basis.z.z).normalized()
	var half: float = TABLE_HALF * s
	# Head position in table axes: u along ax, v along az.
	var rel: Vector3 = _cam.global_position - tx.origin
	var u: float = rel.dot(ax)
	var v: float = rel.dot(az)

	# Horizontal shift of the table, in table axes, that restores the clearance.
	var du: float = u - clampf(u, -half, half)
	var dv: float = v - clampf(v, -half, half)
	var d: float = sqrt(du * du + dv * dv)
	var shift: Vector2 = Vector2.ZERO
	if d > 0.0:
		if d < TABLE_GAP:
			# Head outside the footprint but too close: push the table straight away from it.
			shift = Vector2(du, dv) * (-(TABLE_GAP - d) / d)
	else:
		# Head under the table: slide it out through the edge that needs the least movement.
		var reach: float = half + TABLE_GAP
		var cands: Array[Vector2] = [
			Vector2(u - reach, 0.0), Vector2(u + reach, 0.0),
			Vector2(0.0, v - reach), Vector2(0.0, v + reach),
		]
		shift = cands[0]
		for c in cands:
			if c.length() < shift.length():
				shift = c

	var move: Vector3 = ax * shift.x + az * shift.y
	# Vertical: lift the world just enough that the table's underside is not below the floor.
	var under: float = (tx * Vector3(0.0, TABLE_UNDERSIDE, 0.0)).y
	move.y = maxf(0.0, -under)
	if move != Vector3.ZERO:
		_world.global_position += move


## The battle table, when one is in the world root. BattleView is the only table.
func _find_table() -> Node3D:
	for child in _world.get_children():
		if child is BattleView:
			return child as Node3D
	return null


## Seconds since the previous update(), capped at MAX_DT. Measured here so the caller's call stays as it is.
func _frame_dt() -> float:
	var now: int = Time.get_ticks_usec()
	var dt: float = 0.0
	if _last_usec > 0:
		dt = clampf(float(now - _last_usec) * 0.000001, 0.0, MAX_DT)
	_last_usec = now
	return dt


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
