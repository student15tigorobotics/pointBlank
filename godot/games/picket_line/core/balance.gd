# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name PLBalance
extends RefCounted
## Tuning numbers and static definitions. Change numbers here, not in the systems.

enum Kind { SCOUT, DRONE, GUNSHIP, BOMBER, CARRIER, DREADNOUGHT }
enum Weapon { PULSE, LANCE, FLAK, SWARM }
enum Diff { CADET, ENSIGN, COMMANDER }

const STATION_HULL := 100.0
const SHIELD_MAX := 100.0
const SHIELD_REGEN := 14.0
const SHIELD_QUIET := 3.0
const ENERGY_MAX := 100.0
const ENERGY_REGEN := 16.0
const HEAT_MAX := 100.0
const HEAT_COOL := 22.0
const HEAT_RECOVER := 25.0
const HEAT_SPREAD := 1.5
const SCOPE_SPREAD := 0.2
const FOCUS_MAX := 100.0
const FOCUS_DRAIN := 30.0
const FOCUS_REGEN := 10.0
const FOCUS_TIME_SCALE := 0.35
const RAIL_HALF_WIDTH := 8.0
const RAIL_HALF_HEIGHT := 2.5
const RAIL_SPEED := 16.0
const DODGE_SPEED := 60.0
const DODGE_TIME := 0.22
const DODGE_IFRAMES := 0.28
const DODGE_COOLDOWN := 1.1
const BEAM_RADIUS := 1.6
const SHELL_SPEED := 190.0
const ATTACK_DIST := 140.0
const CARRIER_HOLD := 170.0
const DREAD_HOLD := 230.0
const SPAWN_MIN := 350.0
const SPAWN_MAX := 900.0
const SEEN_DIST := 260.0
const SNAP_WINDOW := 1.0
const SNAP_BONUS := 50
const WEAK_DAMAGE := 2.2
const WEAK_SCORE := 1.5
const COMBO_WINDOW := 2.5
const COMBO_STEP := 3
const COMBO_MAX := 8
const YAW_LIMIT := 1.3
const PITCH_MIN := -0.5
const PITCH_MAX := 0.9
const SECTOR_BONUS := 1000
const CLEAN_BONUS := 2000
const DEATH_TIME := 0.6
const PROXIMITY := 6.0
const FLAK_MIN_FALLOFF := 0.15

## Enemy definitions. "mode" is "none", "shell" (timed projectile) or "beam" (instant, dodged by moving the rail).
## "crash" is hull damage when the alien reaches "trigger" metres from the station (0 = no crash).
## "hold" is the distance a hovering alien stops at (0 = keeps diving).
const ENEMY_DEFS := {
	Kind.SCOUT: {"name": "Scout", "hp": 30.0, "radius": 1.1, "speed": 58.0, "points": 100,
		"weak_radius": 0.0, "weak_dist": 0.0, "interval": 0.0, "telegraph": 0.0, "damage": 0.0,
		"mode": "none", "crash": 6.0, "trigger": 20.0, "hold": 0.0, "spawn": Vector2i(4, 7)},
	Kind.DRONE: {"name": "Drone", "hp": 55.0, "radius": 1.5, "speed": 24.0, "points": 150,
		"weak_radius": 0.0, "weak_dist": 0.0, "interval": 0.0, "telegraph": 0.0, "damage": 0.0,
		"mode": "none", "crash": 4.0, "trigger": 20.0, "hold": 0.0, "spawn": Vector2i(3, 6)},
	Kind.GUNSHIP: {"name": "Gunship", "hp": 170.0, "radius": 3.0, "speed": 16.0, "points": 400,
		"weak_radius": 1.1, "weak_dist": 3.4, "interval": 2.6, "telegraph": 0.9, "damage": 12.0,
		"mode": "shell", "crash": 0.0, "trigger": 0.0, "hold": ATTACK_DIST, "spawn": Vector2i(2, 4)},
	Kind.BOMBER: {"name": "Bomber", "hp": 80.0, "radius": 2.2, "speed": 27.0, "points": 300,
		"weak_radius": 0.0, "weak_dist": 0.0, "interval": 0.0, "telegraph": 0.0, "damage": 0.0,
		"mode": "none", "crash": 25.0, "trigger": 60.0, "hold": 0.0, "spawn": Vector2i(2, 4)},
	Kind.CARRIER: {"name": "Carrier", "hp": 900.0, "radius": 9.0, "speed": 7.0, "points": 2500,
		"weak_radius": 2.6, "weak_dist": 7.5, "interval": 3.6, "telegraph": 1.1, "damage": 16.0,
		"mode": "beam", "crash": 0.0, "trigger": 0.0, "hold": CARRIER_HOLD, "spawn": Vector2i(1, 1)},
	Kind.DREADNOUGHT: {"name": "Dreadnought", "hp": 3200.0, "radius": 16.0, "speed": 4.0, "points": 9000,
		"weak_radius": 4.5, "weak_dist": 12.0, "interval": 3.0, "telegraph": 1.4, "damage": 26.0,
		"mode": "shell", "crash": 0.0, "trigger": 0.0, "hold": DREAD_HOLD, "spawn": Vector2i(1, 1)},
}

## Weapon definitions. "damage_max" is the full-charge damage for the lance. "area" is flak splash radius (m).
const WEAPON_DEFS := {
	Weapon.PULSE: {"name": "Pulse", "cooldown": 0.09, "damage": 9.0, "damage_max": 9.0, "speed": 480.0,
		"heat": 2.3, "energy": 0.0, "spread": 2.4, "charge_min": 0.0, "charge_max": 0.0,
		"area": 0.0, "fuse": 0.0, "lock_cone": 0.0, "pods": 0, "pod_reload": 0.0, "homing": 0.0, "max_range": 1100.0},
	Weapon.LANCE: {"name": "Lance", "cooldown": 0.4, "damage": 40.0, "damage_max": 220.0, "speed": 1500.0,
		"heat": 18.0, "energy": 24.0, "spread": 0.0, "charge_min": 0.15, "charge_max": 1.2,
		"area": 0.0, "fuse": 0.0, "lock_cone": 0.0, "pods": 0, "pod_reload": 0.0, "homing": 0.0, "max_range": 1800.0},
	Weapon.FLAK: {"name": "Flak", "cooldown": 1.2, "damage": 55.0, "damage_max": 55.0, "speed": 210.0,
		"heat": 10.0, "energy": 14.0, "spread": 1.0, "charge_min": 0.0, "charge_max": 0.0,
		"area": 8.5, "fuse": 2.6, "lock_cone": 0.0, "pods": 0, "pod_reload": 0.0, "homing": 0.0, "max_range": 1000.0},
	Weapon.SWARM: {"name": "Swarm", "cooldown": 0.45, "damage": 30.0, "damage_max": 30.0, "speed": 135.0,
		"heat": 4.0, "energy": 16.0, "spread": 0.0, "charge_min": 0.0, "charge_max": 0.0,
		"area": 0.0, "fuse": 0.0, "lock_cone": 7.0, "pods": 4, "pod_reload": 1.1, "homing": 2.6, "max_range": 1200.0},
}

const DIFFICULTY := {
	Diff.CADET: {"name": "Cadet", "hp_mult": 0.75, "spawn_mult": 0.8, "fire_mult": 0.8},
	Diff.ENSIGN: {"name": "Ensign", "hp_mult": 1.0, "spawn_mult": 1.0, "fire_mult": 1.0},
	Diff.COMMANDER: {"name": "Commander", "hp_mult": 1.35, "spawn_mult": 1.25, "fire_mult": 1.2},
}


static func enemy_def(kind: int) -> Dictionary:
	return ENEMY_DEFS[kind]


static func weapon_def(weapon: int) -> Dictionary:
	return WEAPON_DEFS[weapon]


static func difficulty(level: int) -> Dictionary:
	return DIFFICULTY[level]


## Forward vector for a yaw and pitch. Yaw 0 and pitch 0 look down -Z; positive pitch looks up.
static func aim_dir(yaw: float, pitch: float) -> Vector3:
	var cp := cos(pitch)
	return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)


## Inverse of aim_dir: returns Vector2(yaw, pitch) that points at the given world direction.
static func aim_yaw_pitch(v: Vector3) -> Vector2:
	var n := v.normalized()
	return Vector2(atan2(-n.x, -n.z), asin(clampf(n.y, -1.0, 1.0)))
