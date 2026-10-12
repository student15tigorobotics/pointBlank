# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name SwarmRenderer
extends Node3D
## Draws the swarm with MultiMeshes, written through MultiMesh.buffer: one assignment per multimesh per frame.
## Port of Game/SwarmRenderer.cs with the addendum changes (buffer-based, no per-frame allocations).
## Near enemies use low-poly instanced meshes; far enemies (and anything over the mesh budget) become additive
## billboard glows. Enemies outside the view cone are skipped before any transform is written.
##
## Buffer layout, 16 floats per instance: floats 0..11 are the transform as three rows of four
## (row i = basis row i, then origin[i]); floats 12..15 are the RGBA colour.

const LOD_DISTANCE: float = 6.0       # metres from the eye: mesh inside, sprite outside. High on
                                      # purpose: battles should be real meshes; sprites are the
                                      # over-budget fallback (benchmark swarms), not the norm.
const CULL_COS: float = 0.25          # about a 75 degree half-angle view cone, generous to avoid edge pop
const STRIDE: int = 16
const SPRITE_SCALE: float = 1.3       # was 3.2: oversized additive sprites bloomed into auroras
const BAR_WIDTH: float = 0.06         # health bar full width in metres
const BAR_HEIGHT: float = 0.008
const UPLOAD_STEP: int = 64           # multimesh instance counts and buffers move in steps of this many instances

# Merged crowds (Swarm.merge_crowds makes them persistent simulation objects) render as ONE
# finer sphere scaled by the body count. CLUMP_N only normalizes that visual scale here.
const CLUMP_N: int = 30
const CLUMP_MAX: int = 64             # clump instances cap per frame
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
var _mm_bar: MultiMesh               # health bars over near (mesh LOD) enemies
var _mm_clump: MultiMesh             # one high-face icosphere per packed crowd

# Each buffer is written only by direct member index (_buf_0[o] = v). A local alias would make every write copy the array.
# A buffer always holds exactly instance_count * STRIDE floats of its multimesh (see _reserve).
var _buf_0: PackedFloat32Array = PackedFloat32Array()
var _buf_1: PackedFloat32Array = PackedFloat32Array()
var _buf_2: PackedFloat32Array = PackedFloat32Array()
var _buf_sprite: PackedFloat32Array = PackedFloat32Array()
var _buf_bar: PackedFloat32Array = PackedFloat32Array()
var _buf_clump: PackedFloat32Array = PackedFloat32Array()


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

	_mm_0 = _make_multimesh(Meshes.shape_mesh(Balance.MeshShape.TETRA))
	_mm_1 = _make_multimesh(Meshes.shape_mesh(Balance.MeshShape.OCTA))
	_mm_2 = _make_multimesh(Meshes.shape_mesh(Balance.MeshShape.ICOSA))
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_mm_sprite = _make_multimesh(quad)
	var bar_quad := QuadMesh.new()
	bar_quad.size = Vector2(1.0, 1.0)
	_mm_bar = _make_multimesh(bar_quad)
	# Clump body: ONE pre-baked crowd mesh (a mound of small enemy bodies combined into a
	# single mesh), so a merged mob still costs exactly one instance but reads as a group
	# of enemies rather than a sphere (owner 2026-10-12).
	_mm_clump = _make_multimesh(_build_crowd_mesh())

	var inst_mat: StandardMaterial3D = Meshes.instanced_material()
	_add_node(_mm_0, inst_mat)
	_add_node(_mm_1, inst_mat)
	_add_node(_mm_2, inst_mat)
	_add_node(_mm_clump, inst_mat)
	_add_node(_mm_sprite, Meshes.glow_material())
	# Health bars: camera-facing solid quads, scale kept so each bar's width is its hp fraction.
	var bar_mat := StandardMaterial3D.new()
	bar_mat.vertex_color_use_as_albedo = true
	bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bar_mat.billboard_keep_scale = true
	bar_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_node(_mm_bar, bar_mat)


## Writes this frame's visible instances. eye and forward are in battlefield-local space.
func draw(swarm: Swarm, eye: Vector3, forward: Vector3) -> void:
	var alive: PackedByteArray = swarm.alive
	var kinds: PackedInt32Array = swarm.kind
	var xs: PackedFloat32Array = swarm.x
	var ys: PackedFloat32Array = swarm.y
	var zs: PackedFloat32Array = swarm.z
	var hps: PackedFloat32Array = swarm.hp
	var max_hps: PackedFloat32Array = swarm.max_hp
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

	# Every bucket holds at most one instance per live slot, so each multimesh is sized to the swarm's high-water mark
	# (in UPLOAD_STEP steps) and the upload carries no more than that. high_water only rises within a swarm, so the
	# resize runs a few times per battle, not per frame. Sizing to the exact visible count would need a second
	# per-instance pass over the swarm, which costs more GDScript time than the upload it saves.
	_buf_0 = _reserve(_mm_0, _buf_0, high)
	_buf_1 = _reserve(_mm_1, _buf_1, high)
	_buf_2 = _reserve(_mm_2, _buf_2, high)
	_buf_sprite = _reserve(_mm_sprite, _buf_sprite, high)
	_buf_bar = _reserve(_mm_bar, _buf_bar, high)
	_buf_clump = _reserve(_mm_clump, _buf_clump, mini(high, CLUMP_MAX))

	var mesh_total: int = 0
	var sprite_count: int = 0
	var bar_n: int = 0
	var n_clumps: int = 0
	var clumps: PackedInt32Array = swarm.clump_count
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

		# A merged crowd draws as ONE baked crowd-mound mesh with a wide summed-hp bar. The
		# clump is a persistent simulation object (swarm.merge_crowds); no binning here.
		if clumps[i] > 1 and n_clumps < CLUMP_MAX:
			var ccount: int = clumps[i]
			var cs2: float = clampf(0.14 + 0.12 * pow(float(ccount) / float(CLUMP_N), 0.34), 0.16, 0.4)
			var co: int = n_clumps * STRIDE
			_buf_clump[co] = cs2
			_buf_clump[co + 3] = px
			_buf_clump[co + 5] = cs2
			_buf_clump[co + 7] = py
			_buf_clump[co + 10] = cs2
			_buf_clump[co + 11] = pz
			_buf_clump[co + 12] = _palette[0] * 1.1
			_buf_clump[co + 13] = _palette[1] * 1.1
			_buf_clump[co + 14] = _palette[2] * 1.1
			_buf_clump[co + 15] = 1.0
			n_clumps += 1
			if bar_n < cap:
				var cfrac: float = clampf(hps[i] / maxf(max_hps[i], 0.001), 0.0, 1.0)
				var cbo: int = bar_n * STRIDE
				_buf_bar[cbo] = BAR_WIDTH * 2.0 * cfrac
				_buf_bar[cbo + 3] = px
				_buf_bar[cbo + 5] = BAR_HEIGHT * 1.6
				_buf_bar[cbo + 7] = py + cs2 + 0.06
				_buf_bar[cbo + 10] = 1.0
				_buf_bar[cbo + 11] = pz
				_buf_bar[cbo + 12] = 1.0 - cfrac * 0.8
				_buf_bar[cbo + 13] = cfrac
				_buf_bar[cbo + 14] = 0.12
				_buf_bar[cbo + 15] = 1.0
				bar_n += 1
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
			# Health bar above the body: width = hp fraction, colour slides green -> red.
			var frac: float = clampf(hps[i] / maxf(max_hps[i], 0.001), 0.0, 1.0)
			var bo: int = bar_n * STRIDE
			_buf_bar[bo] = BAR_WIDTH * frac
			_buf_bar[bo + 3] = px
			_buf_bar[bo + 5] = BAR_HEIGHT
			_buf_bar[bo + 7] = py + sc + 0.035
			_buf_bar[bo + 10] = 1.0
			_buf_bar[bo + 11] = pz
			_buf_bar[bo + 12] = 1.0 - frac * 0.8
			_buf_bar[bo + 13] = frac
			_buf_bar[bo + 14] = 0.12
			_buf_bar[bo + 15] = 1.0
			bar_n += 1
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

	_mm_clump.visible_instance_count = n_clumps
	if n_clumps > 0:
		_mm_clump.buffer = _buf_clump

	visible_meshes = mesh_total + n_clumps
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
	_mm_bar.visible_instance_count = bar_n
	if bar_n > 0:
		_mm_bar.buffer = _buf_bar


func visible_total() -> int:
	return visible_meshes + visible_sprites


## Grows one multimesh to hold n instances, in UPLOAD_STEP steps, and returns its buffer. MultiMesh.buffer must be
## exactly instance_count * STRIDE floats (Godot rejects any other size), so the count and the buffer change together.
## Never shrinks: a smaller swarm simply leaves the tail unused.
func _reserve(mm: MultiMesh, buf: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var want: int = ((n + UPLOAD_STEP - 1) / UPLOAD_STEP) * UPLOAD_STEP
	if want > mm.instance_count:
		mm.instance_count = want
		buf.resize(want * STRIDE)
	return buf


## Bakes a mound of small enemy bodies into one unit-sized mesh. Deterministic layout; per-body
## brightness is baked into vertex colours and multiplies the instance's palette tint.
func _build_crowd_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# [count, ring radius, height] per layer: wide base, packed middle, a couple on top.
	var layers: Array = [[8, 0.62, 0.16], [5, 0.34, 0.45], [2, 0.12, 0.74]]
	var shapes: Array = [Balance.MeshShape.TETRA, Balance.MeshShape.OCTA]
	for layer in layers:
		var n: int = layer[0]
		for b in n:
			var ang: float = TAU * float(b) / float(n) + rng.randf() * 0.5
			var rr: float = float(layer[1]) * (0.85 + rng.randf() * 0.3)
			var centre := Vector3(cos(ang) * rr, float(layer[2]) + rng.randf() * 0.06, sin(ang) * rr)
			var body_scale: float = 0.24 + rng.randf() * 0.12
			var yaw: float = rng.randf() * TAU
			var bright: float = 0.7 + rng.randf() * 0.4
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * body_scale), centre)
			var src: ArrayMesh = Meshes.shape_mesh(shapes[(b + n) % shapes.size()])
			var arrays: Array = src.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for v in verts.size():
				st.set_color(Color(bright, bright, bright))
				st.set_normal(xf.basis * norms[v])
				st.add_vertex(xf * verts[v])
	return st.commit()


func _make_multimesh(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.visible_instance_count = 0
	mm.mesh = mesh
	return mm


func _add_node(mm: MultiMesh, mat: Material) -> void:
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	add_child(node)
