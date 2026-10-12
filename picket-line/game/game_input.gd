# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name GameInput
extends Node
## Keyboard, mouse and gamepad state, turned into the command dictionary that Sim.step reads.
## Actions are registered in code by install(), so the project needs no input map entries.

const DEADZONE := 0.18
const MOUSE_RAD_PER_PX := 0.0022
const STICK_RAD_PER_S := 2.4
const DOUBLE_TAP_MS := 260
const SCOPE_AIM_SCALE := 0.45
const DODGE_DOUBLE_TAP := 0

var _mouse_delta := Vector2.ZERO
var _last_left_ms := -100000
var _last_right_ms := -100000


static func install() -> void:
	_add("fire", [_mouse_button(MOUSE_BUTTON_LEFT), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_add("scope", [_mouse_button(MOUSE_BUTTON_RIGHT), _joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_add("focus", [_key(KEY_Q), _joy_button(JOY_BUTTON_LEFT_SHOULDER)])
	_add("dodge", [_key(KEY_SHIFT), _joy_button(JOY_BUTTON_RIGHT_SHOULDER)])
	_add("move_left", [_key(KEY_A), _joy_axis(JOY_AXIS_LEFT_X, -1.0)])
	_add("move_right", [_key(KEY_D), _joy_axis(JOY_AXIS_LEFT_X, 1.0)])
	_add("rail_up", [_key(KEY_W), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add("rail_down", [_key(KEY_S), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add("weapon_1", [_key(KEY_1)])
	_add("weapon_2", [_key(KEY_2)])
	_add("weapon_3", [_key(KEY_3)])
	_add("weapon_4", [_key(KEY_4)])
	_add("cycle_next", [_mouse_button(MOUSE_BUTTON_WHEEL_UP), _key(KEY_E), _joy_button(JOY_BUTTON_DPAD_RIGHT)])
	_add("cycle_prev", [_mouse_button(MOUSE_BUTTON_WHEEL_DOWN), _key(KEY_R), _joy_button(JOY_BUTTON_DPAD_LEFT)])
	_add("pause", [_key(KEY_ESCAPE), _joy_button(JOY_BUTTON_START)])


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += (event as InputEventMouseMotion).relative


## Builds the command for this frame. Call once per played frame; mouse motion is consumed here.
func poll(dt: float, settings: Dictionary) -> Dictionary:
	var sens := float(settings.get("sensitivity", 1.0))
	var invert := -1.0 if bool(settings.get("invert_y", false)) else 1.0
	var scope := Input.is_action_pressed("scope")
	var scope_scale := SCOPE_AIM_SCALE if scope else 1.0
	var mouse_k := MOUSE_RAD_PER_PX * sens * scope_scale
	var yaw := -_mouse_delta.x * mouse_k
	var pitch := -_mouse_delta.y * mouse_k * invert
	_mouse_delta = Vector2.ZERO
	var stick_rate := STICK_RAD_PER_S * sens * scope_scale * dt
	yaw -= _stick(JOY_AXIS_RIGHT_X) * stick_rate
	pitch -= _stick(JOY_AXIS_RIGHT_Y) * stick_rate * invert

	var move_x := Input.get_axis("move_left", "move_right")
	var dodge_dir := move_x if absf(move_x) > 0.2 else 1.0
	var dodge_pressed := Input.is_action_just_pressed("dodge")
	if int(settings.get("dodge_mode", DODGE_DOUBLE_TAP)) == DODGE_DOUBLE_TAP:
		var now := Time.get_ticks_msec()
		if Input.is_action_just_pressed("move_left"):
			if now - _last_left_ms < DOUBLE_TAP_MS:
				dodge_pressed = true
				dodge_dir = -1.0
			_last_left_ms = now
		if Input.is_action_just_pressed("move_right"):
			if now - _last_right_ms < DOUBLE_TAP_MS:
				dodge_pressed = true
				dodge_dir = 1.0
			_last_right_ms = now

	var select := -1
	for i in 4:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			select = i
	var cycle := 0
	if Input.is_action_just_pressed("cycle_next"):
		cycle += 1
	if Input.is_action_just_pressed("cycle_prev"):
		cycle -= 1

	return {
		"aim": Vector2(yaw, pitch),
		"move_x": move_x,
		"move_y": Input.get_axis("rail_down", "rail_up"),
		"scope": scope,
		"focus_held": Input.is_action_pressed("focus"),
		"fire_held": Input.is_action_pressed("fire"),
		"fire_pressed": Input.is_action_just_pressed("fire"),
		"fire_released": Input.is_action_just_released("fire"),
		"dodge_pressed": dodge_pressed,
		"dodge_dir": dodge_dir,
		"select": select,
		"cycle": cycle,
	}


func clear_mouse() -> void:
	_mouse_delta = Vector2.ZERO


func _stick(axis: int) -> float:
	var v := Input.get_joy_axis(0, axis)
	if absf(v) < DEADZONE:
		return 0.0
	return signf(v) * (absf(v) - DEADZONE) / (1.0 - DEADZONE)


static func _add(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for e in events:
		InputMap.action_add_event(action, e)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	return e


static func _mouse_button(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


static func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


static func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
