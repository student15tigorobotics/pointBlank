class_name Button3D
extends Node3D
## A flat 3D button. Hit-tested against pointer rays with a slab test, so no physics bodies are needed.
## Port of the Button3D class in Game/Ui.cs.

const HALF_DEPTH: float = 0.05

var size: Vector2 = Vector2.ZERO
var callback: Callable = Callable()
var enabled: bool = true
var hovered: bool = false

var _mat: StandardMaterial3D
var _base_color: Color = Color.WHITE


func _init(box_size: Vector2 = Vector2.ZERO, text: String = "", color: Color = Color.WHITE, font: int = 30) -> void:
	size = box_size
	_base_color = color
	_mat = Meshes.solid_material(color.darkened(0.35), 0.35)
	var box := BoxMesh.new()
	box.size = Vector3(box_size.x, box_size.y, 0.025)
	var body := MeshInstance3D.new()
	body.mesh = box
	body.material_override = _mat
	add_child(body)
	if text != "":
		add_child(Ui.make_label(text, font, Color.WHITE, 0.0015))


func set_hovered(on: bool) -> void:
	if on == hovered:
		return
	hovered = on
	_mat.emission_energy_multiplier = 1.6 if on else 0.35
	_mat.albedo_color = _base_color if on else _base_color.darkened(0.35)


## Returns [hit: bool, distance: float]. Allocates a small Array, so per-frame code should call hit_distance().
func raycast(origin: Vector3, ray_dir: Vector3) -> Array:
	var d: float = hit_distance(origin, ray_dir)
	if d < 0.0:
		return [false, 0.0]
	return [true, d]


## Allocation-free slab test in local space. Returns the distance along the ray to the front
## (0 when the origin is inside the box), or -1.0 on a miss.
func hit_distance(origin: Vector3, ray_dir: Vector3) -> float:
	var inv: Transform3D = global_transform.affine_inverse()
	var o: Vector3 = inv * origin
	var d: Vector3 = inv.basis * ray_dir
	var span := Vector2(0.0, INF)  # x = tmin, y = tmax
	span = _slab(o.x, d.x, size.x * 0.5, span)
	if span.x > span.y:
		return -1.0
	span = _slab(o.y, d.y, size.y * 0.5, span)
	if span.x > span.y:
		return -1.0
	span = _slab(o.z, d.z, HALF_DEPTH, span)
	if span.x > span.y:
		return -1.0
	return span.x


## One axis of the slab test. A failed test returns an empty span (tmin > tmax).
static func _slab(o: float, d: float, h: float, span: Vector2) -> Vector2:
	if absf(d) < 1e-6:
		return span if absf(o) <= h else Vector2(INF, -INF)
	var t1: float = (-h - o) / d
	var t2: float = (h - o) / d
	if t1 > t2:
		var s: float = t1
		t1 = t2
		t2 = s
	return Vector2(maxf(span.x, t1), minf(span.y, t2))
