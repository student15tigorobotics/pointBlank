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
var _tower_nodes: Dictionary = {}     # TowerInstance -> Node3D
var _tower_levels: Dictionary = {}    # TowerInstance -> int, level the node was built at
var _stale_scratch: Array = []        # reused by sync_towers
var _base_mat: StandardMaterial3D
var _pip_mat: StandardMaterial3D

var _tracers: Array = []
var _tracer_life: PackedFloat32Array = PackedFloat32Array()
var _tracer_next: int = 0
var _style_mats: Array = []           # StandardMaterial3D per ShotStyle tint

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
		_add_part(_box(Vector3(3.0, 0.004, 0.004)), grid_mat, Vector3(0.0, 0.002, v))
		_add_part(_box(Vector3(0.004, 0.004, 3.0)), grid_mat, Vector3(v, 0.002, 0.0))

	# Lane ribbon along the path
	var pts: PackedFloat32Array = stage_def["path"]
	var path_mat: StandardMaterial3D = Meshes.solid_material(accent, 1.4, false)
	for i in (pts.size() >> 1) - 1:
		var x0: float = pts[i * 2]
		var z0: float = pts[i * 2 + 1]
		var x1: float = pts[i * 2 + 2]
		var z1: float = pts[i * 2 + 3]
		var seg_len: float = sqrt((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0))
		var seg: MeshInstance3D = _add_part(_box(Vector3(0.05, 0.008, seg_len + 0.05)), path_mat, Vector3((x0 + x1) * 0.5, 0.004, (z0 + z1) * 0.5))
		seg.rotation = Vector3(0.0, atan2(x1 - x0, z1 - z0), 0.0)

	# Spawn portal and core
	var start_p: Vector3 = path.start()
	_add_part(_cyl(0.09, 0.09, 0.005), Meshes.solid_material(accent, 1.2, false), Vector3(start_p.x, 0.003, start_p.z))
	var end_p: Vector3 = path.end()
	_add_part(_sphere(0.08, 0.16), Meshes.solid_material(accent, 2.2, false), Vector3(end_p.x, 0.08, end_p.z))
	_add_part(_cyl(0.14, 0.14, 0.004), Meshes.solid_material(accent, 0.9, false), Vector3(end_p.x, 0.004, end_p.z))

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
		_pad_mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(sp.x, 0.003, sp.y)))
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

	renderer = SwarmRenderer.new(theme, Balance.MAX_ENEMIES)
	add_child(renderer)

	_build_fx(accent)
	_build_hud()


func _build_fx(accent: Color) -> void:
	var tints: Array = [
		Meshes.hex_color(0x3DFFEA), Meshes.hex_color(0xB84DFF), Meshes.hex_color(0x7FB8FF), Meshes.hex_color(0xFFD23F),
		Color.WHITE, Meshes.hex_color(0xFF2EE6), Color.YELLOW, Meshes.hex_color(0x9BFF6A),
	]
	for s in tints.size():
		_style_mats.append(Meshes.solid_material(tints[s], 2.5, false))

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


func _build_hud() -> void:
	# Left of the table, facing the player (player is at local (0,-0.9,2.2)).
	var hud := Node3D.new()
	hud.position = Vector3(-1.25, 0.6, 0.45)
	add_child(hud)
	Ui.quad(hud, Vector3.ZERO, Vector2(1.0, 1.05), Ui.PANEL)
	Ui.face_center(hud, -TABLE_CENTER)
	hud_credits = Ui.label(hud, "", Vector3(0.0, 0.42, 0.02), 40, Ui.GOLD, 0.0013)
	hud_core = Ui.label(hud, "", Vector3(0.0, 0.31, 0.02), 34, Ui.ACCENT, 0.0013)
	hud_wave = Ui.label(hud, "", Vector3(0.0, 0.2, 0.02), 30, Color.WHITE, 0.0013)
	hud_tower = Ui.label(hud, "", Vector3(0.0, 0.08, 0.02), 30, Color.WHITE, 0.0013)
	hud_weapon = Ui.label(hud, "", Vector3(0.0, -0.02, 0.02), 30, Color.WHITE, 0.0013)
	hud_note = Ui.label(hud, "", Vector3(0.0, -0.14, 0.02), 22, Ui.DIM, 0.0013)
	call_button = Ui.button(hud, "CALL WAVE", Vector3(-0.22, -0.36, 0.03), Vector2(0.4, 0.12), Ui.ACCENT, Callable(), 28)
	retreat_button = Ui.button(hud, "RETREAT", Vector3(0.22, -0.36, 0.03), Vector2(0.4, 0.12), Ui.WARN, Callable(), 28)


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
	_ring.position = Vector3(at.x, 0.004, at.y)
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
	var head: Mesh
	if t.kind == Balance.TowerKind.SNIPER:
		head = _box(Vector3(0.035, 0.14, 0.035))
	elif t.kind == Balance.TowerKind.MORTAR:
		head = _cyl(0.06, 0.04, 0.06)
	elif t.kind == Balance.TowerKind.TESLA or t.kind == Balance.TowerKind.FROST:
		head = _sphere(0.045, 0.09)
	else:
		head = _box(Vector3(0.07, 0.07, 0.07))
	root.add_child(_make_part(head, Meshes.solid_material(c, 1.1, false), Vector3(0.0, 0.11, 0.0)))
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
	node.material_override = _style_mats[style]
	node.visible = true


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
