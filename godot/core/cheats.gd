# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name CheatCatalog
extends RefCounted
## Keypad cheat codes revealed by clearing chapters. Port of Cheats.cs (CheatCatalog).
##
## Def dict: {code: String, chapter: int, effect: int (CheatEffect), amount: int, title: String, text: String}
## amount is 0 for effects that carry no number. find / for_chapter / for_effect return {} when nothing matches.

enum CheatEffect { BANK_CREDITS, OVERKILL_BOOST, CORE_BOOST, START_CREDITS, RAPID_FIRE, ARSENAL_KEY }

## Effect names as stored in Profile.pending. Index equals the CheatEffect int.
const EFFECT_NAMES: Array = ["BANK_CREDITS", "OVERKILL_BOOST", "CORE_BOOST", "START_CREDITS", "RAPID_FIRE", "ARSENAL_KEY"]

static var _cache: Array = []


static func all() -> Array:
	if _cache.is_empty():
		_cache = [
			_def("1974", 0, CheatEffect.BANK_CREDITS, 750, "Armory Credit Drop", "+750 bank credits, instantly"),
			_def("3316", 1, CheatEffect.OVERKILL_BOOST, 0, "Overkill Surge", "Overkill ratio doubled in the next battle"),
			_def("7742", 2, CheatEffect.CORE_BOOST, 10, "Breaker Override", "+10 core HP in the next battle"),
			_def("5150", 3, CheatEffect.START_CREDITS, 400, "Gold Reserve", "+400 starting credits in the next battle"),
			_def("8080", 4, CheatEffect.RAPID_FIRE, 0, "Thunder Rune", "Weapon cooldowns halved in the next battle"),
			_def("9001", 5, CheatEffect.ARSENAL_KEY, 0, "Arsenal Key", "Every weapon and tower unlocked permanently"),
		]
	return _cache


static func find(code: String) -> Dictionary:
	for c in all():
		if c["code"] == code:
			return c
	return {}


static func for_chapter(chapter: int) -> Dictionary:
	for c in all():
		if c["chapter"] == chapter:
			return c
	return {}


static func for_effect(effect: int) -> Dictionary:
	for c in all():
		if c["effect"] == effect:
			return c
	return {}


## Stored name for a CheatEffect, e.g. "OVERKILL_BOOST".
static func effect_name(effect: int) -> String:
	return EFFECT_NAMES[effect]


## Inverse of effect_name. Returns -1 for unknown names.
static func effect_from_name(effect_text: String) -> int:
	return EFFECT_NAMES.find(effect_text)


static func _def(code: String, chapter: int, effect: int, amount: int, title: String, text: String) -> Dictionary:
	return {"code": code, "chapter": chapter, "effect": effect, "amount": amount, "title": title, "text": text}
