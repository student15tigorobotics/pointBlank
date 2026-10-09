class_name Balance
extends RefCounted
## Tuning tables. Port of Balance.cs; numbers copied exactly.

enum EnemyKind { DRONE, WALKER, SHADE, BRUTE, TITAN }
enum MeshShape { TETRA, OCTA, ICOSA }
enum WeaponKind { BLASTER, SCATTER, RAIL, ARC, NOVA }
enum TowerKind { TURRET, TESLA, FROST, MORTAR, SNIPER }
enum ThemeKind { SPACE_OPERA, METROPOLIS, NOIR_HARBOR, EGYPT, NORSE, NEON_FUTURE }

# Logical battlefield: square of side 3 m centred on the table origin, table top at y = 0.
const FIELD_HALF: float = 1.5
const PAD_SPACING: float = 0.2
const PAD_CLEARANCE: float = 0.14
const ENEMY_BASE_CAPACITY: float = 2500.0  # design target, adapted at runtime by quality
const MAX_ENEMIES: int = 6000
const MAX_TOWERS: int = 48
const MAX_TOWER_LEVEL: int = 3

const PREP_SECONDS: float = 25.0
const EARLY_CALL_CREDITS_PER_SECOND: float = 10.0
const WAVE_CLEAR_BASE: float = 20.0
const WAVE_CLEAR_PER_WAVE: float = 6.0
const BASE_OVERKILL_RATIO: float = 0.25
const BASE_CORE_HP: int = 20
const TOWER_SELL_PERCENT: int = 60
const TOWER_UPGRADE_COST_FACTOR: float = 0.6
const TOWER_UPGRADE_DAMAGE: float = 1.45
const TOWER_UPGRADE_COOLDOWN: float = 0.9
const STAR3_RATIO: float = 0.8
const STAR2_RATIO: float = 0.4


## keys: name, hp, speed, scale, hover, core_damage, reward, shape
static func enemy(kind: int) -> Dictionary:
	match kind:
		EnemyKind.DRONE:
			return {"name": "Drone", "hp": 5.0, "speed": 0.55, "scale": 0.035, "hover": 0.0, "core_damage": 1, "reward": 1, "shape": MeshShape.TETRA}
		EnemyKind.WALKER:
			return {"name": "Walker", "hp": 14.0, "speed": 0.38, "scale": 0.05, "hover": 0.0, "core_damage": 1, "reward": 2, "shape": MeshShape.OCTA}
		EnemyKind.SHADE:
			return {"name": "Shade", "hp": 22.0, "speed": 0.50, "scale": 0.05, "hover": 0.06, "core_damage": 2, "reward": 3, "shape": MeshShape.OCTA}
		EnemyKind.BRUTE:
			return {"name": "Brute", "hp": 90.0, "speed": 0.22, "scale": 0.09, "hover": 0.0, "core_damage": 5, "reward": 8, "shape": MeshShape.ICOSA}
		_:
			return {"name": "Titan", "hp": 1600.0, "speed": 0.12, "scale": 0.22, "hover": 0.0, "core_damage": 20, "reward": 150, "shape": MeshShape.ICOSA}


## keys: name, cooldown, damage, range, cone_deg, radius, count, unlock_cost
## count = max targets per shot, radius = splash / chain / line tolerance in meters.
static func weapon(kind: int) -> Dictionary:
	match kind:
		WeaponKind.BLASTER:
			return {"name": "Blaster", "cooldown": 0.16, "damage": 4.0, "range": 6.0, "cone_deg": 4.0, "radius": 0.0, "count": 1, "unlock_cost": 0}
		WeaponKind.SCATTER:
			return {"name": "Scatter", "cooldown": 0.65, "damage": 5.0, "range": 1.2, "cone_deg": 16.0, "radius": 0.0, "count": 12, "unlock_cost": 300}
		WeaponKind.RAIL:
			return {"name": "Rail", "cooldown": 1.1, "damage": 45.0, "range": 4.0, "cone_deg": 0.0, "radius": 0.05, "count": 999, "unlock_cost": 500}
		WeaponKind.ARC:
			return {"name": "Arc", "cooldown": 0.45, "damage": 9.0, "range": 5.0, "cone_deg": 6.0, "radius": 0.22, "count": 6, "unlock_cost": 700}
		_:
			return {"name": "Nova", "cooldown": 1.5, "damage": 38.0, "range": 6.0, "cone_deg": 0.0, "radius": 0.22, "count": 1, "unlock_cost": 900}


## keys: name, cost, range, cooldown, damage, splash, slow, slow_seconds, chain
static func tower(kind: int) -> Dictionary:
	match kind:
		TowerKind.TURRET:
			return {"name": "Turret", "cost": 60, "range": 0.45, "cooldown": 0.22, "damage": 5.0, "splash": 0.0, "slow": 1.0, "slow_seconds": 0.0, "chain": 0}
		TowerKind.TESLA:
			return {"name": "Tesla", "cost": 110, "range": 0.38, "cooldown": 0.9, "damage": 13.0, "splash": 0.2, "slow": 1.0, "slow_seconds": 0.0, "chain": 4}
		TowerKind.FROST:
			return {"name": "Frost", "cost": 90, "range": 0.36, "cooldown": 0.5, "damage": 1.2, "splash": 0.0, "slow": 0.45, "slow_seconds": 1.2, "chain": 0}
		TowerKind.MORTAR:
			return {"name": "Mortar", "cost": 130, "range": 0.8, "cooldown": 2.2, "damage": 28.0, "splash": 0.18, "slow": 1.0, "slow_seconds": 0.0, "chain": 0}
		_:
			return {"name": "Sniper", "cost": 170, "range": 1.1, "cooldown": 2.6, "damage": 190.0, "splash": 0.0, "slow": 1.0, "slow_seconds": 0.0, "chain": 0}
