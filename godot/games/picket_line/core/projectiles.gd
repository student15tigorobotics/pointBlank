# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name PLProjectiles
extends RefCounted
## Player shots (swept against enemy spheres, weak core first) and enemy shells.
## A shell hits only if the rail is still within BEAM_RADIUS of the point it was aimed at.

var _shots: Array = []
var _shells: Array = []
var _next_id := 1


func fire_player(weapon: int, origin: Vector3, dir: Vector3, damage: float, extra: Dictionary) -> int:
	var def: Dictionary = PLBalance.WEAPON_DEFS[weapon]
	var id := _next_id
	_next_id += 1
	_shots.append({
		"id": id,
		"weapon": weapon,
		"pos": origin,
		"prev": origin,
		"dir": dir.normalized(),
		"speed": float(extra.get("speed", def.speed)),
		"damage": damage,
		"area": float(extra.get("area", def.area)),
		"fuse": float(extra.get("fuse", def.fuse)),
		"lock_id": int(extra.get("lock_id", 0)),
		"homing": float(def.homing),
		"travelled": 0.0,
		"max_range": float(def.max_range),
	})
	return id


func fire_enemy_shell(from: Vector3, to: Vector3, speed: float, damage: float) -> int:
	var id := _next_id
	_next_id += 1
	_shells.append({"id": id, "from": from, "to": to, "pos": from, "t": 0.0,
		"dist": maxf(0.1, from.distance_to(to)), "speed": speed, "damage": damage})
	return id


func step(dt: float, enemies: Array, station: Station) -> Array:
	var events: Array = []
	var i := _shots.size() - 1
	while i >= 0:
		if _step_shot(_shots[i], dt, enemies, events):
			_shots.remove_at(i)
		i -= 1
	i = _shells.size() - 1
	while i >= 0:
		if _step_shell(_shells[i], dt, station, events):
			_shells.remove_at(i)
		i -= 1
	return events


func active_player() -> Array:
	var out: Array = []
	for p in _shots:
		out.append({"pos": p.pos, "prev": p.prev, "dir": p.dir, "weapon": p.weapon, "damage": p.damage})
	return out


func active_enemy_shells() -> Array:
	var out: Array = []
	for s in _shells:
		out.append({"pos": s.pos, "from": s.from, "to": s.to, "t": s.t})
	return out


func _step_shot(p: Dictionary, dt: float, enemies: Array, events: Array) -> bool:
	var homing: float = p.homing
	if homing > 0.0 and int(p.lock_id) > 0:
		var target := _find(enemies, int(p.lock_id))
		if target != null:
			var to_target: Vector3 = (target.pos - p.pos).normalized()
			p.dir = (p.dir + to_target * homing * dt).normalized()
	p.prev = p.pos
	var travel: float = float(p.speed) * dt
	p.pos = p.prev + p.dir * travel
	p.travelled = float(p.travelled) + travel
	var hit := _first_hit(p.prev, p.pos, enemies)
	if int(p.weapon) == PLBalance.Weapon.FLAK:
		return _flak(p, hit, dt, enemies, events)
	if not hit.is_empty():
		_direct_hit(p, hit, events)
		return true
	if float(p.travelled) >= float(p.max_range):
		events.append({"type": "shot_expired", "pos": p.pos})
		return true
	return false


func _flak(p: Dictionary, hit: Dictionary, dt: float, enemies: Array, events: Array) -> bool:
	p.fuse = float(p.fuse) - dt
	var at: Vector3 = p.pos
	var go := false
	if not hit.is_empty():
		at = p.prev.lerp(p.pos, float(hit.t))
		go = true
	elif float(p.fuse) <= 0.0 or _near_any(p.pos, enemies):
		go = true
	if go:
		_detonate(p, at, enemies, events)
		return true
	if float(p.travelled) >= float(p.max_range):
		events.append({"type": "shot_expired", "pos": p.pos})
		return true
	return false


func _detonate(p: Dictionary, at: Vector3, enemies: Array, events: Array) -> void:
	var area: float = maxf(float(p.area), 0.01)
	var base: float = p.damage
	var nearest: Enemy = null
	var nearest_d := INF
	for e: Enemy in enemies:
		if not e.alive:
			continue
		var d := maxf(0.0, at.distance_to(e.pos) - e.radius)
		if d > area:
			continue
		var falloff := clampf(1.0 - d / area, PLBalance.FLAK_MIN_FALLOFF, 1.0)
		e.hp -= base * falloff
		e.last_crit = false
		if d < nearest_d:
			nearest_d = d
			nearest = e
	events.append({"type": "detonate", "pos": at, "radius": area, "weapon": p.weapon})
	if nearest != null:
		events.append({"type": "hit", "enemy_id": nearest.id, "damage": base, "crit": false,
			"weapon": p.weapon, "pos": at, "kind": nearest.kind})


func _direct_hit(p: Dictionary, hit: Dictionary, events: Array) -> void:
	var e: Enemy = hit.enemy
	var crit: bool = hit.crit
	var dmg: float = float(p.damage) * (PLBalance.WEAK_DAMAGE if crit else 1.0)
	e.hp -= dmg
	e.last_crit = crit
	events.append({"type": "hit", "enemy_id": e.id, "damage": dmg, "crit": crit,
		"weapon": p.weapon, "pos": p.prev.lerp(p.pos, float(hit.t)), "kind": e.kind})


## Returns {enemy, t, crit} for the nearest enemy the segment touches, or an empty dictionary.
func _first_hit(a: Vector3, b: Vector3, enemies: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_t := 2.0
	for e: Enemy in enemies:
		if not e.alive:
			continue
		var tb := _seg_sphere(a, b, e.pos, e.radius)
		var tw := -1.0
		if e.weak_open and e.weak_radius > 0.0:
			tw = _seg_sphere(a, b, e.pos + e.weak_offset, e.weak_radius)
		var t := tb
		var crit := false
		if tw >= 0.0 and (tb < 0.0 or tw <= tb):
			t = tw
			crit = true
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"enemy": e, "t": t, "crit": crit}
	return best


## Entry parameter t in [0, 1] where segment a->b first touches sphere (c, r), or -1 when it misses.
func _seg_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> float:
	var d := b - a
	var f := a - c
	var qa := d.dot(d)
	if qa < 0.000000001:
		return 0.0 if f.length() <= r else -1.0
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return -1.0
	var t1 := (-qb - sqrt(disc)) / (2.0 * qa)
	if t1 >= 0.0 and t1 <= 1.0:
		return t1
	if qc <= 0.0:
		return 0.0
	return -1.0


func _near_any(pos: Vector3, enemies: Array) -> bool:
	for e: Enemy in enemies:
		if e.alive and pos.distance_to(e.pos) <= e.radius + PLBalance.PROXIMITY:
			return true
	return false


func _find(enemies: Array, id: int) -> Enemy:
	for e: Enemy in enemies:
		if e.id == id:
			return e
	return null


func _step_shell(s: Dictionary, dt: float, station: Station, events: Array) -> bool:
	s.t = float(s.t) + dt * float(s.speed) / float(s.dist)
	var at: Vector3 = s.to
	s.pos = (s.from as Vector3).lerp(at, minf(float(s.t), 1.0))
	if float(s.t) < 1.0:
		return false
	var rail := station.rail_point()
	if Vector2(rail.x, rail.y).distance_to(Vector2(at.x, at.y)) <= PLBalance.BEAM_RADIUS:
		var r := station.take_damage(float(s.damage), "shell")
		events.append({"type": "player_hit", "kind": "shell", "damage": float(s.damage),
			"applied_hull": r.applied_hull, "applied_shield": r.applied_shield, "blocked": r.blocked, "pos": at})
	else:
		events.append({"type": "shell_miss", "pos": at})
	return true
