# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name BattleView
extends Node3D
## Holographic battle table: path, pads, towers, effect pools and HUD. Owns visuals only; logic lives in BattleController.
## Port of Game/BattleView.cs with the addendum fixes:
## - pad_under and table_point require the hit parameter t > 0 (the table must be in front of the pointer),
## - sync_towers allocates nothing per frame (node dictionary kept, scratch array reused),
## - the ring radius is rewritten only when it changes.
## local_ray, pad_under and table_point return a shared scratch Array. Read its entries before the next call.
## local_ray replaces the contract name to_local: Node3D already has a native to_local(Vector3) -> Vector3,
## and GDScript rejects an override with a different signature.

const TABLE_CENTER: Vector3 = Vector3(0.0, 0.9, -2.2)
const PAD_SIZE: float = 0.16
const TRACER_POOL: int = 160
const BURST_POOL: int = 16
const BOLT_POOL: int = 96
const BALL_POOL: int = 8
const LIGHT_POOL: int = 4
const LIGHT_LIFE: float = 0.28
const FLOAT_POOL: int = 24
const FLOAT_LIFE: float = 1.1
const PAD_PICK_RADIUS_SQ: float = 0.01        # 0.1 m
const TABLE_MARGIN: float = 0.1

var stage: Dictionary
var theme: Dictionary
var path: BattlePath
var spots: Array = []                 # Vector2 pad positions
var renderer: SwarmRenderer
var call_button: Button3D
var retreat_button: Button3D
var mode_button: Button3D
var hud_credits: Label3D
var hud_core: Label3D
var hud_wave: Label3D
var hud_tower: Label3D
var hud_weapon: Label3D
var hud_note: Label3D

var _idle: Color
var _hover: Color
var _hover_pad: int = -1
var _pad_mesh: MultiMesh
var _ring: MeshInstance3D
var _ring_mesh: CylinderMesh
var _ring_radius: float = -1.0
var _tower_root: Node3D
var _ghost: Node3D = null             # placement preview of the selected tower
var _ghost_kind: int = -1
var _tower_nodes: Dictionary = {}     # TowerInstance -> Node3D
var _tower_levels: Dictionary = {}    # TowerInstance -> int, level the node was built at
var _stale_scratch: Array = []        # reused by sync_towers
var _base_mat: StandardMaterial3D
var _pip_mat: StandardMaterial3D

var _tracers: Array = []
var _tracer_life: PackedFloat32Array = PackedFloat32Array()
var _tracer_next: int = 0
var _style_mats: Array = []           # StandardMaterial3D per ShotStyle tint

var _burst_mats: Array = []           # dimmer per-style materials for fireballs
var _bursts: Array = []
var _burst_life: PackedFloat32Array = PackedFloat32Array()
var _burst_max: PackedFloat32Array = PackedFloat32Array()
var _burst_radius: PackedFloat32Array = PackedFloat32Array()
var _burst_at: PackedVector3Array = PackedVector3Array()
var _burst_next: int = 0

var _floats: Array = []
var _float_life: PackedFloat32Array = PackedFloat32Array()
var _float_at: PackedVector3Array = PackedVector3Array()
var _float_next: int = 0

var _bolts: Array = []                # MeshInstance3D pool for travelling projectiles
var _balls: Array = []                # MeshInstance3D pool for thrown boulders
var _allies: Array = []               # Node3D pool for lemming allies
var _ally_anim: float = 0.0
var _lights: Array = []               # OmniLight3D pool for explosion flashes
var _light_life: PackedFloat32Array = PackedFloat32Array()
var _light_next: int = 0

var _local_out: Array = [Vector3.ZERO, Vector3.ZERO]
var _pad_out: Array = [-1, Vector2.ZERO]
var _table_out: Array = [false, Vector2.ZERO]


func _init(stage_def: Dictionary) -> void:
	stage = stage_def
	theme = stage_def["theme"]
	path = BattlePath.new(stage_def["path"])
	position = TABLE_CENTER

	var accent: Color = Meshes.hex_color(int(theme["accent"]))
	var grid_c: Color = Meshes.hex_color(int(theme["grid"]))
	_idle = grid_c * 0.25
	_hover = accent

	# Table slab and grid
	_add_part(_box(Vector3(3.2, 0.06, 3.2)), Meshes.solid_material(Meshes.hex_color(int(theme["table"])), 0.05), Vector3(0.0, -0.03, 0.0))
	var grid_mat: StandardMaterial3D = Meshes.solid_material(grid_c, 0.5, false)
	for i in range(-7, 8):
		var v: float = i * 0.2
		_add_part(_box(Vector3(3.0, 0.004, 0.004)), grid_mat, Vector3(0.0, 0.004, v))
		_add_part(_box(Vector3(0.004, 0.004, 3.0)), grid_mat, Vector3(v, 0.004, 0.0))

	# Lane ribbon along the path: a dim wide roadway (enemies weave across its width) with a
	# bright centre line, so the walkable corridor reads at a glance.
	var pts: PackedFloat32Array = stage_def["path"]
	var road_w: float = Swarm.LANE_HALF * 2.0 + 0.08
	var road_mat: StandardMaterial3D = Meshes.solid_material(accent * 0.35, 0.5, false)
	var path_mat: StandardMaterial3D = Meshes.solid_material(accent, 1.4, false)
	var rail_mat: StandardMaterial3D = Meshes.solid_material(accent * 0.6, 0.3)
	for i in (pts.size() >> 1) - 1:
		var x0: float = pts[i * 2]
		var z0: float = pts[i * 2 + 1]
		var x1: float = pts[i * 2 + 2]
		var z1: float = pts[i * 2 + 3]
		var seg_len: float = sqrt((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0))
		var yaw: float = atan2(x1 - x0, z1 - z0)
		# Layer heights are spread by >=5 mm: near-coplanar stacks z-fight into shimmering
		# lines at VR depth precision (owner report 2026-10-10).
		var road: MeshInstance3D = _add_part(_box(Vector3(road_w, 0.006, seg_len + road_w)), road_mat, Vector3((x0 + x1) * 0.5, 0.012, (z0 + z1) * 0.5))
		road.rotation = Vector3(0.0, yaw, 0.0)
		var seg: MeshInstance3D = _add_part(_box(Vector3(0.02, 0.009, seg_len + 0.02)), path_mat, Vector3((x0 + x1) * 0.5, 0.021, (z0 + z1) * 0.5))
		seg.rotation = Vector3(0.0, yaw, 0.0)
		# Raised guide rails along both lane edges: 3D tracks that a thrown boulder rides
		# (the physics gutter in Projectiles matches their width).
		var rail_off: float = road_w * 0.5 + 0.012
		var perp_x: float = cos(yaw)
		var perp_z: float = -sin(yaw)
		for side in [-1.0, 1.0]:
			var rail: MeshInstance3D = _add_part(_box(Vector3(0.018, 0.034, seg_len + road_w)), rail_mat,
				Vector3((x0 + x1) * 0.5 + perp_x * rail_off * side, 0.028, (z0 + z1) * 0.5 + perp_z * rail_off * side))
			rail.rotation = Vector3(0.0, yaw, 0.0)

	# Spawn portal and core. Emission is kept low and the parts are shaded: the old bright
	# unshaded emission (2.2) blew far past the glow bloom threshold, so the small core sphere
	# bloomed into a giant white ball that swallowed the whole table corner (owner 2026-10-10).
	var start_p: Vector3 = path.start()
	_add_part(_cyl(0.09, 0.09, 0.005), Meshes.solid_material(accent, 0.25), Vector3(start_p.x, 0.028, start_p.z))
	var end_p: Vector3 = path.end()
	_add_part(_sphere(0.08, 0.16), Meshes.solid_material(accent, 0.3), Vector3(end_p.x, 0.1, end_p.z))
	_add_part(_cyl(0.14, 0.14, 0.004), Meshes.solid_material(accent, 0.2), Vector3(end_p.x, 0.028, end_p.z))

	# Buildable pads (instanced)
	for ix in range(-7, 8):
		for iz in range(-7, 8):
			var px: float = ix * Balance.PAD_SPACING
			var pz: float = iz * Balance.PAD_SPACING
			if path.distance_to(px, pz) < Balance.PAD_CLEARANCE:
				continue
			if absf(px) > Balance.FIELD_HALF or absf(pz) > Balance.FIELD_HALF:
				continue
			spots.append(Vector2(px, pz))
	_pad_mesh = MultiMesh.new()
	_pad_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_pad_mesh.use_colors = true
	_pad_mesh.instance_count = spots.size()
	_pad_mesh.mesh = _box(Vector3(PAD_SIZE, 0.006, PAD_SIZE))
	for i in spots.size():
		var sp: Vector2 = spots[i]
		_pad_mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(sp.x, 0.009, sp.y)))
		_pad_mesh.set_instance_color(i, _idle)
	var pad_node := MultiMeshInstance3D.new()
	pad_node.multimesh = _pad_mesh
	pad_node.material_override = Meshes.instanced_material(false)
	add_child(pad_node)

	_ring_mesh = _cyl(0.2, 0.2, 0.003)
	_ring_radius = 0.2
	_ring = _add_part(_ring_mesh, Meshes.solid_material(accent, 0.8, false), Vector3.ZERO)
	_ring.visible = false

	_tower_root = Node3D.new()
	add_child(_tower_root)

	# Space-opera chapters get a distant starfield dome for that star-wars feel.
	if bool(theme.get("stars", false)):
		_build_stars()

	renderer = SwarmRenderer.new(theme, Balance.MAX_ENEMIES)
	add_child(renderer)

	_build_fx(accent)
	# The HUD labels/buttons live on Boot's head-following HudBar, injected via Boot._attach_hud
	# before the BattleController is created. The old world-anchored HUD window is gone.


## A dome of faint stars far beyond the table. Deterministic layout (seeded) so screenshots
## and replays always show the same sky.
func _build_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 260
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	mm.mesh = q
	for i in mm.instance_count:
		var yaw: float = rng.randf() * TAU
		var pitch: float = rng.randf_range(-0.05, 1.35)
		var r: float = rng.randf_range(7.0, 10.0)
		var pos := Vector3(cos(pitch) * sin(yaw) * r, sin(pitch) * r, cos(pitch) * cos(yaw) * r)
		var s: float = rng.randf_range(0.012, 0.035)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), pos))
		var b: float = rng.randf_range(0.4, 1.0)
		mm.set_instance_color(i, Color(b, b, minf(1.0, b * 1.1)))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	node.material_override = mat
	add_child(node)


func _build_fx(accent: Color) -> void:
	# Index 0 is the player blaster bolt: green, star-wars style (owner ask 2026-10-10).
	var tints: Array = [
		Meshes.hex_color(0x58FF5E), Meshes.hex_color(0xB84DFF), Meshes.hex_color(0x7FB8FF), Meshes.hex_color(0xFFD23F),
		Color.WHITE, Meshes.hex_color(0xFF2EE6), Color.YELLOW, Meshes.hex_color(0x9BFF6A),
	]
	for s in tints.size():
		_style_mats.append(Meshes.solid_material(tints[s], 2.5, false))
		# Bursts are translucent fireballs: an opaque sphere blocked the whole view when an
		# explosion went off in front of the player (owner report 2026-10-11).
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(tints[s].r, tints[s].g, tints[s].b, 0.32)
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_burst_mats.append(bm)

	_base_mat = Meshes.solid_material(Color(0.12, 0.14, 0.2), 0.0)
	_pip_mat = Meshes.solid_material(Color.WHITE, 2.0, false)

	_tracer_life.resize(TRACER_POOL)
	_tracer_life.fill(0.0)
	var tracer_mesh: BoxMesh = _box(Vector3(0.012, 0.012, 1.0))
	for i in TRACER_POOL:
		var node := MeshInstance3D.new()
		node.mesh = tracer_mesh
		node.visible = false
		add_child(node)
		_tracers.append(node)

	_burst_life.resize(BURST_POOL)
	_burst_max.resize(BURST_POOL)
	_burst_radius.resize(BURST_POOL)
	_burst_at.resize(BURST_POOL)
	_burst_life.fill(0.0)
	_burst_max.fill(0.0)
	_burst_radius.fill(0.0)
	var burst_mesh: SphereMesh = _sphere(0.5, 1.0)
	var burst_mat: StandardMaterial3D = Meshes.solid_material(accent, 2.0, false)
	for i in BURST_POOL:
		var node := MeshInstance3D.new()
		node.mesh = burst_mesh
		node.material_override = burst_mat
		node.visible = false
		add_child(node)
		_bursts.append(node)

	_float_life.resize(FLOAT_POOL)
	_float_at.resize(FLOAT_POOL)
	_float_life.fill(0.0)
	for i in FLOAT_POOL:
		var lbl: Label3D = Ui.make_label("", 40, Color.WHITE, 0.0016)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.visible = false
		add_child(lbl)
		_floats.append(lbl)

	# Travelling bolt pool: short emissive slugs, repositioned every frame from Projectiles.
	var bolt_mesh: BoxMesh = _box(Vector3(0.014, 0.014, 0.085))
	for i in BOLT_POOL:
		var node := MeshInstance3D.new()
		node.mesh = bolt_mesh
		node.visible = false
		add_child(node)
		_bolts.append(node)

	# Lemming ally pool: little marchers — blue body, pale face, green mop of hair.
	var body_mat: StandardMaterial3D = Meshes.solid_material(Color(0.2, 0.35, 0.95), 0.15)
	var face_mat: StandardMaterial3D = Meshes.solid_material(Color(0.95, 0.9, 0.82), 0.1)
	var hair_mat: StandardMaterial3D = Meshes.solid_material(Color(0.25, 0.95, 0.35), 0.6, false)
	for i in AllySquad.CAP:
		var lem := Node3D.new()
		lem.add_child(_make_part(_box(Vector3(0.022, 0.034, 0.016)), body_mat, Vector3(0.0, 0.017, 0.0)))
		lem.add_child(_make_part(_sphere(0.011, 0.022), face_mat, Vector3(0.0, 0.045, 0.0)))
		lem.add_child(_make_part(_box(Vector3(0.02, 0.008, 0.018)), hair_mat, Vector3(0.0, 0.058, 0.0)))
		lem.visible = false
		add_child(lem)
		_allies.append(lem)

	# Thrown boulder pool: stone spheres with their own shaded material.
	var ball_mesh: SphereMesh = _sphere(Projectiles.BALL_RADIUS, Projectiles.BALL_RADIUS * 2.0)
	var ball_mat: StandardMaterial3D = Meshes.solid_material(Color(0.42, 0.4, 0.38), 0.0)
	for i in BALL_POOL:
		var node := MeshInstance3D.new()
		node.mesh = ball_mesh
		node.material_override = ball_mat
		node.visible = false
		add_child(node)
		_balls.append(node)

	# Explosion flash pool: brief point lights so deaths actually light the table up.
	_light_life.resize(LIGHT_POOL)
	_light_life.fill(0.0)
	for i in LIGHT_POOL:
		var lamp := OmniLight3D.new()
		lamp.light_color = accent
		lamp.omni_range = 0.6
		lamp.light_energy = 0.0
		lamp.shadow_enabled = false
		lamp.visible = false
		add_child(lamp)
		_lights.append(lamp)


## Converts a world pointer to battlefield-local space. Returns [origin: Vector3, dir: Vector3] (shared scratch).
## Named local_ray, not to_local, because Node3D.to_local is native.
func local_ray(p: Pointer) -> Array:
	var inv: Transform3D = global_transform.affine_inverse()
	_local_out[0] = inv * p.origin
	_local_out[1] = (inv.basis * p.dir).normalized()
	return _local_out


## Intersects a local ray with the table top and returns [index, spot] for the nearest buildable pad,
## or [-1, Vector2.ZERO]. Misses the table or points away from it (t <= 0) give no pad. Shared scratch.
func pad_under(o: Vector3, d: Vector3) -> Array:
	_pad_out[0] = -1
	_pad_out[1] = Vector2.ZERO
	if d.y > -0.02:
		return _pad_out
	var t: float = -o.y / d.y
	if t <= 0.0:
		return _pad_out
	var hx: float = o.x + d.x * t
	var hz: float = o.z + d.z * t
	var best: int = -1
	var best_d: float = PAD_PICK_RADIUS_SQ
	for i in spots.size():
		var sp: Vector2 = spots[i]
		var dx: float = sp.x - hx
		var dz: float = sp.y - hz
		var d2: float = dx * dx + dz * dz
		if d2 < best_d:
			best_d = d2
			best = i
	if best >= 0:
		_pad_out[0] = best
		_pad_out[1] = spots[best]
	return _pad_out


## Point on the table under a local ray as [ok: bool, xz: Vector2]. [false, Vector2.ZERO] when the table is
## behind the ray (t <= 0) or the ray does not reach it. Shared scratch.
func table_point(o: Vector3, d: Vector3) -> Array:
	_table_out[0] = false
	_table_out[1] = Vector2.ZERO
	if d.y > -0.02:
		return _table_out
	var t: float = -o.y / d.y
	if t <= 0.0:
		return _table_out
	var hx: float = o.x + d.x * t
	var hz: float = o.z + d.z * t
	_table_out[0] = absf(hx) <= Balance.FIELD_HALF + TABLE_MARGIN and absf(hz) <= Balance.FIELD_HALF + TABLE_MARGIN
	if _table_out[0]:
		_table_out[1] = Vector2(hx, hz)
	return _table_out


## Translucent preview of the tower about to be placed, standing on the hovered pad. Rebuilt
## only when the selected kind changes; otherwise it just moves.
func show_tower_ghost(kind: int, at: Vector2) -> void:
	if _ghost == null or _ghost_kind != kind:
		if _ghost != null:
			_ghost.queue_free()
		_ghost = _build_ghost(kind)
		_ghost_kind = kind
		add_child(_ghost)
	_ghost.position = Vector3(at.x, 0.0, at.y)
	_ghost.visible = true


func hide_tower_ghost() -> void:
	if _ghost != null:
		_ghost.visible = false


func _build_ghost(kind: int) -> Node3D:
	var root := Node3D.new()
	var c: Color = _tower_color(kind)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(c.r, c.g, c.b, 0.4)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	root.add_child(_make_part(_cyl(0.05, 0.06, 0.05), mat, Vector3(0.0, 0.025, 0.0)))
	root.add_child(_make_part(_head_mesh(kind), mat, Vector3(0.0, 0.11, 0.0)))
	return root


## Head geometry per tower kind, shared by the real tower and its placement ghost.
static func _head_mesh(kind: int) -> Mesh:
	if kind == Balance.TowerKind.SNIPER:
		return _box(Vector3(0.035, 0.14, 0.035))
	if kind == Balance.TowerKind.MORTAR:
		return _cyl(0.06, 0.04, 0.06)
	if kind == Balance.TowerKind.TESLA or kind == Balance.TowerKind.FROST:
		return _sphere(0.045, 0.09)
	if kind == Balance.TowerKind.VORTEX:
		return _cyl(0.065, 0.015, 0.075)   # inverted funnel: the suction mouth
	return _box(Vector3(0.07, 0.07, 0.07))


func set_hover_pad(index: int) -> void:
	if index == _hover_pad:
		return
	if _hover_pad >= 0:
		_pad_mesh.set_instance_color(_hover_pad, _idle)
	_hover_pad = index
	if _hover_pad >= 0:
		_pad_mesh.set_instance_color(_hover_pad, _hover)


func show_ring(at: Vector2, radius: float) -> void:
	if radius != _ring_radius:
		_ring_mesh.top_radius = radius
		_ring_mesh.bottom_radius = radius
		_ring_radius = radius
	_ring.position = Vector3(at.x, 0.03, at.y)
	_ring.visible = true


func hide_ring() -> void:
	_ring.visible = false


## Brings the tower nodes in line with the logic towers. Nothing is allocated unless a tower was added,
## removed or upgraded.
func sync_towers(towers: Array) -> void:
	for t in towers:
		var tw: TowerInstance = t
		if _tower_nodes.has(tw):
			if int(_tower_levels[tw]) == tw.level:
				continue
			var old: Node3D = _tower_nodes[tw]
			old.queue_free()
		var node: Node3D = _build_tower(tw)
		_tower_root.add_child(node)
		_tower_nodes[tw] = node
		_tower_levels[tw] = tw.level
	if _tower_nodes.size() != towers.size():
		_drop_stale_towers(towers)


func _drop_stale_towers(towers: Array) -> void:
	_stale_scratch.clear()
	for key in _tower_nodes:
		if not towers.has(key):
			_stale_scratch.append(key)
	for key in _stale_scratch:
		var node: Node3D = _tower_nodes[key]
		node.queue_free()
		_tower_nodes.erase(key)
		_tower_levels.erase(key)
	_stale_scratch.clear()


func _build_tower(t: TowerInstance) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(t.x, 0.0, t.z)
	var c: Color = _tower_color(t.kind)
	root.add_child(_make_part(_cyl(0.05, 0.06, 0.05), _base_mat, Vector3(0.0, 0.025, 0.0)))
	root.add_child(_make_part(_head_mesh(t.kind), Meshes.solid_material(c, 1.1, false), Vector3(0.0, 0.11, 0.0)))
	for l in t.level:
		root.add_child(_make_part(_sphere(0.012, 0.024), _pip_mat, Vector3(-0.03 + l * 0.03, 0.2, 0.0)))
	return root


static func _tower_color(kind: int) -> Color:
	if kind == Balance.TowerKind.TURRET:
		return Meshes.hex_color(0x3DFFEA)
	if kind == Balance.TowerKind.TESLA:
		return Meshes.hex_color(0xB84DFF)
	if kind == Balance.TowerKind.FROST:
		return Meshes.hex_color(0x7FB8FF)
	if kind == Balance.TowerKind.MORTAR:
		return Meshes.hex_color(0xFFD23F)
	if kind == Balance.TowerKind.VORTEX:
		return Meshes.hex_color(0x2EE6D6)
	return Meshes.hex_color(0xFF4D6D)


## Shows one attack from the logic layer as a tracer, burst or both. shot is a ShotStyle.make dictionary.
func shoot(shot: Dictionary) -> void:
	var from: Vector3 = shot["from"]
	var to: Vector3 = shot["to"]
	var radius: float = shot["radius"]
	var style: int = shot["style"]
	if style == ShotStyle.Style.BURST:
		_burst(to, radius, 0.25, 4)
	elif style == ShotStyle.Style.PULSE:
		_burst(from, radius, 0.3, 2)
	elif style == ShotStyle.Style.SHELL:
		_tracer(from, to, 3)
		_burst(to, maxf(radius, 0.04), 0.3, 3)
	elif style == ShotStyle.Style.CHAIN:
		_tracer(from, to, 1)
	elif style == ShotStyle.Style.LANCE:
		_tracer(from, to, 4)
	elif style == ShotStyle.Style.BEAM:
		_tracer(from, to, 5)
	elif style == ShotStyle.Style.PELLET:
		_tracer(from, to, 6)
	else:
		_tracer(from, to, 0)


func _tracer(from: Vector3, to: Vector3, style: int) -> void:
	var i: int = _tracer_next
	_tracer_next = (i + 1) % TRACER_POOL
	var d: Vector3 = to - from
	var seg_len: float = d.length()
	if seg_len < 0.0001:
		return
	# Same orientation as Basis.LookingAt(fwd, up) scaled along z by the segment length.
	var fwd: Vector3 = d / seg_len
	var up: Vector3 = Vector3.RIGHT if absf(fwd.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var z_axis: Vector3 = -fwd
	var x_axis: Vector3 = up.cross(z_axis).normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis)
	var b := Basis(x_axis, y_axis, z_axis * seg_len)
	var node: MeshInstance3D = _tracers[i]
	node.transform = Transform3D(b, (from + to) * 0.5)
	node.material_override = _style_mats[style]
	node.visible = true
	_tracer_life[i] = 0.08


func _burst(at: Vector3, radius: float, life: float, style: int) -> void:
	var i: int = _burst_next
	_burst_next = (i + 1) % BURST_POOL
	_burst_at[i] = at
	_burst_radius[i] = maxf(radius, 0.02)
	_burst_life[i] = life
	_burst_max[i] = life
	var node: MeshInstance3D = _bursts[i]
	node.material_override = _burst_mats[style]
	node.visible = true


## Repositions the bolt pool from the projectile system. Call once per frame after its tick.
func draw_bolts(proj: Projectiles) -> void:
	var n: int = 0
	var nb: int = 0
	if proj.alive_count > 0:
		for i in Projectiles.CAP:
			if proj.alive[i] == 0:
				continue
			if proj.kind[i] == Projectiles.KIND_BALL:
				if nb < BALL_POOL:
					var ball: MeshInstance3D = _balls[nb]
					ball.position = Vector3(proj.px[i], proj.py[i], proj.pz[i])
					ball.visible = true
					nb += 1
				continue
			var node: MeshInstance3D = _bolts[n]
			var fwd := Vector3(proj.dx[i], proj.dy[i], proj.dz[i])
			var up: Vector3 = Vector3.RIGHT if absf(fwd.dot(Vector3.UP)) > 0.98 else Vector3.UP
			var z_axis: Vector3 = -fwd
			var x_axis: Vector3 = up.cross(z_axis).normalized()
			node.transform = Transform3D(Basis(x_axis, z_axis.cross(x_axis), z_axis),
				Vector3(proj.px[i], proj.py[i], proj.pz[i]))
			node.material_override = _style_mats[proj.style[i]]
			node.visible = true
			n += 1
			if n >= BOLT_POOL:
				break
	for k in range(n, BOLT_POOL):
		var spare: MeshInstance3D = _bolts[k]
		if not spare.visible:
			break
		spare.visible = false
	for k in range(nb, BALL_POOL):
		var spare_b: MeshInstance3D = _balls[k]
		if not spare_b.visible:
			break
		spare_b.visible = false


## Repositions the lemming pool from the ally squad. March bob while walking; a quick
## side-to-side shake while brawling.
func draw_allies(squad: AllySquad, dt: float) -> void:
	_ally_anim += dt
	var n: int = 0
	if squad.alive_count > 0:
		for i in AllySquad.CAP:
			if squad.alive[i] == 0:
				continue
			var lem: Node3D = _allies[n]
			var bob: float = absf(sin(_ally_anim * 9.0 + float(i))) * 0.012
			var shake: float = (sin(_ally_anim * 22.0 + float(i)) * 0.1) if squad.fighting[i] == 1 else 0.0
			lem.position = Vector3(squad.x[i], bob, squad.z[i])
			lem.rotation = Vector3(0.0, squad.heading[i] + shake, 0.0)
			lem.visible = true
			n += 1
	for k in range(n, AllySquad.CAP):
		var spare: Node3D = _allies[k]
		if not spare.visible:
			break
		spare.visible = false


## A death explosion: expanding burst, floor flash from the light pool, at a battlefield point.
## scale grows the fireball and light: a clustered mass-death renders as ONE bigger blast
## instead of dozens of individual ones (classic TD perf fix, owner ask 2026-10-11).
func explosion(at: Vector3, scale: float = 1.0) -> void:
	_burst(at, 0.055 * scale, 0.28 + 0.06 * scale, 3)
	var i: int = _light_next
	_light_next = (i + 1) % LIGHT_POOL
	_light_life[i] = LIGHT_LIFE
	var lamp: OmniLight3D = _lights[i]
	lamp.position = at + Vector3(0.0, 0.06, 0.0)
	lamp.omni_range = 0.4 + 0.3 * scale
	lamp.light_energy = 1.4 + 0.9 * scale
	lamp.visible = true


## Floating text (credits, levels, warnings) that rises and fades over FLOAT_LIFE seconds.
func float_text(text: String, at: Vector3, color: Color) -> void:
	var i: int = _float_next
	_float_next = (i + 1) % FLOAT_POOL
	_float_at[i] = at
	_float_life[i] = FLOAT_LIFE
	var lbl: Label3D = _floats[i]
	lbl.text = text
	lbl.modulate = color
	lbl.visible = true


## Advances the effect pools. Called every frame by the controller.
func tick_fx(dt: float) -> void:
	for i in TRACER_POOL:
		if _tracer_life[i] <= 0.0:
			continue
		_tracer_life[i] -= dt
		if _tracer_life[i] <= 0.0:
			var tr: MeshInstance3D = _tracers[i]
			tr.visible = false
	for i in BURST_POOL:
		if _burst_life[i] <= 0.0:
			continue
		_burst_life[i] -= dt
		var node: MeshInstance3D = _bursts[i]
		if _burst_life[i] <= 0.0:
			node.visible = false
			continue
		var progress: float = 1.0 - _burst_life[i] / _burst_max[i]
		var size_v: float = _burst_radius[i] * 2.0 * (0.3 + 0.7 * progress)
		node.position = _burst_at[i]
		node.scale = Vector3(size_v, size_v, size_v)
	for i in LIGHT_POOL:
		if _light_life[i] <= 0.0:
			continue
		_light_life[i] -= dt
		var lamp: OmniLight3D = _lights[i]
		if _light_life[i] <= 0.0:
			lamp.visible = false
			lamp.light_energy = 0.0
			continue
		lamp.light_energy *= maxf(1.0 - dt * 9.0, 0.0)
	for i in FLOAT_POOL:
		if _float_life[i] <= 0.0:
			continue
		_float_life[i] -= dt
		var lbl: Label3D = _floats[i]
		if _float_life[i] <= 0.0:
			lbl.visible = false
			continue
		var alpha: float = clampf(_float_life[i] / FLOAT_LIFE, 0.0, 1.0)
		var m: Color = lbl.modulate
		lbl.modulate = Color(m.r, m.g, m.b, alpha)
		var at: Vector3 = _float_at[i]
		at.y += dt * 0.12
		_float_at[i] = at
		lbl.position = at


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	return m


static func _sphere(radius: float, height: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	return m


## A MeshInstance3D that is not attached yet.
static func _make_part(mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	return node


## A MeshInstance3D attached to this view.
func _add_part(mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = _make_part(mesh, mat, at)
	add_child(node)
	return node
