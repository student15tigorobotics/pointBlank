# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Station
extends RefCounted
## The picket station: rail position, aim, shield, hull, energy, heat and focus.

var hull := Balance.STATION_HULL
var shield_max := Balance.SHIELD_MAX
var shield := Balance.SHIELD_MAX
var energy := Balance.ENERGY_MAX
var heat := 0.0
var focus_max := Balance.FOCUS_MAX
var focus := Balance.FOCUS_MAX
var rail := Vector2.ZERO
var yaw := 0.0
var pitch := 0.0
var scoping := false
var focus_held := false
var focusing := false
var overheated := false
var dodge_timer := 0.0
var dodge_cool := 0.0
var dodge_dir := 0.0
var dodge_cooldown := Balance.DODGE_COOLDOWN
var iframes := 0.0
var quiet := 0.0
var hits_taken := 0
var damage_taken_sector := 0.0
var shield_regen_mult := 1.0
var energy_regen_mult := 1.0


func _init(mods: Dictionary = {}) -> void:
	var m := Upgrades.with_defaults(mods)
	shield_max += float(m.shield_max_add)
	shield = shield_max
	focus_max += float(m.focus_add)
	focus = focus_max
	shield_regen_mult = float(m.shield_regen_mult)
	energy_regen_mult = float(m.energy_mult)
	dodge_cooldown = Balance.DODGE_COOLDOWN * float(m.dodge_mult)


## Real-time station timers. Sim calls this with real dt so the player is never slowed by focus.
func step(dt: float) -> void:
	dodge_cool = maxf(0.0, dodge_cool - dt)
	if dodge_timer > 0.0:
		dodge_timer = maxf(0.0, dodge_timer - dt)
		rail.x = clampf(rail.x + dodge_dir * Balance.DODGE_SPEED * dt, -Balance.RAIL_HALF_WIDTH, Balance.RAIL_HALF_WIDTH)
	iframes = maxf(0.0, iframes - dt)
	quiet += dt
	if quiet >= Balance.SHIELD_QUIET:
		shield = minf(shield_max, shield + Balance.SHIELD_REGEN * shield_regen_mult * dt)
	energy = minf(Balance.ENERGY_MAX, energy + Balance.ENERGY_REGEN * energy_regen_mult * dt)
	heat = maxf(0.0, heat - Balance.HEAT_COOL * dt)
	if overheated and heat < Balance.HEAT_RECOVER:
		overheated = false
	focusing = focus_held and focus > 0.0
	if focusing:
		focus = maxf(0.0, focus - Balance.FOCUS_DRAIN * dt)
	else:
		focus = minf(focus_max, focus + Balance.FOCUS_REGEN * dt)


func set_aim(yaw_delta: float, pitch_delta: float) -> void:
	yaw = clampf(yaw + yaw_delta, -Balance.YAW_LIMIT, Balance.YAW_LIMIT)
	pitch = clampf(pitch + pitch_delta, Balance.PITCH_MIN, Balance.PITCH_MAX)


func move_rail(dir_x: float, dir_y: float, dt: float) -> void:
	rail.x = clampf(rail.x + dir_x * Balance.RAIL_SPEED * dt, -Balance.RAIL_HALF_WIDTH, Balance.RAIL_HALF_WIDTH)
	rail.y = clampf(rail.y + dir_y * Balance.RAIL_SPEED * 0.6 * dt, -Balance.RAIL_HALF_HEIGHT, Balance.RAIL_HALF_HEIGHT)


## Starts a quick dodge. Returns false while on cooldown or when dir is zero.
func dodge(dir: float) -> bool:
	if dodge_cool > 0.0 or dodge_timer > 0.0 or is_zero_approx(dir):
		return false
	dodge_dir = signf(dir)
	dodge_timer = Balance.DODGE_TIME
	iframes = Balance.DODGE_IFRAMES
	dodge_cool = dodge_cooldown
	return true


## Shield takes damage first, then hull. Invulnerable during dodge i-frames.
func take_damage(amount: float, kind: String) -> Dictionary:
	if amount <= 0.0 or hull <= 0.0:
		return {"applied_hull": 0.0, "applied_shield": 0.0, "blocked": false, "kind": kind}
	if iframes > 0.0:
		return {"applied_hull": 0.0, "applied_shield": 0.0, "blocked": true, "kind": kind}
	quiet = 0.0
	hits_taken += 1
	var absorbed := minf(shield, amount)
	shield -= absorbed
	var rest := amount - absorbed
	hull = maxf(0.0, hull - rest)
	damage_taken_sector += rest
	return {"applied_hull": rest, "applied_shield": absorbed, "blocked": false, "kind": kind}


func forward() -> Vector3:
	return Balance.aim_dir(yaw, pitch)


func muzzle() -> Vector3:
	return Vector3(rail.x, rail.y, 0.0)


func rail_point() -> Vector3:
	return Vector3(rail.x, rail.y, 0.0)


func alive() -> bool:
	return hull > 0.0
