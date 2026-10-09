class_name BattleEconomy
extends RefCounted
## Credits, core health and kill accounting for one battle. Port of Economy.cs BattleEconomy.

var credits: int = 0
var earned_total: int = 0
var core_hp: int = 0
var core_max_hp: int = 0
var overkill_ratio: float = 0.0
var early_bonus_mult: float = 1.0
var tower_cost_mult: float = 1.0

var kills: int = 0
var leaks: int = 0
var early_calls: int = 0
var overkill_credits: int = 0
var overkill_damage: float = 0.0

var _overkill_carry: float = 0.0
# Per-EnemyKind tables read once per battle, so on_kill/on_leak never build dictionaries.
var _rewards: PackedInt32Array = PackedInt32Array()
var _core_damage: PackedInt32Array = PackedInt32Array()


func _init(mods: BattleModifiers) -> void:
	core_max_hp = mods.core_max_hp
	core_hp = core_max_hp
	overkill_ratio = mods.overkill_ratio
	early_bonus_mult = mods.early_bonus_mult
	tower_cost_mult = mods.tower_cost_mult
	for k in range(Balance.EnemyKind.TITAN + 1):
		var e: Dictionary = Balance.enemy(k)
		_rewards.append(int(e["reward"]))
		_core_damage.append(int(e["core_damage"]))
	earn(mods.start_credits)


func core_destroyed() -> bool:
	return core_hp <= 0


func core_fraction() -> float:
	if core_max_hp <= 0:
		return 0.0
	return float(core_hp) / float(core_max_hp)


func earn(amount: int) -> void:
	if amount <= 0:
		return
	credits += amount
	earned_total += amount


func try_spend(amount: int) -> bool:
	if amount > credits:
		return false
	credits -= amount
	return true


func refund(amount: int) -> void:
	if amount > 0:
		credits += amount


## C# uses Math.Round (banker's rounding), so _round_even is used wherever C# rounds.
func tower_cost(kind: int) -> int:
	var s: Dictionary = Balance.tower(kind)
	return _round_even(float(s["cost"]) * tower_cost_mult)


func on_kill(kind: int, overkill: float) -> void:
	kills += 1
	earn(_rewards[kind])
	if overkill <= 0.0:
		return

	overkill_damage += overkill
	var raw: float = overkill * overkill_ratio + _overkill_carry
	var whole: int = int(raw)
	_overkill_carry = raw - float(whole)
	if whole > 0:
		overkill_credits += whole
		earn(whole)


func on_leak(kind: int) -> void:
	leaks += 1
	core_hp = maxi(0, core_hp - _core_damage[kind])


func on_early_call(bonus: int) -> void:
	early_calls += 1
	earn(bonus)


static func early_call_bonus(remaining_seconds: float, mult: float) -> int:
	if remaining_seconds <= 0.0:
		return 0
	return _round_even(remaining_seconds * Balance.EARLY_CALL_CREDITS_PER_SECOND * mult)


static func wave_clear_bonus(wave_index: int) -> int:
	return int(Balance.WAVE_CLEAR_BASE + Balance.WAVE_CLEAR_PER_WAVE * float(wave_index))


static func stars(core_fraction_value: float, cleared: bool) -> int:
	if not cleared:
		return 0
	if core_fraction_value >= Balance.STAR3_RATIO:
		return 3
	if core_fraction_value >= Balance.STAR2_RATIO:
		return 2
	return 1


## Bank credits paid out when a stage is cleared.
static func bank_payout(earned: int, stars_count: int, first_clear: bool) -> int:
	return int(float(earned) * 0.2) + stars_count * 150 + (300 if first_clear else 0)


## Round half to even, matching C# Math.Round(double).
static func _round_even(x: float) -> int:
	var f: float = floorf(x)
	var diff: float = x - f
	var base: int = int(f)
	if diff > 0.5:
		return base + 1
	if diff < 0.5:
		return base
	return base if base % 2 == 0 else base + 1
