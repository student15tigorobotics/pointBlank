class_name UnlockCatalog
extends RefCounted
## One-time unlocks for weapons and towers. Port of Upgrades.cs (UnlockCatalog).
##
## Def dict: {key: String, title: String, cost: int}. Keys are "W:SCATTER" style (per port contract).

const WEAPON_NAMES: Array = ["BLASTER", "SCATTER", "RAIL", "ARC", "NOVA"]
const TOWER_NAMES: Array = ["TURRET", "TESLA", "FROST", "MORTAR", "SNIPER"]

static var _cache: Array = []


static func all() -> Array:
	if _cache.is_empty():
		_cache = [
			_def("W:SCATTER", "Scatter Cannon", int(Balance.weapon(Balance.WeaponKind.SCATTER)["unlock_cost"])),
			_def("W:RAIL", "Rail Lance", int(Balance.weapon(Balance.WeaponKind.RAIL)["unlock_cost"])),
			_def("W:ARC", "Chain Arc", int(Balance.weapon(Balance.WeaponKind.ARC)["unlock_cost"])),
			_def("W:NOVA", "Nova Grenade", int(Balance.weapon(Balance.WeaponKind.NOVA)["unlock_cost"])),
			_def("T:TESLA", "Tesla Coil", 250),
			_def("T:FROST", "Frost Emitter", 320),
			_def("T:MORTAR", "Mortar Battery", 400),
			_def("T:SNIPER", "Sniper Spire", 600),
		]
	return _cache


## "W:" + Balance.WeaponKind key name, e.g. "W:SCATTER".
static func weapon_key(kind: int) -> String:
	return "W:" + WEAPON_NAMES[kind]


## "T:" + Balance.TowerKind key name, e.g. "T:TESLA".
static func tower_key(kind: int) -> String:
	return "T:" + TOWER_NAMES[kind]


static func _def(key: String, title: String, cost: int) -> Dictionary:
	return {"key": key, "title": title, "cost": cost}
