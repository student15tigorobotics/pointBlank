# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Weapons
extends RefCounted
## Player weapons: cooldowns, heat and energy costs, lance charge, swarm pods and lock-on.
## Player weapon timers run on real time, so focus slows the enemies but not the player's hands.

var mods: Dictionary = {}
var current: int = Balance.Weapon.PULSE
var cooldown: Array = [0.0, 0.0, 0.0, 0.0]
var charging := false
var charge_t := 0.0
var pods := 0.0


func _init(mods_in: Dictionary = {}) -> void:
	mods = Upgrades.with_defaults(mods_in)
	pods = float(max_pods())


func max_pods() -> int:
	return int(Balance.WEAPON_DEFS[Balance.Weapon.SWARM].pods) + int(mods.pods_add)


func update(dt: float) -> void:
	for i in cooldown.size():
		cooldown[i] = maxf(0.0, float(cooldown[i]) - dt)
	var rate := 1.0 / float(Balance.WEAPON_DEFS[Balance.Weapon.SWARM].pod_reload)
	pods = minf(float(max_pods()), pods + dt * rate)


func select(w: int) -> void:
	if w == current:
		return
	current = clampi(w, 0, 3)
	charging = false
	charge_t = 0.0


func cycle(step: int) -> void:
	select(posmod(current + step, 4))


## cmd keys: fire_held (bool), fire_pressed (bool, edge). Returns events ("shot", "lock", "dry", "overheat", "charge_start").
func try_fire(dt: float, cmd: Dictionary, station: Station, muzzle: Vector3, dir: Vector3,
		projectiles: Projectiles, enemies: Array, rng: Rng) -> Array:
	var events: Array = []
	var held: bool = cmd.get("fire_held", false)
	var pressed: bool = cmd.get("fire_pressed", false)
	if current == Balance.Weapon.LANCE:
		_lance(dt, held, pressed, station, muzzle, dir, projectiles, events)
		return events
	if station.overheated:
		if pressed:
			events.append({"type": "dry", "reason": "heat"})
		return events
	if not held or float(cooldown[current]) > 0.0:
		return events
	match current:
		Balance.Weapon.PULSE:
			station.heat += float(Balance.WEAPON_DEFS[current].heat) * float(mods.heat_mult)
			var def: Dictionary = Balance.WEAPON_DEFS[current]
			var spread_deg: float = float(def.spread) * (Balance.SCOPE_SPREAD if station.scoping else 1.0) \
				+ Balance.HEAT_SPREAD * station.heat / Balance.HEAT_MAX
			var d := _cone(dir, deg_to_rad(spread_deg), rng)
			projectiles.fire_player(Balance.Weapon.PULSE, muzzle, d, float(def.damage) * float(mods.damage_mult), {})
			cooldown[current] = float(def.cooldown) * float(mods.reload_mult)
			events.append({"type": "shot", "weapon": current, "count": 1, "pos": muzzle})
			_heat_check(station, events)
		Balance.Weapon.FLAK:
			var fdef: Dictionary = Balance.WEAPON_DEFS[current]
			if not _pay(station, fdef, pressed, events):
				return events
			station.heat += float(fdef.heat) * float(mods.heat_mult)
			projectiles.fire_player(Balance.Weapon.FLAK, muzzle, dir, float(fdef.damage) * float(mods.damage_mult),
				{"area": float(fdef.area) * float(mods.area_mult), "fuse": float(fdef.fuse)})
			cooldown[current] = float(fdef.cooldown) * float(mods.reload_mult)
			events.append({"type": "shot", "weapon": current, "count": 1, "pos": muzzle})
			_heat_check(station, events)
		Balance.Weapon.SWARM:
			_swarm(station, muzzle, dir, projectiles, enemies, rng, pressed, events)
	return events


func _lance(dt: float, held: bool, pressed: bool, station: Station, muzzle: Vector3, dir: Vector3,
		projectiles: Projectiles, events: Array) -> void:
	var def: Dictionary = Balance.WEAPON_DEFS[Balance.Weapon.LANCE]
	var max_t := float(def.charge_max) * float(mods.charge_mult)
	if station.overheated or float(cooldown[Balance.Weapon.LANCE]) > 0.0:
		charging = false
		charge_t = 0.0
		if pressed and station.overheated:
			events.append({"type": "dry", "reason": "heat"})
		return
	if held:
		if not charging:
			if station.energy < float(def.energy):
				if pressed:
					events.append({"type": "dry", "reason": "energy"})
				return
			charging = true
			charge_t = 0.0
			events.append({"type": "charge_start"})
		charge_t = minf(charge_t + dt, max_t)
		return
	if not charging:
		return
	charging = false
	var t01 := clampf(charge_t / maxf(max_t, 0.001), 0.0, 1.0)
	var long_enough := charge_t >= float(def.charge_min)
	charge_t = 0.0
	if not long_enough:
		return
	if station.energy < float(def.energy):
		events.append({"type": "dry", "reason": "energy"})
		return
	station.energy -= float(def.energy)
	station.heat += float(def.heat) * float(mods.heat_mult)
	var dmg := lerpf(float(def.damage), float(def.damage_max), t01) * float(mods.damage_mult)
	projectiles.fire_player(Balance.Weapon.LANCE, muzzle, dir, dmg, {"speed": float(def.speed)})
	cooldown[Balance.Weapon.LANCE] = float(def.cooldown) * float(mods.reload_mult)
	events.append({"type": "shot", "weapon": Balance.Weapon.LANCE, "count": 1, "pos": muzzle, "charge": t01})
	_heat_check(station, events)


func _swarm(station: Station, muzzle: Vector3, dir: Vector3, projectiles: Projectiles,
		enemies: Array, rng: Rng, pressed: bool, events: Array) -> void:
	var def: Dictionary = Balance.WEAPON_DEFS[Balance.Weapon.SWARM]
	var available := int(floor(pods))
	if available < 1 or station.energy < float(def.energy):
		if pressed:
			events.append({"type": "dry", "reason": "pods" if available < 1 else "energy"})
		return
	station.energy -= float(def.energy)
	station.heat += float(def.heat) * float(mods.heat_mult)
	var locks := _locks(muzzle, dir, def, enemies, available)
	var count := maxi(1, locks.size())
	for i in count:
		var target := int(locks[i]) if i < locks.size() else 0
		projectiles.fire_player(Balance.Weapon.SWARM, muzzle, _cone(dir, 0.02, rng),
			float(def.damage) * float(mods.damage_mult), {"lock_id": target, "speed": float(def.speed)})
	pods -= float(count)
	cooldown[Balance.Weapon.SWARM] = float(def.cooldown) * float(mods.reload_mult)
	events.append({"type": "shot", "weapon": Balance.Weapon.SWARM, "count": count, "pos": muzzle})
	if not locks.is_empty():
		events.append({"type": "lock", "ids": locks})
	_heat_check(station, events)


func _locks(muzzle: Vector3, dir: Vector3, def: Dictionary, enemies: Array, limit: int) -> Array:
	var cone := deg_to_rad(float(def.lock_cone))
	var cands: Array = []
	for e: Enemy in enemies:
		if not e.alive:
			continue
		var to: Vector3 = e.pos - muzzle
		if to.length_squared() < 0.0001:
			continue
		var ang := acos(clampf(dir.dot(to.normalized()), -1.0, 1.0))
		if ang <= cone:
			cands.append([ang, e.id])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var ids: Array = []
	for i in mini(limit, cands.size()):
		ids.append(cands[i][1])
	return ids


func _pay(station: Station, def: Dictionary, pressed: bool, events: Array) -> bool:
	if station.energy < float(def.energy):
		if pressed:
			events.append({"type": "dry", "reason": "energy"})
		return false
	station.energy -= float(def.energy)
	return true


func _heat_check(station: Station, events: Array) -> void:
	if station.heat >= Balance.HEAT_MAX and not station.overheated:
		station.heat = Balance.HEAT_MAX
		station.overheated = true
		events.append({"type": "overheat"})


func _cone(dir: Vector3, half_rad: float, rng: Rng) -> Vector3:
	if half_rad <= 0.0:
		return dir
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	var r := sqrt(rng.next()) * half_rad
	var a := rng.next() * TAU
	return (dir + right * (cos(a) * r) + up * (sin(a) * r)).normalized()
