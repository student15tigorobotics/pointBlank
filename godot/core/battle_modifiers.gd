# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name BattleModifiers
extends RefCounted
## Upgrade-derived rules applied to one battle. Port of Economy.cs BattleModifiers.

var core_max_hp: int = Balance.BASE_CORE_HP
var overkill_ratio: float = Balance.BASE_OVERKILL_RATIO
var early_bonus_mult: float = 1.0
var tower_cost_mult: float = 1.0
var weapon_damage_mult: float = 1.0
var tower_damage_mult: float = 1.0
var weapon_cooldown_mult: float = 1.0
var start_credits: int = 0


## Same values as C# BattleModifiers.Default.
static func defaults() -> BattleModifiers:
	return BattleModifiers.new()
