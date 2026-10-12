# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name EnemyView
extends Node3D
## Draws every alien in sim.enemies. One pooled MeshInstance3D per Enemy id; each kind has one ArrayMesh with a body
## surface and a glow surface (shaders/enemy.gdshader). Weak-point markers show while scoped and telegraph beams show
## while an alien winds up. Nodes and pools are reused, so nothing is allocated per frame.
## Nose faces -Z; the alien is oriented to look at the station (origin).

const MARKER_POOL := 64
const BEAM_POOL := 16
const FLASH_DECAY := 6.0
const BEAM_WIDTH := 0.5
const WARN_COLOR := Color(1.0, 0.35, 0.2, 1.0)
const OPEN_COLOR := Color(0.9, 2.0, 1.0, 0.45)
const CLOSED_COLOR := Color(2.0, 0.5, 0.45, 0.4)


class Slot extends RefCounted:
	var id := 0
	var kind := 0
	var node: MeshInstance3D = null
	var flash := 0.0
	var was_alive := true
	var stamp := 0


var _built := false
var _accent := Color(0.2, 0.9, 1.0, 1.0)
var _time := 0.0
var _stamp := 0
var _body_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _kind_meshes: Array = []
var _slots: Dictionary = {}
var _free_slots: Array = []
var _stale: Array = []
var _markers: Array = []
var _marker_used := 0
var _marker_mesh: SphereMesh
var _mat_open: StandardMaterial3D
var _mat_closed: StandardMaterial3D
var _beams: Array = []
var _beam_mats: Array = []
var _beam_used := 0
var _beam_quad: QuadMesh


func _ready() -> void:
	_ensure_built()


## Sets the theme accent used for enemy emission. Updates live aliens too.
func set_accent(color: Color) -> void:
	_accent = color
	for id in _slots:
		var s: Slot = _slots[id]
		s.node.set_instance_shader_parameter("accent", _accent)


## Adds a damage flash to one alien (decays at FLASH_DECAY per second).
func flash(enemy_id: int, amount: float) -> void:
	var s: Slot = _slots.get(enemy_id, null)
	if s != null:
		s.flash = maxf(s.flash, amount)


## Hides every alien, marker and beam and returns their nodes to the pool.
func clear() -> void:
	for id in _slots:
		var s: Slot = _slots[id]
		s.node.visible = false
		_free_slots.append(s)
	_slots.clear()
	for m: MeshInstance3D in _markers:
		m.visible = false
	for b: MeshInstance3D in _beams:
		b.visible = false
	_marker_used = 0
	_beam_used = 0


## Called every frame with the sim state. settings.quality >= 1 enables the marker pulse.
func sync(sim: Sim, dt: float, settings: Dictionary) -> void:
	_ensure_built()
	_time += dt
	_stamp += 1
	_marker_used = 0
	_beam_used = 0
	var cam_pos: Vector3 = sim.station.rail_point()
	var scoping: bool = sim.station.scoping
	var pulse_on: bool = int(settings.get("quality", 1)) >= 1
	for e: Enemy in sim.enemies:
		var s: Slot = _slots.get(e.id, null)
		if s == null:
			s = _acquire(e)
		s.stamp = _stamp
		_update_slot(s, e, dt)
		if e.alive:
			if scoping and e.weak_radius > 0.0:
				_draw_marker(e, pulse_on)
			if e.telegraph > 0.0:
				_draw_beam(e, cam_pos)
	_sweep()
	_hide_unused()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = load("res://games/picket_line/shaders/enemy.gdshader")
	_body_mat.set_shader_parameter("is_glow", false)
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = load("res://games/picket_line/shaders/enemy.gdshader")
	_glow_mat.set_shader_parameter("is_glow", true)

	_kind_meshes.resize(6)
	for k in 6:
		_kind_meshes[k] = _build_kind(k)

	_marker_mesh = SphereMesh.new()
	_marker_mesh.radius = 1.0
	_marker_mesh.height = 2.0
	_marker_mesh.radial_segments = 16
	_marker_mesh.rings = 8
	_mat_open = _marker_material(OPEN_COLOR)
	_mat_closed = _marker_material(CLOSED_COLOR)
	for i in MARKER_POOL:
		var m := MeshInstance3D.new()
		m.mesh = _marker_mesh
		m.material_override = _mat_open
		m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_markers.append(m)

	_beam_quad = QuadMesh.new()
	_beam_quad.size = Vector2(1.0, 1.0)
	for i in BEAM_POOL:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://games/picket_line/shaders/beam.gdshader")
		mat.set_shader_parameter("beam_col", WARN_COLOR)
		mat.set_shader_parameter("intensity", 2.6)
		mat.set_shader_parameter("alpha", 0.0)
		mat.set_shader_parameter("scroll_speed", 14.0)
		var b := MeshInstance3D.new()
		b.mesh = _beam_quad
		b.material_override = mat
		b.visible = false
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
		_beams.append(b)
		_beam_mats.append(mat)


func _marker_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


func _acquire(e: Enemy) -> Slot:
	var s: Slot
	if _free_slots.is_empty():
		s = Slot.new()
		s.node = MeshInstance3D.new()
		add_child(s.node)
	else:
		s = _free_slots.pop_back()
	s.id = e.id
	s.kind = e.kind
	s.flash = 0.0
	s.was_alive = e.alive
	s.node.mesh = _kind_meshes[e.kind]
	s.node.visible = true
	s.node.set_instance_shader_parameter("accent", _accent)
	_slots[e.id] = s
	return s


func _update_slot(s: Slot, e: Enemy, dt: float) -> void:
	if s.was_alive and not e.alive:
		s.flash = 1.0
	s.was_alive = e.alive
	var grow := 1.0
	if not e.alive:
		grow = clampf(e.dead_timer / PLBalance.DEATH_TIME, 0.0, 1.0)
		# Dying hulls stay white-hot and shrink away.
		s.flash = maxf(s.flash, 0.85 * grow)
	s.flash = maxf(0.0, s.flash - FLASH_DECAY * dt)
	var node: MeshInstance3D = s.node
	node.visible = grow > 0.01
	node.transform = Transform3D(_orient(e.pos).scaled(Vector3.ONE * grow), e.pos)
	node.set_instance_shader_parameter("flash", s.flash)
	node.set_instance_shader_parameter("alive", 1.0 if e.alive else grow)


## Nose (-Z) toward the station. Falls back to a safe up vector when the alien sits on the vertical axis.
func _orient(pos: Vector3) -> Basis:
	var to_station: Vector3 = -pos
	if to_station.length_squared() < 0.0001:
		return Basis.IDENTITY
	var dir: Vector3 = to_station.normalized()
	var up := Vector3.UP
	if absf(dir.y) > 0.98:
		up = Vector3.RIGHT
	return Basis.looking_at(dir, up)


func _draw_marker(e: Enemy, pulse_on: bool) -> void:
	if _marker_used >= _markers.size():
		return
	var m: MeshInstance3D = _markers[_marker_used]
	_marker_used += 1
	var r: float = e.weak_radius
	if pulse_on:
		r *= 1.0 + 0.05 * sin(_time * 7.0)
	m.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * r), e.pos + e.weak_offset)
	m.material_override = _mat_open if e.weak_open else _mat_closed
	m.visible = true


## Telegraph beam from the alien to its aim point. Pulses faster and brighter as the wind-up completes.
func _draw_beam(e: Enemy, cam_pos: Vector3) -> void:
	if _beam_used >= _beams.size():
		return
	var from: Vector3 = e.pos
	var to: Vector3 = e.telegraph_dir
	var seg: Vector3 = to - from
	var seg_len: float = seg.length()
	if seg_len < 1.0:
		return
	var dir: Vector3 = seg / seg_len
	var mid: Vector3 = (from + to) * 0.5
	var view: Vector3 = mid - cam_pos
	var side: Vector3 = dir.cross(view)
	if side.length_squared() < 0.000001:
		side = dir.cross(Vector3.UP)
	if side.length_squared() < 0.000001:
		side = Vector3.RIGHT
	side = side.normalized()

	var def: Dictionary = PLBalance.enemy_def(e.kind)
	var tmax: float = maxf(0.001, float(def.telegraph))
	var p: float = clampf(1.0 - e.telegraph / tmax, 0.0, 1.0)
	var freq: float = lerpf(3.0, 18.0, p)
	var pulse: float = 0.5 + 0.5 * sin(_time * freq * TAU)
	var alpha: float = lerpf(0.25, 1.0, p) * lerpf(0.35, 1.0, pulse)
	var width: float = lerpf(BEAM_WIDTH * 0.8, BEAM_WIDTH * 1.6, p)

	var b: MeshInstance3D = _beams[_beam_used]
	var mat: ShaderMaterial = _beam_mats[_beam_used]
	_beam_used += 1
	var x_axis: Vector3 = dir * seg_len
	var y_axis: Vector3 = side * width
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	b.transform = Transform3D(Basis(x_axis, y_axis, z_axis), mid)
	b.visible = true
	mat.set_shader_parameter("alpha", alpha)


func _hide_unused() -> void:
	for i in range(_marker_used, _markers.size()):
		var m: MeshInstance3D = _markers[i]
		m.visible = false
	for i in range(_beam_used, _beams.size()):
		var b: MeshInstance3D = _beams[i]
		b.visible = false


## Moves slots whose enemy left sim.enemies back to the pool.
func _sweep() -> void:
	_stale.clear()
	for id in _slots:
		var s: Slot = _slots[id]
		if s.stamp != _stamp:
			_stale.append(id)
	for id in _stale:
		var s2: Slot = _slots[id]
		_slots.erase(id)
		s2.node.visible = false
		_free_slots.append(s2)


# ---- Mesh construction (built once per kind) ------------------------------------------------------------------

func _build_kind(kind: int) -> ArrayMesh:
	var body := SurfaceTool.new()
	var glow := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		PLBalance.Kind.SCOUT:
			_scout(body, glow)
		PLBalance.Kind.DRONE:
			_drone(body, glow)
		PLBalance.Kind.GUNSHIP:
			_gunship(body, glow)
		PLBalance.Kind.BOMBER:
			_bomber(body, glow)
		PLBalance.Kind.CARRIER:
			_carrier(body, glow)
		_:
			_dreadnought(body, glow)
	var mesh := ArrayMesh.new()
	body.commit(mesh)
	glow.commit(mesh)
	mesh.surface_set_material(0, _body_mat)
	mesh.surface_set_material(1, _glow_mat)
	return mesh


static func _scout(body: SurfaceTool, glow: SurfaceTool) -> void:
	_part(body, _box(Vector3(0.7, 0.35, 2.4)), _xf(Vector3(0.0, 0.0, 0.2)))
	_part(body, _box(Vector3(1.9, 0.08, 0.7)), _xf(Vector3(0.0, 0.0, 0.9)))
	_part(body, _cyl(0.0, 0.45, 1.1, 8), _xf(Vector3(0.0, 0.0, -1.55), Vector3(-PI * 0.5, 0.0, 0.0)))
	_part(glow, _sphere(0.28, 8, 4), _xf(Vector3(0.0, 0.0, 1.45)))
	_part(glow, _box(Vector3(0.12, 0.06, 1.2)), _xf(Vector3(0.0, 0.2, 0.1)))


static func _drone(body: SurfaceTool, glow: SurfaceTool) -> void:
	_part(body, _sphere(0.9, 10, 6), _xf(Vector3.ZERO))
	for a in [45.0, 135.0, 225.0, 315.0]:
		var rad: float = deg_to_rad(float(a))
		var d := Vector3(cos(rad), 0.0, sin(rad))
		_part(body, _box(Vector3(1.5, 0.16, 0.16)), _xf(d * 1.35, Vector3(0.0, -rad, 0.0)))
		_part(glow, _sphere(0.22, 6, 4), _xf(d * 2.2))
	_part(glow, _sphere(0.42, 8, 4), _xf(Vector3(0.0, 0.0, -0.85)))


static func _gunship(body: SurfaceTool, glow: SurfaceTool) -> void:
	# Flat delta wedge: the prism's apex (+Y) is rotated to -Z, its thickness (Z) to Y.
	_part(body, _prism(Vector3(6.0, 4.6, 0.9)), _xf(Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0)))
	for sx in [-1.0, 1.0]:
		_part(body, _cyl(0.18, 0.18, 2.4, 8), _xf(Vector3(1.7 * sx, -0.25, -2.0), Vector3(-PI * 0.5, 0.0, 0.0)))
		_part(glow, _sphere(0.2, 6, 4), _xf(Vector3(1.7 * sx, -0.25, -3.2)))
		_part(glow, _sphere(0.32, 8, 4), _xf(Vector3(1.9 * sx, -0.1, 2.0)))


static func _bomber(body: SurfaceTool, glow: SurfaceTool) -> void:
	_part(body, _sphere(1.0, 12, 6), _xf(Vector3.ZERO, Vector3.ZERO, Vector3(1.2, 0.42, 1.7)))
	_part(glow, _sphere(0.8, 10, 4), _xf(Vector3(0.0, -0.36, 0.1), Vector3.ZERO, Vector3(1.0, 0.25, 1.25)))
	_part(glow, _sphere(0.34, 8, 4), _xf(Vector3(0.0, 0.05, 1.9)))


static func _carrier(body: SurfaceTool, glow: SurfaceTool) -> void:
	_part(body, _box(Vector3(10.0, 3.4, 16.0)), _xf(Vector3.ZERO))
	for z in [-6.0, -3.6, -1.2, 1.2, 3.6, 6.0]:
		_part(body, _box(Vector3(11.5, 0.5, 0.7)), _xf(Vector3(0.0, 1.95, float(z))))
	_part(body, _box(Vector3(5.0, 2.0, 3.0)), _xf(Vector3(0.0, 2.7, -3.0)))
	_part(glow, _box(Vector3(4.2, 1.0, 0.35)), _xf(Vector3(0.0, -0.2, -8.12)))
	for sx in [-1.0, 1.0]:
		_part(glow, _box(Vector3(2.2, 1.0, 0.35)), _xf(Vector3(3.2 * sx, 0.0, 8.12)))


static func _dreadnought(body: SurfaceTool, glow: SurfaceTool) -> void:
	_part(body, _box(Vector3(22.0, 6.0, 40.0)), _xf(Vector3.ZERO))
	_part(body, _box(Vector3(8.0, 3.0, 10.0)), _xf(Vector3(0.0, 4.5, 1.0)))
	for z in [-6.0, 6.0, 16.0]:
		var base := Vector3(0.0, 3.8, float(z))
		_part(body, _cyl(2.4, 2.4, 1.6, 10), _xf(base))
		_part(body, _cyl(0.45, 0.45, 7.0, 8), _xf(base + Vector3(0.0, 1.0, -4.0), Vector3(-PI * 0.5, 0.0, 0.0)))
	_part(glow, _sphere(3.4, 12, 6), _xf(Vector3(0.0, 0.0, -20.2), Vector3.ZERO, Vector3(1.0, 1.0, 0.4)))
	for sx in [-1.0, 1.0]:
		_part(glow, _box(Vector3(4.0, 3.0, 0.5)), _xf(Vector3(6.5 * sx, 0.0, 20.2)))


static func _part(st: SurfaceTool, prim: Mesh, xf: Transform3D) -> void:
	st.append_from(prim, 0, xf)


static func _xf(pos: Vector3, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scale), pos)


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _sphere(radius: float, segs: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segs
	m.rings = rings
	return m


static func _cyl(top_r: float, bottom_r: float, height: float, segs: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = segs
	m.rings = 1
	return m


static func _prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	m.left_to_right = 0.5
	return m
