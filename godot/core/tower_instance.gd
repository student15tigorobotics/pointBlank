class_name TowerInstance
extends RefCounted
## One placed tower. Port of Towers.cs TowerInstance.

var id: int = 0
var kind: int = 0
var level: int = 1
var x: float = 0.0
var z: float = 0.0
var cooldown: float = 0.0
var spent: int = 0  # total credits invested, used for sell value


## All arguments are optional, so TowerInstance.new() matches the C# object initialiser defaults.
func _init(p_id: int = 0, p_kind: int = 0, p_x: float = 0.0, p_z: float = 0.0, p_spent: int = 0) -> void:
	id = p_id
	kind = p_kind
	x = p_x
	z = p_z
	spent = p_spent
