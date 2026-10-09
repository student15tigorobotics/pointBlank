class_name Quality
extends RefCounted
## Frame-time governor. Averages over two seconds and trades render scale, mesh budget and spawn cap
## for frame rate when the headset falls behind its refresh target, then recovers when there is headroom.
## Port of Game/Quality.cs.

const TARGET_HZ: float = 90.0
const BUDGET_MS: float = 1000.0 / TARGET_HZ

var avg_ms: float = BUDGET_MS
var render_scale: float = 1.0
var spawn_cap: int = int(Balance.ENEMY_BASE_CAPACITY)
var mesh_budget: int = 1400
var tier: int = 1
var enabled: bool = true

var _acc: float = 0.0
var _acc_time: float = 0.0
var _frames: int = 0


## Call once per frame. xr may be null (desktop). renderer is the SwarmRenderer (or null); its mesh_budget is updated.
func tick(dt: float, xr: XRInterface, renderer: Object) -> void:
	_acc += dt * 1000.0
	_acc_time += dt
	_frames += 1
	if _acc_time < 2.0:
		return

	avg_ms = _acc / _frames
	_acc = 0.0
	_acc_time = 0.0
	_frames = 0
	if not enabled:
		return

	if avg_ms > BUDGET_MS * 1.08:
		render_scale = maxf(0.6, render_scale - 0.1)
		mesh_budget = maxi(300, mesh_budget - 200)
		spawn_cap = maxi(800, int(spawn_cap * 0.9))
	elif avg_ms < BUDGET_MS * 0.75:
		render_scale = minf(1.0, render_scale + 0.05)
		mesh_budget = mini(2000, mesh_budget + 100)
		spawn_cap = mini(Balance.MAX_ENEMIES, spawn_cap + 100)

	if xr != null:
		xr.render_target_size_multiplier = render_scale
	if renderer != null:
		renderer.set("mesh_budget", mesh_budget)


## Applies a player-chosen graphics tier (0 low, 1 medium, 2 high) as the starting point.
func set_tier(tier_index: int) -> void:
	tier = tier_index
	render_scale = 0.7 if tier_index == 0 else (0.85 if tier_index == 1 else 1.0)
	mesh_budget = 500 if tier_index == 0 else (1000 if tier_index == 1 else 1600)
	spawn_cap = 1200 if tier_index == 0 else (2000 if tier_index == 1 else 2500)
