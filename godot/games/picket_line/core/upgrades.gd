# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Upgrades
extends RefCounted
## Between-sector upgrade cards. Each card's mods multiply the matching neutral value, or add to it for *_add keys.

const POOL := [
	{"id": "heat_sinks", "name": "Heat Sinks", "text": "Weapons run 25% cooler.", "mods": {"heat_mult": 0.75}},
	{"id": "focus_reserve", "name": "Focus Reserve", "text": "+40 focus. Hold time-slow longer.", "mods": {"focus_add": 40.0}},
	{"id": "flak_radius", "name": "Wide Burst", "text": "Flak splash radius +35%.", "mods": {"area_mult": 1.35}},
	{"id": "lance_charge", "name": "Quick Coil", "text": "Lance charges 30% faster.", "mods": {"charge_mult": 0.7}},
	{"id": "shield_matrix", "name": "Shield Matrix", "text": "+40 shield, regenerates 50% faster.", "mods": {"shield_max_add": 40.0, "shield_regen_mult": 1.5}},
	{"id": "salvage_net", "name": "Salvage Net", "text": "Energy regenerates 60% faster.", "mods": {"energy_mult": 1.6}},
	{"id": "swarm_pods", "name": "Extra Pods", "text": "+2 swarm missile pods.", "mods": {"pods_add": 2}},
	{"id": "evasion", "name": "Evasive Thrusters", "text": "Dodge recharges 30% faster.", "mods": {"dodge_mult": 0.7}},
	{"id": "pulse_overdrive", "name": "Pulse Overdrive", "text": "+20% damage, +15% heat from all weapons.", "mods": {"damage_mult": 1.2, "heat_mult": 1.15}},
]


static func pool() -> Array:
	return POOL


static func neutral_mods() -> Dictionary:
	return {
		"damage_mult": 1.0,
		"reload_mult": 1.0,
		"heat_mult": 1.0,
		"area_mult": 1.0,
		"charge_mult": 1.0,
		"pods_add": 0,
		"focus_add": 0.0,
		"shield_max_add": 0.0,
		"shield_regen_mult": 1.0,
		"dodge_mult": 1.0,
		"energy_mult": 1.0,
	}


## Fills any missing keys with neutral values, so callers can pass partial dictionaries.
static func with_defaults(mods: Dictionary) -> Dictionary:
	var out := neutral_mods()
	for k in mods:
		out[k] = mods[k]
	return out


static func mods_for(ids: Array) -> Dictionary:
	var out := neutral_mods()
	for id in ids:
		var card := _find(String(id))
		if card.is_empty():
			continue
		var m: Dictionary = card.mods
		for k in m:
			var key := String(k)
			if key.ends_with("_add"):
				out[key] = out[key] + m[k]
			else:
				out[key] = float(out[key]) * float(m[k])
	return out


## Up to n distinct card ids that are not already owned, chosen with rng.
static func offer(rng: Rng, owned: Array, n: int) -> Array:
	var cands: Array = []
	for card in POOL:
		if not owned.has(card.id):
			cands.append(card.id)
	var out: Array = []
	while out.size() < n and not cands.is_empty():
		var i := rng.range_i(0, cands.size() - 1)
		out.append(cands[i])
		cands.remove_at(i)
	return out


static func _find(id: String) -> Dictionary:
	for card in POOL:
		if card.id == id:
			return card
	return {}
