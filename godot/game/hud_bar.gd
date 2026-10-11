# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name HudBar
extends Node3D
## Slim battle status/control bar that floats at the top of the player's view, replacing the
## old world-anchored HUD window. It lazily follows the head (smoothed), lives outside the
## zoomable world root, and carries the same labels/buttons the controller already drives.

const AHEAD: float = 1.15        # metres in front of the eyes
const RAISE: float = 0.40        # metres above eye level: top of the view, out of the action
const FOLLOW_RATE: float = 5.0   # higher = tighter head tracking

var credits: Label3D
var core: Label3D
var wave: Label3D
var tower: Label3D
var weapon: Label3D
var note: Label3D
var call_button: Button3D
var retreat_button: Button3D


var mode_button: Button3D


func _init() -> void:
	Ui.quad(self, Vector3(0.0, 0.0, -0.012), Vector2(1.8, 0.2), Ui.PANEL)
	credits = Ui.label_left(self, "", Vector3(-0.72, 0.055, 0.004), 22, Ui.GOLD)
	core = Ui.label_left(self, "", Vector3(-0.45, 0.055, 0.004), 22, Ui.ACCENT)
	wave = Ui.label_left(self, "", Vector3(-0.13, 0.055, 0.004), 22, Color.WHITE)
	tower = Ui.label_left(self, "", Vector3(-0.72, 0.0, 0.004), 17, Color.WHITE)
	weapon = Ui.label_left(self, "", Vector3(-0.13, 0.0, 0.004), 17, Color.WHITE)
	note = Ui.label_left(self, "", Vector3(-0.72, -0.062, 0.004), 13, Ui.DIM)
	call_button = Ui.button(self, "CALL WAVE", Vector3(0.33, 0.045, 0.012), Vector2(0.28, 0.075), Ui.ACCENT, Callable(), 20)
	retreat_button = Ui.button(self, "RETREAT", Vector3(0.33, -0.048, 0.012), Vector2(0.28, 0.075), Ui.WARN, Callable(), 20)
	# The Wave runtime swallows X/Y clicks on some firmware (same bug SF2 hit), so the
	# dual-wield toggle lives on the bar too — pointer + trigger always works.
	mode_button = Ui.button(self, "L-HAND ⇄", Vector3(0.66, 0.0, 0.012), Vector2(0.26, 0.09), Ui.GOLD, Callable(), 18)


## Places the bar instantly at its anchored spot (first frame, screenshots, scene changes).
func snap(cam: Node3D) -> void:
	_place(cam, 1.0)


## Smoothed follow. Call once per frame with the active camera.
func follow(cam: Node3D, dt: float) -> void:
	_place(cam, clampf(dt * FOLLOW_RATE, 0.0, 1.0))


func _place(cam: Node3D, weight: float) -> void:
	if cam == null:
		return
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()
	var target: Vector3 = cam.global_position + fwd * AHEAD + Vector3(0.0, RAISE, 0.0)
	global_position = global_position.lerp(target, weight)
	# Face the player, tilted down toward the eyes.
	var d: Vector3 = cam.global_position - global_position
	var flat: float = sqrt(d.x * d.x + d.z * d.z)
	rotation = Vector3(-atan2(d.y, flat) * 0.8, atan2(d.x, d.z), 0.0)
