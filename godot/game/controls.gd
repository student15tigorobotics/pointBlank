# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name Controls
extends RefCounted
## Unifies VIVE XR Elite / Focus 3 controllers and desktop mouse and keyboard into per-frame intents.
## Port of Game/Controls.cs with the Focus 3 click fix from the game contract addendum:
## - every hand keeps its own previous state; nothing is shared between hands,
## - a trigger is pressed when value > 0.6 or its *_click is true, released when value < 0.35 and click is false (hysteresis),
## - edges are "pressed this frame and not last frame".

const TRIGGER_PRESS: float = 0.6
const TRIGGER_RELEASE: float = 0.35
const GRIP_HELD: float = 0.5
const STICK_ARM: float = 0.3

var xr: bool = false
var left: XRController3D = null
var right: XRController3D = null
var desk: Camera3D = null

var left_ptr: Pointer = Pointer.new()
var right_ptr: Pointer = Pointer.new()
var mouse_ptr: Pointer = Pointer.new()

# Held intents
var fire: bool = false          # right trigger held (XR) / left mouse held (desktop)
var fire_left: bool = false     # left trigger held (XR; both hands are always weapons)
var sell: bool = false          # left grip held (XR) / shift held (desktop)

# Lemming tool (right A/B, click edge or touch-tap) and selectors.
var lemming_explode: bool = false   # right A: detonate every deployed lemming
var lemming_deploy: bool = false    # right B: release a squad from the core end
var weapon_step_right: int = 0      # right stick X: right-hand weapon cycle

# Edge intents, true for the one frame they occur
var press_right: bool = false   # right trigger edge, UI press for the right pointer
var press_left: bool = false    # left trigger edge, UI press for the left pointer
var press_mouse: bool = false   # desktop left mouse edge, UI press for the mouse pointer
var place: bool = false         # left trigger edge (XR) / middle mouse edge (desktop)
var upgrade: bool = false       # right B/Y edge (XR) / right mouse edge (desktop)
var call_wave: bool = false     # left B/Y edge (XR) / G (desktop)
var advance: bool = false       # right A/X edge (XR) / Space or Enter (desktop)
var menu: bool = false          # left menu edge (XR) / Escape (desktop)

var tower_step: int = 0         # -1, 0 or 1 (left stick X / Q, E)
var weapon_step: int = 0        # -1, 0 or 1 (right stick X / R, F)

# Per-hand state
var _right_trigger_down: bool = false
var _left_trigger_down: bool = false
var _right_by_down: bool = false
var _right_ax_down: bool = false
var _left_ax_down: bool = false
var _left_by_down: bool = false
var _left_menu_down: bool = false
var _left_stick_armed: bool = true      # left stick X (left weapon cycle)
var _left_stick_y_armed: bool = true    # left stick Y (tower cycle)
var _right_stick_armed: bool = true     # right stick X (right weapon cycle)
var _left_face_touch_down: bool = false
var _ra_touch_down: bool = false
var _rb_touch_down: bool = false
var _ra_touch_ms: int = 0
var _rb_touch_ms: int = 0

const TAP_MS: int = 350

# Desktop state
var _mouse_left_down: bool = false
var _mouse_middle_down: bool = false
var _mouse_right_down: bool = false
var _space_down: bool = false
var _g_down: bool = false
var _esc_down: bool = false
var _q_down: bool = false
var _e_down: bool = false
var _r_down: bool = false
var _f_down: bool = false

# Cached return values for ui_pointers() / ui_presses(), so the per-frame call does not allocate.
var _xr_pointers: Array = []
var _desk_pointers: Array = []
var _xr_presses: Array = [false, false]
var _desk_presses: Array = [false]


func _init() -> void:
	_xr_pointers = [right_ptr, left_ptr]
	_desk_pointers = [mouse_ptr]


func poll(viewport: Viewport) -> void:
	place = false
	upgrade = false
	call_wave = false
	advance = false
	menu = false
	lemming_explode = false
	lemming_deploy = false
	press_right = false
	press_left = false
	press_mouse = false
	tower_step = 0
	weapon_step = 0
	weapon_step_right = 0
	if _use_xr():
		_poll_xr()
	else:
		_poll_desktop(viewport)


func aim_pointer() -> Pointer:
	return right_ptr if _use_xr() else mouse_ptr


func place_pointer() -> Pointer:
	return left_ptr if _use_xr() else mouse_ptr


## [right, left] in XR, [mouse] on desktop. Same order as ui_presses().
func ui_pointers() -> Array:
	return _xr_pointers if _use_xr() else _desk_pointers


## [press_right, press_left] in XR, [press_mouse] on desktop. presses[i] belongs to ui_pointers()[i].
func ui_presses() -> Array:
	return _xr_presses if _use_xr() else _desk_presses


func _use_xr() -> bool:
	return xr and left != null and right != null


func _poll_xr() -> void:
	_set_pointer(left_ptr, left)
	_set_pointer(right_ptr, right)

	# Both triggers are always weapons (owner control model 2026-10-11).
	var r_down: bool = _trigger_down(_right_trigger_down, right.get_float("trigger"), right.is_button_pressed("trigger_click"))
	press_right = r_down and not _right_trigger_down
	_right_trigger_down = r_down
	fire = r_down

	var l_down: bool = _trigger_down(_left_trigger_down, left.get_float("trigger"), left.is_button_pressed("trigger_click"))
	press_left = l_down and not _left_trigger_down
	_left_trigger_down = l_down
	fire_left = l_down

	# Tower placement: left X or Y, accepting click OR touch edges because the Wave runtime
	# swallows face-button clicks on some firmware. A resting thumb costs one spurious edge.
	var l_face_click: bool = left.is_button_pressed("ax_button") or left.is_button_pressed("by_button")
	var l_face_touch: bool = left.is_button_pressed("ax_touch") or left.is_button_pressed("by_touch")
	place = (l_face_click and not _left_ax_down) or (l_face_touch and not _left_face_touch_down)
	_left_ax_down = l_face_click
	_left_face_touch_down = l_face_touch

	# Lemming tool on the right face buttons: A detonates, B deploys from the core end.
	# Click edge fires immediately; a touch counts only as a quick TAP (press->release under
	# 350 ms), so a thumb resting on A can never nuke the lemmings by itself.
	var now: int = Time.get_ticks_msec()
	var r_ax: bool = right.is_button_pressed("ax_button")
	advance = r_ax and not _right_ax_down      # dialogue NEXT shares A; states never overlap
	lemming_explode = r_ax and not _right_ax_down
	_right_ax_down = r_ax
	var r_a_touch: bool = right.is_button_pressed("ax_touch")
	if r_a_touch and not _ra_touch_down:
		_ra_touch_ms = now
	elif not r_a_touch and _ra_touch_down and now - _ra_touch_ms < TAP_MS:
		lemming_explode = true
	_ra_touch_down = r_a_touch

	var r_by: bool = right.is_button_pressed("by_button")
	lemming_deploy = r_by and not _right_by_down
	_right_by_down = r_by
	var r_b_touch: bool = right.is_button_pressed("by_touch")
	if r_b_touch and not _rb_touch_down:
		_rb_touch_ms = now
	elif not r_b_touch and _rb_touch_down and now - _rb_touch_ms < TAP_MS:
		lemming_deploy = true
	_rb_touch_down = r_b_touch

	sell = left.get_float("grip") > GRIP_HELD or left.is_button_pressed("grip_click")

	var l_menu: bool = left.is_button_pressed("menu_button")
	menu = l_menu and not _left_menu_down
	_left_menu_down = l_menu

	# Left stick: X cycles the LEFT hand's weapon, Y cycles the tower. Dominant axis wins.
	var lv: Vector2 = left.get_vector2("primary")
	if absf(lv.x) >= absf(lv.y):
		var wx: Vector2i = _stick_step(lv.x, _left_stick_armed)
		weapon_step = wx.x
		_left_stick_armed = wx.y == 1
		_left_stick_y_armed = _left_stick_y_armed or absf(lv.y) < STICK_ARM
	else:
		var ty: Vector2i = _stick_step(lv.y, _left_stick_y_armed)
		tower_step = ty.x
		_left_stick_y_armed = ty.y == 1
		_left_stick_armed = _left_stick_armed or absf(lv.x) < STICK_ARM

	# Right stick X cycles the RIGHT hand's weapon (hands carry different weapons now).
	var rs: Vector2i = _stick_step(right.get_vector2("primary").x, _right_stick_armed)
	weapon_step_right = rs.x
	_right_stick_armed = rs.y == 1

	# An untracked pointer is invalid, so its press must not reach the UI either.
	_xr_presses[0] = press_right and right_ptr.valid
	_xr_presses[1] = press_left and left_ptr.valid


func _poll_desktop(viewport: Viewport) -> void:
	if desk != null:
		var m: Vector2 = viewport.get_mouse_position()
		mouse_ptr.origin = desk.project_ray_origin(m)
		mouse_ptr.dir = desk.project_ray_normal(m)
		mouse_ptr.valid = true

	var ml: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var mm: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	var mr: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	fire = ml
	fire_left = false
	sell = Input.is_key_pressed(KEY_SHIFT)
	press_mouse = ml and not _mouse_left_down
	_mouse_left_down = ml
	place = mm and not _mouse_middle_down
	_mouse_middle_down = mm
	upgrade = mr and not _mouse_right_down
	_mouse_right_down = mr

	var space: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER)
	advance = space and not _space_down
	_space_down = space

	var g: bool = Input.is_key_pressed(KEY_G)
	call_wave = g and not _g_down
	_g_down = g

	var esc: bool = Input.is_key_pressed(KEY_ESCAPE)
	menu = esc and not _esc_down
	_esc_down = esc

	var e: bool = Input.is_key_pressed(KEY_E)
	if e and not _e_down:
		tower_step = 1
	_e_down = e
	var q: bool = Input.is_key_pressed(KEY_Q)
	if q and not _q_down:
		tower_step = -1
	_q_down = q

	var f: bool = Input.is_key_pressed(KEY_F)
	if f and not _f_down:
		weapon_step = 1
	_f_down = f
	var r: bool = Input.is_key_pressed(KEY_R)
	if r and not _r_down:
		weapon_step = -1
	_r_down = r

	_desk_presses[0] = press_mouse


## Trigger with hysteresis: pressed above 0.6 or on click; released only below 0.35 with no click; otherwise unchanged.
static func _trigger_down(was_down: bool, value: float, click: bool) -> bool:
	if value > TRIGGER_PRESS or click:
		return true
	if value < TRIGGER_RELEASE:
		return false
	return was_down


## Returns Vector2i(step, armed_after). The stick must return inside the dead zone before it can step again.
static func _stick_step(x: float, armed: bool) -> Vector2i:
	if absf(x) < STICK_ARM:
		return Vector2i(0, 1)
	if not armed:
		return Vector2i(0, 0)
	return Vector2i(1 if x > 0.0 else -1, 0)


## Copies the controller pose into the pointer. The pointer is valid only while the controller is tracked,
## so a lost or put-down controller gives no ray and no hover.
static func _set_pointer(p: Pointer, c: XRController3D) -> void:
	var t: Transform3D = c.global_transform
	p.origin = t.origin
	p.dir = -t.basis.z
	p.valid = _controller_active(c)


## XRController3D.get_is_active() reports whether the controller is tracked. Defaults to true if the method is missing.
static func _controller_active(c: XRController3D) -> bool:
	if c.has_method("get_is_active"):
		return c.get_is_active()
	return true
