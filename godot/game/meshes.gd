class_name Meshes
extends RefCounted
## Procedural geometry and shared materials. No imported assets are needed.
## Port of Game/Meshes.cs. Static only.

static var _shapes: Dictionary = {}
static var _glow_texture: ImageTexture = null


## 0xRRGGBB int to Color (opaque).
static func hex_color(v: int) -> Color:
	return Color(
		float((v >> 16) & 0xFF) / 255.0,
		float((v >> 8) & 0xFF) / 255.0,
		float(v & 0xFF) / 255.0)


## Cached convex polyhedron for a Balance.MeshShape value.
static func shape_mesh(shape: int) -> ArrayMesh:
	if not _shapes.has(shape):
		_shapes[shape] = _build_shape(shape)
	return _shapes[shape] as ArrayMesh


static func _build_shape(shape: int) -> ArrayMesh:
	if shape == Balance.MeshShape.TETRA:
		return _polyhedron(PackedVector3Array([
			Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1),
		]))
	if shape == Balance.MeshShape.OCTA:
		return _polyhedron(PackedVector3Array([
			Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
			Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
		]))
	# Icosahedron (default, as in the C# switch).
	var phi: float = (1.0 + sqrt(5.0)) * 0.5
	var ico := PackedVector3Array()
	for a: float in [-1.0, 1.0]:
		for b: float in [-phi, phi]:
			ico.append(Vector3(0.0, a, b))
			ico.append(Vector3(a, b, 0.0))
			ico.append(Vector3(b, 0.0, a))
	var length_v: float = sqrt(1.0 + phi * phi)
	for i in ico.size():
		ico[i] = ico[i] / length_v
	return _polyhedron(ico)


## Builds a convex polyhedron from its vertices. Faces are the triangles whose three edges all have the shortest edge length.
static func _polyhedron(v: PackedVector3Array) -> ArrayMesh:
	var min_edge: float = INF
	for i in v.size():
		for j in range(i + 1, v.size()):
			min_edge = minf(min_edge, v[i].distance_to(v[j]))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in v.size():
		for j in range(i + 1, v.size()):
			for k in range(j + 1, v.size()):
				if not _is_edge(v[i].distance_to(v[j]), min_edge) \
						or not _is_edge(v[j].distance_to(v[k]), min_edge) \
						or not _is_edge(v[i].distance_to(v[k]), min_edge):
					continue
				var a: Vector3 = v[i]
				var b: Vector3 = v[j]
				var c: Vector3 = v[k]
				var n: Vector3 = (b - a).cross(c - a)
				var centroid: Vector3 = (a + b + c) / 3.0
				if n.dot(centroid) < 0.0:
					var tmp: Vector3 = b
					b = c
					c = tmp
					n = -n
				n = n.normalized()
				st.set_normal(n)
				st.add_vertex(a)
				st.set_normal(n)
				st.add_vertex(b)
				st.set_normal(n)
				st.add_vertex(c)
	return st.commit()


static func _is_edge(d: float, min_edge: float) -> bool:
	return absf(d - min_edge) < min_edge * 0.01


## Solid colour material. emission > 0 turns on emission in the same colour.
static func solid_material(color: Color, emission: float, shaded: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.45
	m.emission_enabled = emission > 0.0
	m.emission = color
	m.emission_energy_multiplier = emission
	if not shaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Material for MultiMesh instances: each instance supplies its colour through the vertex colour channel.
static func instanced_material(shaded: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.45
	m.emission_enabled = false
	if not shaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Additive soft glow sprite, always facing the camera. Tinted per instance through vertex colour.
static func glow_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _get_glow_texture()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m


static func _get_glow_texture() -> ImageTexture:
	if _glow_texture == null:
		var tex_size: int = 64
		var img := Image.create_empty(tex_size, tex_size, false, Image.FORMAT_RGBA8)
		for y in tex_size:
			for x in tex_size:
				var dx: float = (x + 0.5) / tex_size * 2.0 - 1.0
				var dy: float = (y + 0.5) / tex_size * 2.0 - 1.0
				var r: float = sqrt(dx * dx + dy * dy)
				var a: float = clampf(1.0 - r, 0.0, 1.0)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
		_glow_texture = ImageTexture.create_from_image(img)
	return _glow_texture
