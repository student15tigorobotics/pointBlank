# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Enemy
extends RefCounted
## One alien. Plain data; movement and fire rules live in EnemyAI.

var id := 0
var kind := 0
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var hp := 1.0
var max_hp := 1.0
var radius := 1.0
var weak_radius := 0.0
var weak_dist := 0.0
var weak_offset := Vector3.ZERO
var weak_open := false
var last_crit := false
var points := 0
var alive := true
var boss := false
var age := 0.0
var fire_timer := 0.0
var telegraph := 0.0
var telegraph_dir := Vector3.ZERO
var phase := 0
var launch_timer := 0.0
var wiggle := 0.0
var group := 0
var dead_timer := 0.0
var first_seen_age := -1.0


func is_boss() -> bool:
	return boss


func total_radius() -> float:
	return radius


func centre() -> Vector3:
	return pos
