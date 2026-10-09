# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name UpgradeCatalog
extends RefCounted
## Permanent, levelled upgrades bought with the bank in the Hub. Port of Upgrades.cs (UpgradeCatalog).
##
## Def dict: {id: int (UpgradeId), name: String, description: String, max_level: int, base_cost: int}

enum UpgradeId { CORE_ARMOR, OVERKILL_ENGINE, EARLY_CALL_BONUS, LOGISTICS, WEAPON_TUNING, TOWER_TUNING, RAPID_CYCLE, FUNDING_DRIVE }

static var _cache: Array = []


static func all() -> Array:
	if _cache.is_empty():
		_cache = _build()
	return _cache


static func count() -> int:
	return all().size()


static func get_def(id: int) -> Dictionary:
	return all()[id]


## Price of the next level when currently at level. C# Math.Round is half-to-even, so this rounds the same way.
static func next_cost(def: Dictionary, level: int) -> int:
	return _round_even(float(int(def["base_cost"])) * pow(1.5, float(level)))


static func _build() -> Array:
	return [
		_def(UpgradeId.CORE_ARMOR, "Core Armor", "+5 core HP per level", 6, 120),
		_def(UpgradeId.OVERKILL_ENGINE, "Overkill Engine", "Overkill credit ratio +0.15 per level", 5, 150),
		_def(UpgradeId.EARLY_CALL_BONUS, "Early Call Bonus", "Early wave bonus +25% per level", 4, 100),
		_def(UpgradeId.LOGISTICS, "Logistics", "Towers cost 8% less per level", 5, 130),
		_def(UpgradeId.WEAPON_TUNING, "Weapon Tuning", "Weapon damage +12% per level", 5, 140),
		_def(UpgradeId.TOWER_TUNING, "Tower Tuning", "Tower damage +12% per level", 5, 140),
		_def(UpgradeId.RAPID_CYCLE, "Rapid Cycle", "Weapon cooldown -6% per level", 5, 160),
		_def(UpgradeId.FUNDING_DRIVE, "Funding Drive", "+60 starting credits per level", 5, 90),
	]


static func _def(id: int, display_name: String, desc: String, max_level: int, base_cost: int) -> Dictionary:
	return {"id": id, "name": display_name, "description": desc, "max_level": max_level, "base_cost": base_cost}


## Round half to even, matching C# Math.Round(double).
static func _round_even(x: float) -> int:
	var f: float = floor(x)
	var diff: float = x - f
	var whole: int = int(f)
	if diff > 0.5:
		return whole + 1
	if diff < 0.5:
		return whole
	return whole if whole % 2 == 0 else whole + 1
