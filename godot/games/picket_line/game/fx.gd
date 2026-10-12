# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Fx
extends Node3D
## Pooled visual effects: explosions (sprite, shockwave ring, particles), impact sparks, beams, flash lights, and the
## per-frame projectile drawing. Nothing is created after build(); every effect has a cap and is recycled.

const MUZZLE_LOCAL := Vector3(0.22, -0.28, -1.5)
const BOOM_POOL := 24
const SPARK_POOL := 8
const BEAM_POOL := 16
const LIGHT_POOL := 8
const PROJ_POOL := 160
const GOLD := Color(1.0, 0.78, 0.25, 1.0)
const ENEMY_BEAM := Color(1.0, 0.3, 0.18, 1.0)
const SHIMMER := Color(0.45, 0.9, 1.0, 1.0)


class Boom extends RefCounted:
	var root: Node3D = null
	var sprite: MeshInstance3D = null
	var sprite_mat: StandardMaterial3D = null
	var ring: MeshInstance3D = null
	var ring_mat: StandardMaterial3D = null
	var parts: CPUParticles3D = null
	var active := false
	var t := 0.0
	var life := 1.0
	var size := 1.0
	var color := Color.WHITE
	var intensity := 1.0


var _built := false
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _glow_tex: GradientTexture2D
var _ring_tex: GradientTexture2D
var _particle_mesh: QuadMesh
var _spark_mat: StandardMaterial3D
var _quad: QuadMesh
var _booms: Array = []
var _boom_next := 0
var _sparks: Array = []
var _spark_next := 0
var _beams: Array = []
var _beam_mats: Array = []
var _beam_next := 0
var _beam_t: PackedFloat32Array = PackedFloat32Array()
var _beam_life: PackedFloat32Array = PackedFloat32Array()
var _lights: Array = []
var _light_next := 0
var _light_t: PackedFloat32Array = PackedFloat32Array()
var _light_life: PackedFloat32Array = PackedFloat32Array()
var _light_energy: PackedFloat32Array = PackedFloat32Array()
var _proj_nodes: Array = []
var _proj_used := 0
var _mat_pulse: ShaderMaterial
var _mat_lance_halo: ShaderMaterial
var _mat_lance_core: ShaderMaterial
var _mat_swarm: ShaderMaterial
var _mat_flak: StandardMaterial3D
var _mat_halo: StandardMaterial3D
var _mat_shell: StandardMaterial3D
var _mat_shell_trail: StandardMaterial3D
var _mat_smoke: StandardMaterial3D


func _ready() -> void:
	_ensure_built()


## Routes one sim event to the matching effect. accent is the sector accent colour.
func spawn_event(ev: Dictionary, accent: Color) -> void:
	_ensure_built()
	var kind_name: String = String(ev.get("type", ""))
	match kind_name:
		"hit":
			var p := _pos(ev)
			if bool(ev.get("crit", false)):
				spark(p, (_camera_pos() - p).normalized(), GOLD, 1.6)
				_boom(p, 2.4, GOLD, 0.25, 1.0, true, false)
			else:
				spark(p, (_camera_pos() - p).normalized(), accent.lightened(0.4), 1.0)
		"kill":
			var p2 := _pos(ev)
			var kind := int(ev.get("kind", 0))
			var size := 3.5
			if bool(ev.get("boss", false)) or kind == PLBalance.Kind.DREADNOUGHT:
				size = 30.0
			elif kind == PLBalance.Kind.CARRIER:
				size = 14.0
			elif kind == PLBalance.Kind.GUNSHIP or kind == PLBalance.Kind.BOMBER:
				size = 7.0
			explode(p2, size, accent)
			flash_at(p2, accent.lightened(0.3), 6.0, size * 4.0)
		"detonate":
			var p3 := _pos(ev)
			explode(p3, float(ev.get("radius", 8.0)) * 0.9, Color(1.0, 0.55, 0.2, 1.0))
			flash_at(p3, Color(1.0, 0.6, 0.25, 1.0), 4.0, 18.0)
		"crash":
			explode(_pos(ev), 4.5, Color(1.0, 0.5, 0.2, 1.0))
		"player_hit":
			if bool(ev.get("blocked", false)):
				_boom(_camera_point(3.0), 2.0, SHIMMER, 0.3, 0.4, true, false)
		"enemy_fire":
			if String(ev.get("mode", "")) == "beam":
				var a: Vector3 = ev.get("from", Vector3.ZERO)
				var b: Vector3 = ev.get("to", Vector3.ZERO)
				beam(a, b, ENEMY_BEAM, 0.14)
		"launch":
			var p4 := _pos(ev)
			flash_at(p4, accent, 4.0, 14.0)
			_boom(p4, 4.0, accent, 0.4, 0.8, true, true)
		"boss_phase":
			var p5 := _pos(ev)
			_boom(p5, 26.0, accent, 1.0, 1.4, true, true)
			flash_at(p5, accent.lightened(0.5), 16.0, 160.0)
		"shell_miss":
			_boom(_pos(ev), 1.6, Color(1.0, 0.6, 0.3, 1.0), 0.35, 0.6, false, true)
		"shot":
			_muzzle_flash(int(ev.get("weapon", 0)))
		"snap":
			_boom(_pos(ev), 6.0, GOLD, 0.45, 0.8, true, false)
		"weak_hit":
			var p6 := _pos(ev)
			flash_at(p6, GOLD, 5.0, 16.0)
			_boom(p6, 4.0, GOLD, 0.35, 0.9, true, false)
		"game_over":
			for i in 10:
				var d := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.8), _rng.randf_range(-1.0, 1.0))
				_boom(d.normalized() * _rng.randf_range(20.0, 60.0), _rng.randf_range(10.0, 18.0),
					accent, 1.0, 1.4, true, true)
			flash_at(Vector3.ZERO, accent, 14.0, 300.0)
		"sector_clear":
			for i in 6:
				var dir := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.0, 0.6), -1.0).normalized()
				var col := Color.from_hsv(_rng.randf(), 0.5, 1.0)
				var at := dir * 500.0
				_boom(at, 16.0, col, 1.2, 1.6, true, true)
				flash_at(at, col, 10.0, 120.0)
		_:
			pass


## Explosion at pos. size is roughly the diameter in metres. Uses a pooled boom with sprite, ring and particles.
func explode(pos: Vector3, size: float, accent: Color) -> void:
	_ensure_built()
	var life := clampf(0.3 + size * 0.03, 0.3, 1.2)
	_boom(pos, size, accent, life, 1.0, true, true)


## Impact spark: a short burst of particles at pos, spreading along normal.
func spark(pos: Vector3, normal: Vector3, color: Color, size: float) -> void:
	_ensure_built()
	var p: CPUParticles3D = _sparks[_spark_next]
	_spark_next = (_spark_next + 1) % _sparks.size()
	var n := normal
	if n.length_squared() < 0.0001:
		n = Vector3.UP
	p.position = pos
	p.direction = n.normalized()
	p.spread = 50.0
	p.initial_velocity_min = 5.0 * size
	p.initial_velocity_max = 14.0 * size
	p.scale_amount_min = 0.3 * size
	p.scale_amount_max = 0.7 * size
	p.color = color
	p.emitting = true


## Additive flash light at pos that fades out over about 0.3 s.
func flash_at(pos: Vector3, color: Color, intensity: float, radius: float) -> void:
	_ensure_built()
	var i := _light_next
	_light_next = (_light_next + 1) % _lights.size()
	var l: OmniLight3D = _lights[i]
	l.position = pos
	l.light_color = color
	l.omni_range = maxf(1.0, radius)
	l.light_energy = intensity
	l.visible = true
	_light_t[i] = 0.0
	_light_life[i] = 0.3
	_light_energy[i] = intensity


## Straight additive beam from a to b that fades over seconds.
func beam(from: Vector3, to: Vector3, color: Color, seconds: float) -> void:
	_ensure_built()
	var seg := to - from
	var seg_len: float = seg.length()
	if seg_len < 0.5:
		return
	var i := _beam_next
	_beam_next = (_beam_next + 1) % _beams.size()
	var node: MeshInstance3D = _beams[i]
	var mat: ShaderMaterial = _beam_mats[i]
	node.transform = _line_xf(from, to, 0.6, _camera_pos())
	mat.set_shader_parameter("beam_col", color)
	mat.set_shader_parameter("intensity", 3.2)
	mat.set_shader_parameter("alpha", 1.0)
	node.visible = true
	_beam_t[i] = 0.0
	_beam_life[i] = maxf(0.02, seconds)


## Draws every player shot and enemy shell with pooled quads. Called each frame.
func render_projectiles(player: Array, shells: Array) -> void:
	_ensure_built()
	_proj_used = 0
	var cam_pos := _camera_pos()
	for p: Dictionary in player:
		var pos: Vector3 = p.pos
		var dir: Vector3 = p.dir
		var prev: Vector3 = p.prev
		var weapon: int = int(p.weapon)
		match weapon:
			PLBalance.Weapon.PULSE:
				_streak(pos - dir * 12.0, pos, 0.16, _mat_pulse, cam_pos)
			PLBalance.Weapon.LANCE:
				_streak(prev, pos, 1.3, _mat_lance_halo, cam_pos)
				_streak(prev, pos, 0.35, _mat_lance_core, cam_pos)
			PLBalance.Weapon.FLAK:
				_orb(pos, 0.7, _mat_flak)
				_orb(pos, 1.5 + 0.3 * sin(_time * 40.0 + pos.x), _mat_halo)
			PLBalance.Weapon.SWARM:
				_streak(pos - dir * 2.2, pos, 0.28, _mat_swarm, cam_pos)
				_orb(pos - dir * 2.6, 0.9, _mat_smoke)
				_orb(pos - dir * 4.6, 1.5, _mat_smoke)
			_:
				pass
	for s: Dictionary in shells:
		var pos2: Vector3 = s.pos
		var from: Vector3 = s.from
		_orb(pos2, 1.8, _mat_shell)
		var back: Vector3 = from - pos2
		var back_len: float = back.length()
		if back_len > 0.01:
			var back_dir: Vector3 = back / back_len
			for i in range(1, 4):
				_orb(pos2 + back_dir * (float(i) * 1.8), 1.8 * (1.0 - 0.22 * float(i)), _mat_shell_trail)
	for i in range(_proj_used, _proj_nodes.size()):
		var n: MeshInstance3D = _proj_nodes[i]
		n.visible = false


## Advances every pooled effect by dt.
func update(dt: float) -> void:
	if not _built:
		return
	_time += dt
	for b: Boom in _booms:
		if b.active:
			_step_boom(b, dt)
	for i in _lights.size():
		if _light_life[i] > 0.0:
			_light_t[i] += dt
			var k: float = _light_t[i] / _light_life[i]
			var l: OmniLight3D = _lights[i]
			if k >= 1.0:
				_light_life[i] = 0.0
				l.visible = false
			else:
				l.light_energy = _light_energy[i] * (1.0 - k) * (1.0 - k)
	for i in _beams.size():
		if _beam_life[i] > 0.0:
			_beam_t[i] += dt
			var kb: float = _beam_t[i] / _beam_life[i]
			var node: MeshInstance3D = _beams[i]
			if kb >= 1.0:
				_beam_life[i] = 0.0
				node.visible = false
			else:
				var mat: ShaderMaterial = _beam_mats[i]
				mat.set_shader_parameter("alpha", 1.0 - kb)


## Stops and hides every effect and projectile.
func clear() -> void:
	if not _built:
		return
	for b: Boom in _booms:
		_deactivate(b)
	for p: CPUParticles3D in _sparks:
		p.emitting = false
	for i in _beams.size():
		_beam_life[i] = 0.0
		var node: MeshInstance3D = _beams[i]
		node.visible = false
	for i in _lights.size():
		_light_life[i] = 0.0
		var l: OmniLight3D = _lights[i]
		l.visible = false
	_proj_used = 0
	for n: MeshInstance3D in _proj_nodes:
		n.visible = false


# ---- Internals -----------------------------------------------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_rng.randomize()
	_glow_tex = _radial_tex([0.0, 0.25, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	_ring_tex = _radial_tex([0.0, 0.7, 0.9, 0.97, 1.0],
		[Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])

	_quad = QuadMesh.new()
	_quad.size = Vector2(1.0, 1.0)

	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_spark_mat.vertex_color_use_as_albedo = true
	_spark_mat.albedo_texture = _glow_tex
	_spark_mat.albedo_color = Color(2.6, 2.6, 2.6, 1.0)
	_spark_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_particle_mesh = QuadMesh.new()
	_particle_mesh.size = Vector2(0.35, 0.35)
	_particle_mesh.material = _spark_mat

	_build_projectile_materials()

	for i in PROJ_POOL:
		var n := MeshInstance3D.new()
		n.mesh = _quad
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.visible = false
		add_child(n)
		_proj_nodes.append(n)

	for i in BOOM_POOL:
		_booms.append(_make_boom())

	for i in SPARK_POOL:
		var p := _make_particles(16, 0.35)
		add_child(p)
		_sparks.append(p)

	for i in BEAM_POOL:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://games/picket_line/shaders/beam.gdshader")
		mat.set_shader_parameter("beam_col", ENEMY_BEAM)
		mat.set_shader_parameter("intensity", 3.2)
		mat.set_shader_parameter("alpha", 0.0)
		mat.set_shader_parameter("scroll_speed", 20.0)
		var node := MeshInstance3D.new()
		node.mesh = _quad
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		add_child(node)
		_beams.append(node)
		_beam_mats.append(mat)
	_beam_t.resize(BEAM_POOL)
	_beam_life.resize(BEAM_POOL)

	for i in LIGHT_POOL:
		var l := OmniLight3D.new()
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
	_light_t.resize(LIGHT_POOL)
	_light_life.resize(LIGHT_POOL)
	_light_energy.resize(LIGHT_POOL)


func _build_projectile_materials() -> void:
	_mat_pulse = _beam_material(Color(0.75, 1.0, 0.25, 1.0), 2.2)
	_mat_lance_halo = _beam_material(Color(0.3, 0.9, 1.0, 1.0), 1.0)
	_mat_lance_core = _beam_material(Color(0.85, 1.0, 1.0, 1.0), 4.0)
	_mat_swarm = _beam_material(Color(1.0, 1.0, 1.0, 1.0), 2.0)
	_mat_flak = _orb_material(Color(1.0, 0.5, 0.15, 1.0), 3.0)
	_mat_halo = _orb_material(Color(1.0, 0.45, 0.12, 1.0), 1.0)
	_mat_shell = _orb_material(Color(1.0, 0.55, 0.15, 1.0), 3.0)
	_mat_shell_trail = _orb_material(Color(1.0, 0.4, 0.1, 1.0), 1.6)
	_mat_smoke = StandardMaterial3D.new()
	_mat_smoke.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_smoke.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat_smoke.albedo_texture = _glow_tex
	_mat_smoke.albedo_color = Color(0.65, 0.68, 0.75, 0.35)
	_mat_smoke.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_smoke.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED


func _beam_material(c: Color, intensity: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://games/picket_line/shaders/beam.gdshader")
	m.set_shader_parameter("beam_col", c)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("alpha", 1.0)
	return m


func _orb_material(c: Color, intensity: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_texture = _glow_tex
	m.albedo_color = Color(c.r * intensity, c.g * intensity, c.b * intensity, 1.0)
	return m


func _make_boom() -> Boom:
	var b := Boom.new()
	b.root = Node3D.new()
	b.root.visible = false
	add_child(b.root)

	b.sprite_mat = StandardMaterial3D.new()
	b.sprite_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.sprite_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b.sprite_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	b.sprite_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	b.sprite_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	b.sprite_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	b.sprite_mat.albedo_texture = _glow_tex
	b.sprite = MeshInstance3D.new()
	b.sprite.mesh = _quad
	b.sprite.material_override = b.sprite_mat
	b.sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.root.add_child(b.sprite)

	b.ring_mat = StandardMaterial3D.new()
	b.ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b.ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	b.ring_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	b.ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	b.ring_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	b.ring_mat.albedo_texture = _ring_tex
	b.ring = MeshInstance3D.new()
	b.ring.mesh = _quad
	b.ring.material_override = b.ring_mat
	b.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.root.add_child(b.ring)

	b.parts = _make_particles(36, 0.7)
	b.root.add_child(b.parts)
	return b


func _make_particles(amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.mesh = _particle_mesh
	p.gravity = Vector3(0.0, -3.0, 0.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _boom(pos: Vector3, size: float, color: Color, life: float, intensity: float, ring: bool, particles: bool) -> void:
	var b: Boom = _booms[_boom_next]
	_boom_next = (_boom_next + 1) % _booms.size()
	b.active = true
	b.t = 0.0
	b.life = maxf(0.05, life)
	b.size = size
	b.color = color
	b.intensity = intensity
	b.root.position = pos
	b.root.visible = true
	b.sprite.visible = true
	b.ring.visible = ring
	if particles:
		var v: float = 1.2 * pow(size, 0.6)
		var sc: float = sqrt(size)
		b.parts.direction = Vector3.UP
		b.parts.spread = 180.0
		b.parts.initial_velocity_min = v * 2.0
		b.parts.initial_velocity_max = v * 5.0
		b.parts.damping_min = 2.0
		b.parts.damping_max = 4.0
		b.parts.scale_amount_min = 0.6 * sc
		b.parts.scale_amount_max = 1.4 * sc
		b.parts.lifetime = b.life
		b.parts.color = color.lightened(0.25)
		b.parts.emitting = true
	else:
		b.parts.emitting = false
	_step_boom(b, 0.0)


func _step_boom(b: Boom, dt: float) -> void:
	b.t += dt
	var k: float = clampf(b.t / b.life, 0.0, 1.0)
	var fade: float = 1.0 - k
	b.sprite.scale = Vector3.ONE * (b.size * (0.35 + 1.1 * sqrt(k)))
	b.sprite_mat.albedo_color = Color(b.color.r * 2.2, b.color.g * 2.2, b.color.b * 2.2,
		clampf(fade * fade * b.intensity, 0.0, 1.0))
	if b.ring.visible:
		b.ring.scale = Vector3.ONE * (b.size * 2.4 * pow(k, 0.6))
		b.ring_mat.albedo_color = Color(b.color.r * 2.0, b.color.g * 2.0, b.color.b * 2.0, clampf(fade * 0.9, 0.0, 1.0))
	if k >= 1.0:
		_deactivate(b)


func _deactivate(b: Boom) -> void:
	b.active = false
	b.root.visible = false
	b.parts.emitting = false


func _muzzle_flash(weapon: int) -> void:
	var tip := _camera_point_local(MUZZLE_LOCAL)
	match weapon:
		PLBalance.Weapon.LANCE:
			flash_at(tip, Color(0.4, 0.95, 1.0, 1.0), 6.0, 12.0)
			_boom(tip, 0.6, Color(0.5, 1.0, 1.0, 1.0), 0.15, 1.2, false, false)
		PLBalance.Weapon.PULSE:
			_boom(tip, 0.25, Color(0.8, 1.0, 0.35, 1.0), 0.1, 0.8, false, false)
		PLBalance.Weapon.FLAK:
			_boom(tip, 0.35, Color(1.0, 0.55, 0.2, 1.0), 0.25, 1.0, true, false)
		PLBalance.Weapon.SWARM:
			_boom(tip, 0.4, Color(0.9, 0.9, 0.95, 1.0), 0.3, 0.5, false, true)
		_:
			pass


func _orb(pos: Vector3, diameter: float, mat: Material) -> void:
	var n := _next_proj()
	if n == null:
		return
	n.material_override = mat
	n.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * diameter), pos)
	n.visible = true


func _streak(start: Vector3, end: Vector3, width: float, mat: Material, cam_pos: Vector3) -> void:
	var seg := end - start
	if seg.length() < 0.05:
		return
	var n := _next_proj()
	if n == null:
		return
	n.material_override = mat
	n.transform = _line_xf(start, end, width, cam_pos)
	n.visible = true


func _next_proj() -> MeshInstance3D:
	if _proj_used >= _proj_nodes.size():
		return null
	var n: MeshInstance3D = _proj_nodes[_proj_used]
	_proj_used += 1
	return n


## Transform for a unit quad that runs from a to b and faces the camera at cam_pos. Caller ensures a != b.
static func _line_xf(a: Vector3, b: Vector3, width: float, cam_pos: Vector3) -> Transform3D:
	var seg := b - a
	var seg_len: float = seg.length()
	var dir: Vector3 = seg / seg_len
	var mid: Vector3 = (a + b) * 0.5
	var side: Vector3 = dir.cross(cam_pos - mid)
	if side.length_squared() < 0.000001:
		side = dir.cross(Vector3.UP)
	if side.length_squared() < 0.000001:
		side = Vector3.RIGHT
	side = side.normalized() * width
	var z_axis: Vector3 = dir.cross(side).normalized()
	return Transform3D(Basis(dir * seg_len, side, z_axis), mid)


func _radial_tex(offsets: Array, colors: Array) -> GradientTexture2D:
	var grad := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in offsets.size():
		offs.append(float(offsets[i]))
		cols.append(colors[i])
	grad.offsets = offs
	grad.colors = cols
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


func _pos(ev: Dictionary) -> Vector3:
	return ev.get("pos", Vector3.ZERO)


func _camera() -> Camera3D:
	if not is_inside_tree():
		return null
	return get_viewport().get_camera_3d()


func _camera_pos() -> Vector3:
	var cam := _camera()
	if cam == null:
		return Vector3.ZERO
	return cam.global_position


func _camera_point(forward: float) -> Vector3:
	var cam := _camera()
	if cam == null:
		return Vector3(0.0, 0.0, -forward)
	return cam.global_position + (-cam.global_transform.basis.z) * forward


func _camera_point_local(local: Vector3) -> Vector3:
	var cam := _camera()
	if cam == null:
		return local
	return cam.global_transform * local
