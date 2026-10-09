class_name SwarmRenderer
extends Node3D
## Draws the swarm with MultiMeshes, written through MultiMesh.buffer: one assignment per multimesh per frame.
## Port of Game/SwarmRenderer.cs with the addendum changes (buffer-based, no per-frame allocations).
## Near enemies use low-poly instanced meshes; far enemies (and anything over the mesh budget) become additive
## billboard glows. Enemies outside the view cone are skipped before any transform is written.
##
## Buffer layout, 16 floats per instance: floats 0..11 are the transform as three rows of four
## (row i = basis row i, then origin[i]); floats 12..15 are the RGBA colour.

const LOD_DISTANCE: float = 3.0       # metres from the eye: mesh inside, sprite outside
const CULL_COS: float = 0.25          # about a 75 degree half-angle view cone, generous to avoid edge pop
const STRIDE: int = 16
const SPRITE_SCALE: float = 3.2
const SHADE_SQUASH: float = 0.5
const KIND_COUNT: int = 5

var mesh_budget: int = 1400
var visible_meshes: int = 0
var visible_sprites: int = 0

var _capacity: int = 0
var _palette: PackedFloat32Array = PackedFloat32Array()   # r, g, b per palette entry
var _palette_count: int = 1
var _kind_shape: PackedInt32Array = PackedInt32Array()
var _kind_scale: PackedFloat32Array = PackedFloat32Array()
var _kind_squash: PackedFloat32Array = PackedFloat32Array()
var _counts: PackedInt32Array = PackedInt32Array()        # instances this frame: tetra, octa, icosa, sprite

var _mm_0: MultiMesh
var _mm_1: MultiMesh
var _mm_2: MultiMesh
var _mm_sprite: MultiMesh

# Each buffer is written only by direct member index (_buf_0[o] = v). A local alias would make every write copy the array.
var _buf_0: PackedFloat32Array = PackedFloat32Array()
var _buf_1: PackedFloat32Array = PackedFloat32Array()
var _buf_2: PackedFloat32Array = PackedFloat32Array()
var _buf_sprite: PackedFloat32Array = PackedFloat32Array()


func _init(theme: Dictionary = {}, cap: int = 0) -> void:
	_capacity = cap

	var colours: Array = theme.get("enemy", [])
	_palette_count = maxi(colours.size(), 1)
	if colours.is_empty():
		_palette.append(1.0)
		_palette.append(1.0)
		_palette.append(1.0)
	for v in colours:
		var col: Color = Meshes.hex_color(int(v))
		_palette.append(col.r)
		_palette.append(col.g)
		_palette.append(col.b)

	_kind_shape.resize(KIND_COUNT)
	_kind_scale.resize(KIND_COUNT)
	_kind_squash.resize(KIND_COUNT)
	for k in KIND_COUNT:
		var stats: Dictionary = Balance.enemy(k)
		_kind_shape[k] = int(stats["shape"])
		_kind_scale[k] = float(stats["scale"])
		_kind_squash[k] = SHADE_SQUASH if k == Balance.EnemyKind.SHADE else 1.0
	_counts.resize(4)
	_counts.fill(0)

	_mm_0 = _make_multimesh(Meshes.shape_mesh(Balance.MeshShape.TETRA), cap)
	_mm_1 = _make_multimesh(Meshes.shape_mesh(Balance.MeshShape.OCTA), cap)
	_mm_2 = _make_multimesh(Meshes.shape_mesh(Balance.MeshShape.ICOSA), cap)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_mm_sprite = _make_multimesh(quad, cap)

	_buf_0 = _zeroed(cap * STRIDE)
	_buf_1 = _zeroed(cap * STRIDE)
	_buf_2 = _zeroed(cap * STRIDE)
	_buf_sprite = _zeroed(cap * STRIDE)

	var inst_mat: StandardMaterial3D = Meshes.instanced_material()
	_add_node(_mm_0, inst_mat)
	_add_node(_mm_1, inst_mat)
	_add_node(_mm_2, inst_mat)
	_add_node(_mm_sprite, Meshes.glow_material())


## Writes this frame's visible instances. eye and forward are in battlefield-local space.
func draw(swarm: Swarm, eye: Vector3, forward: Vector3) -> void:
	var alive: PackedByteArray = swarm.alive
	var kinds: PackedInt32Array = swarm.kind
	var xs: PackedFloat32Array = swarm.x
	var ys: PackedFloat32Array = swarm.y
	var zs: PackedFloat32Array = swarm.z
	var seeds: PackedFloat32Array = swarm.seed_v
	var headings: PackedFloat32Array = swarm.heading
	var high: int = swarm.high_water
	var cap: int = _capacity
	var budget: int = mesh_budget
	var ex: float = eye.x
	var ey: float = eye.y
	var ez: float = eye.z
	var fx: float = forward.x
	var fy: float = forward.y
	var fz: float = forward.z

	var mesh_total: int = 0
	var sprite_count: int = 0
	_counts.fill(0)

	for i in high:
		if alive[i] == 0:
			continue
		var px: float = xs[i]
		var py: float = ys[i]
		var pz: float = zs[i]
		var dx: float = px - ex
		var dy: float = py - ey
		var dz: float = pz - ez
		var eye_dist: float = sqrt(dx * dx + dy * dy + dz * dz)
		if eye_dist > 0.6 and (dx * fx + dy * fy + dz * fz) / eye_dist < CULL_COS:
			continue

		# Tint: palette entry chosen by seed, brightness from seed (same as Tint() in C#).
		var seed_v: float = seeds[i]
		var k: int = kinds[i]
		var pal: int = int(seed_v * float(_palette_count)) % _palette_count
		var bright: float = 0.75 + 0.5 * seed_v
		var r: float = _palette[pal * 3] * bright
		var g: float = _palette[pal * 3 + 1] * bright
		var b: float = _palette[pal * 3 + 2] * bright

		if eye_dist < LOD_DISTANCE and mesh_total < budget:
			# Basis(Vector3.Up, heading).Scaled(s, s * squash, s). Rotation about Y commutes with this scale,
			# so the columns are the rotated columns scaled: x = (c, 0, -s) * sc, y = (0, sy, 0), z = (s, 0, c) * sc.
			var shape: int = _kind_shape[k]
			var sc: float = _kind_scale[k]
			var sy: float = sc * _kind_squash[k]
			var hd: float = headings[i]
			var cs: float = cos(hd) * sc
			var sn: float = sin(hd) * sc
			var n: int = _counts[shape]
			var o: int = n * STRIDE
			# The off-diagonal zeros never change in a mesh bucket and the buffers start zeroed, so they are not rewritten.
			if shape == 0:
				_buf_0[o] = cs
				_buf_0[o + 2] = sn
				_buf_0[o + 3] = px
				_buf_0[o + 5] = sy
				_buf_0[o + 7] = py
				_buf_0[o + 8] = -sn
				_buf_0[o + 10] = cs
				_buf_0[o + 11] = pz
				_buf_0[o + 12] = r
				_buf_0[o + 13] = g
				_buf_0[o + 14] = b
				_buf_0[o + 15] = 1.0
			elif shape == 1:
				_buf_1[o] = cs
				_buf_1[o + 2] = sn
				_buf_1[o + 3] = px
				_buf_1[o + 5] = sy
				_buf_1[o + 7] = py
				_buf_1[o + 8] = -sn
				_buf_1[o + 10] = cs
				_buf_1[o + 11] = pz
				_buf_1[o + 12] = r
				_buf_1[o + 13] = g
				_buf_1[o + 14] = b
				_buf_1[o + 15] = 1.0
			else:
				_buf_2[o] = cs
				_buf_2[o + 2] = sn
				_buf_2[o + 3] = px
				_buf_2[o + 5] = sy
				_buf_2[o + 7] = py
				_buf_2[o + 8] = -sn
				_buf_2[o + 10] = cs
				_buf_2[o + 11] = pz
				_buf_2[o + 12] = r
				_buf_2[o + 13] = g
				_buf_2[o + 14] = b
				_buf_2[o + 15] = 1.0
			_counts[shape] = n + 1
			mesh_total += 1
		elif sprite_count < cap:
			# Billboard glow: uniform scale, identity rotation.
			var size_v: float = _kind_scale[k] * SPRITE_SCALE
			var so: int = sprite_count * STRIDE
			_buf_sprite[so] = size_v
			_buf_sprite[so + 3] = px
			_buf_sprite[so + 5] = size_v
			_buf_sprite[so + 7] = py
			_buf_sprite[so + 10] = size_v
			_buf_sprite[so + 11] = pz
			_buf_sprite[so + 12] = r
			_buf_sprite[so + 13] = g
			_buf_sprite[so + 14] = b
			_buf_sprite[so + 15] = 1.0
			sprite_count += 1

	visible_meshes = mesh_total
	visible_sprites = sprite_count

	# One buffer assignment per multimesh. Empty buckets are hidden and their buffer is left alone.
	_mm_0.visible_instance_count = _counts[0]
	if _counts[0] > 0:
		_mm_0.buffer = _buf_0
	_mm_1.visible_instance_count = _counts[1]
	if _counts[1] > 0:
		_mm_1.buffer = _buf_1
	_mm_2.visible_instance_count = _counts[2]
	if _counts[2] > 0:
		_mm_2.buffer = _buf_2
	_mm_sprite.visible_instance_count = sprite_count
	if sprite_count > 0:
		_mm_sprite.buffer = _buf_sprite


func visible_total() -> int:
	return visible_meshes + visible_sprites


func _make_multimesh(mesh: Mesh, cap: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = cap
	mm.visible_instance_count = 0
	mm.mesh = mesh
	return mm


func _add_node(mm: MultiMesh, mat: Material) -> void:
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	add_child(node)


func _zeroed(count: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(count)
	a.fill(0.0)
	return a
