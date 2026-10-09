# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name Profile
extends RefCounted
## Everything that persists between sessions. Port of Profile.cs.
## Serialise with to_dict() and rebuild with from_dict(); the save file layer (SaveStore) only handles JSON text.

const GATE_PREFIX: String = "gate_"

var version: int = 1
var bank: int = 0
var upgrade_levels: Array = []      # ints, length UpgradeCatalog.count()
var unlocks: Array = []             # String keys, see UnlockCatalog
var stage_stars: Array = []         # ints, length StageCatalog.count()
var revealed: Array = []            # cheat codes revealed by clearing chapters
var redeemed: Array = []            # cheat codes already redeemed
var pending: Array = []             # CheatEffect names applied to the next battle, e.g. "OVERKILL_BOOST"
var flags: Array = []               # dialogue choices
var board: Array = []               # leaderboard entries, dicts {name, score, stage, date}
var callsign_seed: int = 1
var benchmark_max: int = 0          # sustained ALIVE count at the benchmark stop point
var benchmark_visible: int = 0      # visible count at the benchmark stop point
var benchmark_tier: int = -1        # graphics tier used at the stop point, -1 when none
var tts_on: bool = true
var quality: int = 1                # 0 low, 1 medium, 2 high
var prologue_seen: bool = false


func _init() -> void:
	upgrade_levels = _zeros(UpgradeCatalog.count())
	stage_stars = _zeros(StageCatalog.count())


func upgrade_level(id: int) -> int:
	return int(upgrade_levels[id])


func has_weapon(kind: int) -> bool:
	return kind == Balance.WeaponKind.BLASTER or unlocks.has(UnlockCatalog.weapon_key(kind))


func has_tower(kind: int) -> bool:
	return kind == Balance.TowerKind.TURRET or unlocks.has(UnlockCatalog.tower_key(kind))


func has_flag(flag: String) -> bool:
	return flags.has(flag)


func can_play_stage(stage: int) -> bool:
	if stage == 0:
		return true
	if stage < 1 or stage > stage_stars.size():
		return false
	return int(stage_stars[stage - 1]) > 0


func try_buy_upgrade(id: int) -> bool:
	var def: Dictionary = UpgradeCatalog.get_def(id)
	var level: int = upgrade_level(id)
	if level >= int(def["max_level"]):
		return false
	var cost: int = UpgradeCatalog.next_cost(def, level)
	if bank < cost:
		return false
	bank -= cost
	upgrade_levels[id] = level + 1
	return true


## def is an UnlockCatalog entry: {key, title, cost}.
func try_buy_unlock(def: Dictionary) -> bool:
	var key: String = str(def["key"])
	var cost: int = int(def["cost"])
	if unlocks.has(key) or bank < cost:
		return false
	bank -= cost
	unlocks.append(key)
	return true


## Applies persistent upgrades plus any cheat effects queued for this battle, then clears the queue.
func consume_battle_modifiers() -> BattleModifiers:
	var m: BattleModifiers = BattleModifiers.defaults()
	m.core_max_hp += 5 * upgrade_level(UpgradeCatalog.UpgradeId.CORE_ARMOR)
	m.overkill_ratio += 0.15 * upgrade_level(UpgradeCatalog.UpgradeId.OVERKILL_ENGINE)
	m.early_bonus_mult += 0.25 * upgrade_level(UpgradeCatalog.UpgradeId.EARLY_CALL_BONUS)
	m.tower_cost_mult = 1.0 - 0.08 * upgrade_level(UpgradeCatalog.UpgradeId.LOGISTICS)
	m.weapon_damage_mult += 0.12 * upgrade_level(UpgradeCatalog.UpgradeId.WEAPON_TUNING)
	m.tower_damage_mult += 0.12 * upgrade_level(UpgradeCatalog.UpgradeId.TOWER_TUNING)
	m.weapon_cooldown_mult = 1.0 - 0.06 * upgrade_level(UpgradeCatalog.UpgradeId.RAPID_CYCLE)
	m.start_credits += 60 * upgrade_level(UpgradeCatalog.UpgradeId.FUNDING_DRIVE)

	for name in pending:
		var effect: int = CheatCatalog.effect_from_name(str(name))
		if effect < 0:
			continue
		var def: Dictionary = CheatCatalog.for_effect(effect)
		if effect == CheatCatalog.CheatEffect.OVERKILL_BOOST:
			m.overkill_ratio *= 2.0
		elif effect == CheatCatalog.CheatEffect.CORE_BOOST:
			m.core_max_hp += int(def["amount"])
		elif effect == CheatCatalog.CheatEffect.START_CREDITS:
			m.start_credits += int(def["amount"])
		elif effect == CheatCatalog.CheatEffect.RAPID_FIRE:
			m.weapon_cooldown_mult *= 0.5
	pending.clear()
	return m


## Redeems a keypad code. Returns {ok: bool, message: String}, the message being player-facing.
func redeem(code: String) -> Dictionary:
	var def: Dictionary = CheatCatalog.find(code)
	if def.is_empty() or not revealed.has(code):
		return {"ok": false, "message": "ACCESS DENIED"}
	if redeemed.has(code):
		return {"ok": false, "message": "ALREADY USED"}

	var effect: int = int(def["effect"])
	if effect == CheatCatalog.CheatEffect.BANK_CREDITS:
		bank += int(def["amount"])
	elif effect == CheatCatalog.CheatEffect.ARSENAL_KEY:
		for u in UnlockCatalog.all():
			if not unlocks.has(u["key"]):
				unlocks.append(u["key"])
	else:
		pending.append(CheatCatalog.effect_name(effect))

	redeemed.append(code)
	return {"ok": true, "message": str(def["title"]) + ": " + str(def["text"])}


## Records a finished battle. Returns {payout: int, revealed: Dictionary} where revealed is the
## CheatCatalog entry revealed by this clear, or {} when none.
func record_stage(stage: int, stars_count: int, earned: int) -> Dictionary:
	var revealed_def: Dictionary = {}
	if stage < 0 or stage >= stage_stars.size():
		return {"payout": 0, "revealed": revealed_def}

	var prev: int = int(stage_stars[stage])
	var first_clear: bool = prev == 0 and stars_count > 0
	stage_stars[stage] = maxi(prev, stars_count)
	var payout: int = BattleEconomy.bank_payout(earned, stars_count, first_clear) if stars_count > 0 else 0
	bank += payout

	if stars_count > 0:
		var card: Dictionary = CheatCatalog.for_chapter(stage)
		if not card.is_empty() and not revealed.has(card["code"]):
			revealed.append(card["code"])
			revealed_def = card
	return {"payout": payout, "revealed": revealed_def}


func set_flag(flag: String) -> void:
	if flag == "":
		return
	if flag.begins_with(GATE_PREFIX):
		# Only one gate flag at a time: drop the other gate flags before adding this one.
		for i in range(flags.size() - 1, -1, -1):
			var old: String = str(flags[i])
			if old.begins_with(GATE_PREFIX) and old != flag:
				flags.remove_at(i)
	if not flags.has(flag):
		flags.append(flag)


## Wipes campaign progress. Settings, callsign seed, benchmark result and the leaderboard are kept.
func reset_campaign() -> void:
	bank = 0
	upgrade_levels = _zeros(UpgradeCatalog.count())
	unlocks = []
	stage_stars = _zeros(StageCatalog.count())
	revealed = []
	redeemed = []
	pending = []
	flags = []
	prologue_seen = false


func to_dict() -> Dictionary:
	return {
		"version": version,
		"bank": bank,
		"upgrade_levels": upgrade_levels.duplicate(),
		"unlocks": unlocks.duplicate(),
		"stage_stars": stage_stars.duplicate(),
		"revealed": revealed.duplicate(),
		"redeemed": redeemed.duplicate(),
		"pending": pending.duplicate(),
		"flags": flags.duplicate(),
		"board": board.duplicate(true),
		"callsign_seed": callsign_seed,
		"benchmark_max": benchmark_max,
		"benchmark_visible": benchmark_visible,
		"benchmark_tier": benchmark_tier,
		"tts_on": tts_on,
		"quality": quality,
		"prologue_seen": prologue_seen,
	}


## Tolerant load: missing or mistyped keys fall back to defaults, JSON numbers (floats) become ints,
## and per-stage and per-upgrade arrays are resized to the catalog lengths. quality is clamped to 0..2 and
## benchmark_tier to -1..2, so later tier-name lookups never index out of range.
static func from_dict(d: Dictionary) -> Profile:
	var p: Profile = Profile.new()
	p.version = _int_of(d, "version", 1)
	p.bank = _int_of(d, "bank", 0)
	p.upgrade_levels = _int_list(d, "upgrade_levels", UpgradeCatalog.count())
	p.unlocks = _str_list(d, "unlocks")
	p.stage_stars = _int_list(d, "stage_stars", StageCatalog.count())
	p.revealed = _str_list(d, "revealed")
	p.redeemed = _str_list(d, "redeemed")
	p.pending = _str_list(d, "pending")
	p.flags = _str_list(d, "flags")
	p.board = _board_of(d, "board")
	p.callsign_seed = _int_of(d, "callsign_seed", 1)
	p.benchmark_max = _int_of(d, "benchmark_max", 0)
	p.benchmark_visible = _int_of(d, "benchmark_visible", 0)
	p.benchmark_tier = clampi(_int_of(d, "benchmark_tier", -1), -1, 2)
	p.tts_on = _bool_of(d, "tts_on", true)
	p.quality = clampi(_int_of(d, "quality", 1), 0, 2)
	p.prologue_seen = _bool_of(d, "prologue_seen", false)
	return p


static func _zeros(n: int) -> Array:
	var out: Array = []
	out.resize(n)
	out.fill(0)
	return out


static func _as_int(v: Variant, fallback: int) -> int:
	if v is int or v is float:
		return int(v)
	return fallback


static func _as_str(v: Variant, fallback: String) -> String:
	if v is String:
		return v
	return fallback


static func _int_of(d: Dictionary, key: String, fallback: int) -> int:
	return _as_int(d.get(key, fallback), fallback)


static func _bool_of(d: Dictionary, key: String, fallback: bool) -> bool:
	var v: Variant = d.get(key, fallback)
	if v is bool:
		return v
	return fallback


static func _int_list(d: Dictionary, key: String, n: int) -> Array:
	var out: Array = _zeros(n)
	var src: Variant = d.get(key, [])
	if src is Array:
		var arr: Array = src
		for i in range(mini(arr.size(), n)):
			out[i] = _as_int(arr[i], 0)
	return out


static func _str_list(d: Dictionary, key: String) -> Array:
	var out: Array = []
	var src: Variant = d.get(key, [])
	if src is Array:
		var arr: Array = src
		for item in arr:
			if item != null:
				out.append(str(item))
	return out


static func _board_of(d: Dictionary, key: String) -> Array:
	var out: Array = []
	var src: Variant = d.get(key, [])
	if src is Array:
		var arr: Array = src
		for item in arr:
			if item is Dictionary:
				out.append(_normalize_entry(item))
	return out


static func _normalize_entry(e: Dictionary) -> Dictionary:
	return {
		"name": _as_str(e.get("name", ""), ""),
		"score": _as_int(e.get("score", 0), 0),
		"stage": _as_int(e.get("stage", 0), 0),
		"date": _as_str(e.get("date", ""), ""),
	}
