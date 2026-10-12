# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name EnemyAI
extends RefCounted
## Movement, weak-core timing, telegraphed fire and special behaviour (crash, launch, phases) for one alien.
## Events are appended to `out`; Sim resolves them. ctx keys: rail (Vector3 aim point), fire_mult (float).

const CARRIER_LAUNCH := 6.0
const LAUNCH_COUNT := 4
const DREAD_LAUNCH := 5
const PHASE_THRESHOLDS := [0.66, 0.33]
const WEAK_PERIOD := 4.0
const WEAK_OPEN_TIME := 1.5
const FIRE_GRACE := 1.5
const FIRE_RANGE_PAD := 40.0


static func step(e: Enemy, dt: float, ctx: Dictionary, rng: Rng, out: Array) -> void:
	var def: Dictionary = PLBalance.ENEMY_DEFS[e.kind]
	e.age += dt
	e.wiggle += dt
	var to_station := -e.pos
	var dist := to_station.length()
	var dir := to_station / maxf(dist, 0.001)
	var side := Vector3(-dir.z, 0.0, dir.x)
	if e.first_seen_age < 0.0 and dist <= PLBalance.SEEN_DIST:
		e.first_seen_age = e.age
	e.weak_offset = dir * float(def.weak_dist)
	e.weak_open = _weak_open(e)
	var speed: float = def.speed
	match e.kind:
		PLBalance.Kind.SCOUT, PLBalance.Kind.DRONE, PLBalance.Kind.BOMBER:
			var weave := 0.0
			if e.kind == PLBalance.Kind.DRONE:
				weave = sin(e.wiggle * 2.2) * 9.0
			e.vel = dir * speed + side * weave
			e.pos += e.vel * dt
			if e.pos.length() <= float(def.trigger):
				e.alive = false
				e.dead_timer = 0.0
				out.append({"type": "crash", "enemy_id": e.id, "kind": e.kind,
					"damage": float(def.crash), "pos": e.pos})
		PLBalance.Kind.GUNSHIP, PLBalance.Kind.CARRIER, PLBalance.Kind.DREADNOUGHT:
			if dist > float(def.hold):
				e.vel = dir * speed
			else:
				e.vel = side * 2.0 * sin(e.wiggle * 0.5)
			e.pos += e.vel * dt
			if e.kind == PLBalance.Kind.CARRIER:
				_carrier_launch(e, dt, out)
			elif e.kind == PLBalance.Kind.DREADNOUGHT:
				_dread_phase(e, out)
			_fire(e, def, e.pos.length(), dt, ctx, out)


static func _carrier_launch(e: Enemy, dt: float, out: Array) -> void:
	e.launch_timer -= dt
	if e.launch_timer <= 0.0:
		e.launch_timer = CARRIER_LAUNCH
		out.append({"type": "launch", "kind": PLBalance.Kind.SCOUT, "count": LAUNCH_COUNT,
			"pos": e.pos, "group": e.group})


static func _dread_phase(e: Enemy, out: Array) -> void:
	var frac := e.hp / maxf(e.max_hp, 1.0)
	var target := 0
	if frac <= PHASE_THRESHOLDS[1]:
		target = 2
	elif frac <= PHASE_THRESHOLDS[0]:
		target = 1
	if target > e.phase:
		e.phase = target
		out.append({"type": "boss_phase", "enemy_id": e.id, "phase": target, "pos": e.pos})
		out.append({"type": "launch", "kind": PLBalance.Kind.DRONE, "count": DREAD_LAUNCH,
			"pos": e.pos, "group": e.group})


static func _fire(e: Enemy, def: Dictionary, dist: float, dt: float, ctx: Dictionary, out: Array) -> void:
	if String(def.mode) == "none" or e.age < FIRE_GRACE or dist > float(def.hold) + FIRE_RANGE_PAD:
		return
	var fire_mult: float = ctx.fire_mult
	if e.telegraph > 0.0:
		e.telegraph -= dt
		if e.telegraph <= 0.0:
			e.telegraph = 0.0
			out.append({"type": "enemy_fire", "enemy_id": e.id, "kind": e.kind, "mode": def.mode,
				"from": e.pos, "to": e.telegraph_dir, "damage": float(def.damage)})
			e.fire_timer = float(def.interval) * (1.0 - 0.18 * float(e.phase)) / maxf(0.1, fire_mult)
		return
	e.fire_timer -= dt
	if e.fire_timer <= 0.0:
		e.telegraph = float(def.telegraph)
		e.telegraph_dir = ctx.rail
		out.append({"type": "telegraph", "enemy_id": e.id, "kind": e.kind, "pos": e.pos,
			"time": e.telegraph})


static func _weak_open(e: Enemy) -> bool:
	if e.weak_radius <= 0.0:
		return false
	if e.kind == PLBalance.Kind.CARRIER or e.kind == PLBalance.Kind.DREADNOUGHT:
		return fposmod(e.age, WEAK_PERIOD) < WEAK_OPEN_TIME
	return true
