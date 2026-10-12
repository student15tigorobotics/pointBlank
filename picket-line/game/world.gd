# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name World
extends Node3D
## Visual root for a sector: environment, sky, sun, the aim camera with shake, the picket station cockpit, enemy
## views and effects. Reads sim state only; never changes game rules.

const THEMES := [
	{"name": "Outer Picket", "sky_a": Color(0.02, 0.04, 0.12), "sky_b": Color(0.05, 0.10, 0.28),
		"nebula": Color(0.20, 0.12, 0.45), "planet": Color(0.25, 0.40, 0.75), "ring": true,
		"accent": Color(0.30, 0.90, 1.00), "fog": Color(0.05, 0.10, 0.25), "fog_density": 0.00035,
		"sun": Color(1.00, 0.95, 0.85)},
	{"name": "Debris Field", "sky_a": Color(0.12, 0.04, 0.02), "sky_b": Color(0.30, 0.12, 0.05),
		"nebula": Color(0.50, 0.25, 0.10), "planet": Color(0.70, 0.40, 0.20), "ring": false,
		"accent": Color(1.00, 0.55, 0.15), "fog": Color(0.25, 0.10, 0.05), "fog_density": 0.00070,
		"sun": Color(1.00, 0.85, 0.65)},
	{"name": "Ion Storm", "sky_a": Color(0.06, 0.01, 0.12), "sky_b": Color(0.20, 0.05, 0.30),
		"nebula": Color(0.60, 0.10, 0.70), "planet": Color(0.45, 0.20, 0.80), "ring": false,
		"accent": Color(1.00, 0.20, 0.90), "fog": Color(0.20, 0.05, 0.30), "fog_density": 0.00040,
		"sun": Color(0.95, 0.80, 1.00)},
	{"name": "Carrier Lane", "sky_a": Color(0.01, 0.07, 0.07), "sky_b": Color(0.04, 0.22, 0.20),
		"nebula": Color(0.10, 0.50, 0.40), "planet": Color(0.20, 0.70, 0.55), "ring": false,
		"accent": Color(0.40, 1.00, 0.50), "fog": Color(0.05, 0.20, 0.18), "fog_density": 0.00040,
		"sun": Color(0.90, 1.00, 0.92)},
	{"name": "Shattered Ring", "sky_a": Color(0.05, 0.10, 0.16), "sky_b": Color(0.25, 0.42, 0.60),
		"nebula": Color(0.50, 0.70, 0.90), "planet": Color(0.70, 0.85, 1.00), "ring": true,
		"accent": Color(0.60, 0.95, 1.00), "fog": Color(0.40, 0.55, 0.70), "fog_density": 0.00030,
		"sun": Color(0.95, 0.97, 1.00)},
	{"name": "Dreadnought Gate", "sky_a": Color(0.10, 0.01, 0.01), "sky_b": Color(0.30, 0.03, 0.02),
		"nebula": Color(0.50, 0.05, 0.10), "planet": Color(0.80, 0.15, 0.10), "ring": false,
		"accent": Color(1.00, 0.20, 0.25), "fog": Color(0.25, 0.03, 0.04), "fog_density": 0.00060,
		"sun": Color(1.00, 0.30, 0.20)},
]

const SkyScript := preload("res://game/sky.gd")
const BASE_FOV := 75.0
const AIM_FOV := 26.0
const SHAKE_ROT := 0.0105
const SHAKE_MOVE := 0.15
const TRAUMA_DECAY := 1.6

var _built := false
var _pending_sector := 0
var _sector := -1
var _accent := Color(0.3, 0.9, 1.0)
var _env: Environment
var _sky # SkyScript instance (untyped: Sky has no class_name)
var _sun: DirectionalLight3D
var _camera: Camera3D
var _enemy_view: EnemyView
var _fx: Fx
var _cockpit: Node3D
var _barrel_root: Node3D
var _edge_mat: StandardMaterial3D
var _status_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D
var _flash_quad: MeshInstance3D
var _trauma := 0.0
var _time := 0.0
var _fov_now := BASE_FOV
var _recoil := 0.0
var _lag := Vector2.ZERO
var _last_rail := Vector2.ZERO
var _flash_alpha := 0.0
var _flash_col := Color(1.0, 0.3, 0.2)


## Builds the sector visuals once: environment, sky, sun, aim camera, cockpit, enemy view and fx.
func build(settings: Dictionary) -> void:
	if _built:
		return
	_built = true
	var quality: int = int(settings.get("quality", 1))
	var fov: float = float(settings.get("fov", BASE_FOV))
	_fov_now = fov

	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.01, 0.02, 0.05)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.22, 0.27, 0.36)
	_env.ambient_light_energy = 0.7
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 4.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.8
	_env.glow_bloom = 0.08
	_env.glow_hdr_threshold = 1.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.06
	_env.adjustment_saturation = 1.08
	_env.fog_enabled = true
	_env.fog_sky_affect = 0.2
	_env.ssao_enabled = quality >= 1
	_env.ssil_enabled = quality >= 1
	world_env.environment = _env
	add_child(world_env)

	_sky = SkyScript.new()
	_sky.name = "Sky"
	add_child(_sky)
	_sky.build()

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_energy = 1.4
	_sun.shadow_enabled = quality >= 1
	_sun.directional_shadow_max_distance = 250.0
	_sun.basis = Basis.looking_at(-SkyScript.sun_direction(), Vector3.UP)
	add_child(_sun)

	_camera = Camera3D.new()
	_camera.name = "Aim"
	_camera.fov = _fov_now
	_camera.near = 0.05
	_camera.far = 6000.0
	add_child(_camera)
	_camera.current = true

	_build_cockpit()

	_enemy_view = EnemyView.new()
	_enemy_view.name = "EnemyView"
	add_child(_enemy_view)

	_fx = Fx.new()
	_fx.name = "Fx"
	add_child(_fx)

	set_sector(_pending_sector)


## Applies a sector theme: sky colours, nebula, planet and ring, fog, accent (enemies, fx, cockpit) and sun colour.
func set_sector(index: int) -> void:
	var i := clampi(index, 0, THEMES.size() - 1)
	if not _built:
		_pending_sector = i
		return
	_sector = i
	var theme: Dictionary = THEMES[i]
	_sky.set_theme(theme)
	_env.background_color = theme.sky_a
	_env.fog_light_color = theme.fog
	_env.fog_density = float(theme.fog_density)
	_accent = theme.accent
	_enemy_view.set_accent(_accent)
	_sun.light_color = theme.sun
	_edge_mat.emission = _accent
	_flash_col = _accent.lerp(Color(1.0, 0.3, 0.2), 0.5)


## The aim camera (the lead may read its transform or unproject through it).
func camera() -> Camera3D:
	return _camera


## Adds screen shake trauma (0..1). It decays at TRAUMA_DECAY per second.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Per frame: camera from the station aim and rail, shake, FOV zoom, then the battlefield, projectiles and sky.
func render(sim: Sim, dt: float, settings: Dictionary) -> void:
	if not _built or sim == null:
		return
	_time += dt
	var st := sim.station

	# Aim: basis matches Balance.aim_dir (forward is -Z).
	var aim_basis := Basis(Vector3.UP, st.yaw) * Basis(Vector3.RIGHT, st.pitch)

	# Trauma shake, squared and scaled by the shake setting.
	_trauma = maxf(0.0, _trauma - TRAUMA_DECAY * dt)
	var gain: float = clampf(float(settings.get("shake", 1.0)), 0.0, 1.0)
	var s: float = _trauma * _trauma * gain
	var t := _time
	var rot := Basis.from_euler(Vector3(
		SHAKE_ROT * s * sin(t * 23.0 + 0.4),
		SHAKE_ROT * s * sin(t * 19.0 + 1.9),
		SHAKE_ROT * s * sin(t * 29.0 + 3.1)))
	var off := Vector3(
		SHAKE_MOVE * s * sin(t * 17.0 + 0.7),
		SHAKE_MOVE * s * sin(t * 21.3 + 2.2),
		0.0)
	var cam_basis := aim_basis * rot
	var cam_pos := st.rail_point() + aim_basis * off
	_camera.global_transform = Transform3D(cam_basis, cam_pos)

	# FOV: settings value normally, zoomed while scoping.
	var base_fov: float = float(settings.get("fov", BASE_FOV))
	var target := AIM_FOV if st.scoping else base_fov
	_fov_now = lerpf(_fov_now, target, clampf(dt * 10.0, 0.0, 1.0))
	_camera.fov = _fov_now

	_update_cockpit(sim, dt)

	_enemy_view.sync(sim, dt, settings)
	_fx.render_projectiles(sim.projectiles.active_player(), sim.projectiles.active_enemy_shells())
	_fx.update(dt)
	_sky.update(dt, _camera)


## Dispatches sim events to the effects and the enemy view.
func handle_events(events: Array) -> void:
	for ev: Dictionary in events:
		var type_name: String = String(ev.get("type", ""))
		match type_name:
			"hit":
				_enemy_view.flash(int(ev.get("enemy_id", 0)), 1.0)
			"kill":
				add_trauma(0.25)
			"player_hit":
				if not bool(ev.get("blocked", false)):
					add_trauma(0.5)
					_flash_alpha = clampf(float(ev.get("damage", 10.0)) / 20.0, 0.25, 1.0)
			"boss_phase":
				add_trauma(0.6)
			"game_over":
				add_trauma(1.0)
			"shot":
				var w := int(ev.get("weapon", 0))
				var kick := 0.2
				if w == Balance.Weapon.LANCE:
					kick = 1.0
				elif w == Balance.Weapon.FLAK:
					kick = 0.8
				elif w == Balance.Weapon.SWARM:
					kick = 0.4
				_recoil = maxf(_recoil, kick)
			_:
				pass
		_fx.spawn_event(ev, _accent)


## Removes every alien view and clears the effects.
func clear_battlefield() -> void:
	if not _built:
		return
	_enemy_view.clear()
	_fx.clear()


## Shows or hides the battlefield (aliens and effects); menus hide it.
func set_battlefield_visible(on: bool) -> void:
	if not _built:
		return
	_enemy_view.visible = on
	_fx.visible = on


# ---- Cockpit ------------------------------------------------------------------------------------------------------

func _build_cockpit() -> void:
	_cockpit = Node3D.new()
	_cockpit.name = "Cockpit"
	_camera.add_child(_cockpit)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.08, 0.09, 0.11)
	metal.metallic = 0.7
	metal.roughness = 0.45

	_edge_mat = StandardMaterial3D.new()
	_edge_mat.albedo_color = Color(0.05, 0.05, 0.06)
	_edge_mat.emission_enabled = true
	_edge_mat.emission = _accent
	_edge_mat.emission_energy_multiplier = 3.0

	var barrel_mat := StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.22, 0.23, 0.26)
	barrel_mat.metallic = 0.9
	barrel_mat.roughness = 0.3

	_status_mat = StandardMaterial3D.new()
	_status_mat.albedo_color = Color(0.05, 0.1, 0.08)
	_status_mat.emission_enabled = true
	_status_mat.emission = Color(0.2, 1.0, 0.6)
	_status_mat.emission_energy_multiplier = 4.0

	# Frame: dark members with emissive edge strips, framing the view at 0.85 m.
	_add_box(metal, Vector3(2.6, 0.12, 0.06), Vector3(0.0, 0.66, -0.9))
	_add_box(metal, Vector3(2.6, 0.12, 0.06), Vector3(0.0, -0.66, -0.9))
	_add_box(metal, Vector3(0.06, 1.4, 0.06), Vector3(-1.3, 0.0, -0.9))
	_add_box(metal, Vector3(0.06, 1.4, 0.06), Vector3(1.3, 0.0, -0.9))
	_add_box(_edge_mat, Vector3(2.4, 0.03, 0.03), Vector3(0.0, 0.6, -0.85))
	_add_box(_edge_mat, Vector3(2.4, 0.03, 0.03), Vector3(0.0, -0.6, -0.85))
	_add_box(_edge_mat, Vector3(0.03, 1.2, 0.03), Vector3(-1.2, 0.0, -0.85))
	_add_box(_edge_mat, Vector3(0.03, 1.2, 0.03), Vector3(1.2, 0.0, -0.85))
	# Corner gussets, angled toward the centre.
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var g := _add_box(metal, Vector3(0.05, 0.5, 0.05), Vector3(1.05 * sx, 0.42 * sy, -0.88))
			g.rotation = Vector3(0.0, 0.0, -0.55 * sx * sy)
	# Mullion: vertical strut in the upper half, out of the central sightline.
	_add_box(metal, Vector3(0.05, 0.5, 0.05), Vector3(-0.85, 0.36, -0.88))
	_add_box(metal, Vector3(0.05, 0.5, 0.05), Vector3(0.85, 0.36, -0.88))

	# Console along the bottom edge, with a small status light lower left.
	_add_box(metal, Vector3(2.7, 0.22, 0.45), Vector3(0.0, -0.8, -0.95))
	_add_box(_edge_mat, Vector3(2.5, 0.02, 0.02), Vector3(0.0, -0.69, -0.72))
	var status := _add_box(_status_mat, Vector3(0.12, 0.05, 0.02), Vector3(-0.7, -0.78, -0.72))
	status.name = "StatusGlow"

	# Gun barrel: lower right, out of the line of fire. Points along -Z with a short housing.
	_barrel_root = Node3D.new()
	_barrel_root.name = "Barrel"
	_cockpit.add_child(_barrel_root)
	var housing := MeshInstance3D.new()
	var hbox := BoxMesh.new()
	hbox.size = Vector3(0.24, 0.2, 0.5)
	housing.mesh = hbox
	housing.material_override = metal
	housing.position = Vector3(0.22, -0.28, -0.45)
	_barrel_root.add_child(housing)
	var barrel := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.05
	bcyl.bottom_radius = 0.06
	bcyl.height = 1.3
	bcyl.radial_segments = 10
	bcyl.rings = 1
	barrel.mesh = bcyl
	barrel.material_override = barrel_mat
	barrel.transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), Vector3(0.22, -0.28, -0.85))
	_barrel_root.add_child(barrel)

	# Full-screen damage flash quad, additive, faces the camera.
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_flash_mat.albedo_color = Color(1.0, 0.3, 0.2, 0.0)
	var fq := QuadMesh.new()
	fq.size = Vector2(3.0, 1.8)
	_flash_quad = MeshInstance3D.new()
	_flash_quad.mesh = fq
	_flash_quad.material_override = _flash_mat
	_flash_quad.position = Vector3(0.0, 0.0, -0.4)
	_flash_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cockpit.add_child(_flash_quad)


func _add_box(mat: Material, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cockpit.add_child(m)
	return m


## Barrel recoil and lag, status light, and the damage flash. Runs every frame.
func _update_cockpit(sim: Sim, dt: float) -> void:
	_recoil = maxf(0.0, _recoil - 9.0 * dt)
	var rail: Vector2 = sim.station.rail
	var vel := (rail - _last_rail) / maxf(dt, 0.0001)
	_last_rail = rail
	_lag = _lag.lerp(Vector2(-vel.x, -vel.y) * 0.002, clampf(dt * 6.0, 0.0, 1.0))
	_barrel_root.transform = Transform3D(
		Basis.from_euler(Vector3(-_recoil * 0.035 + _lag.y, _lag.x, 0.0)),
		Vector3(0.0, 0.0, _recoil * 0.06))

	var hull_frac: float = sim.station.hull / Balance.STATION_HULL
	if hull_frac < 0.35:
		var blink := 0.5 + 0.5 * sin(_time * 9.0)
		_status_mat.emission = Color(1.0, 0.2, 0.15).lerp(Color(0.2, 0.05, 0.02), blink)
	else:
		_status_mat.emission = _accent.lerp(Color(0.2, 1.0, 0.6), 0.5)

	_flash_alpha = maxf(0.0, _flash_alpha - 2.5 * dt)
	_flash_mat.albedo_color = Color(_flash_col.r, _flash_col.g, _flash_col.b, _flash_alpha * 0.55)
