class_name Ui
extends RefCounted
## Immediate-mode helpers for 3D panels and buttons, plus the UI hit-test loop.
## Port of the Ui class in Game/Ui.cs (static). The button registry is `buttons`.

static var buttons: Array = []

static var PANEL: Color = Color(0.03, 0.05, 0.09, 0.92)
static var ACCENT: Color = Color(0.25, 0.95, 0.92)
static var WARN: Color = Color(1.0, 0.35, 0.45)
static var GOLD: Color = Color(1.0, 0.82, 0.25)
static var DIM: Color = Color(0.55, 0.62, 0.7)


static func make_label(text: String, font: int, color: Color, pixel: float = 0.0014) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 6
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.double_sided = true
	return l


static func label(parent: Node, text: String, pos: Vector3, font: int = 34, color: Color = Color.WHITE, pixel: float = 0.0014) -> Label3D:
	var l := make_label(text, font, color, pixel)
	l.position = pos
	parent.add_child(l)
	return l


static func label_left(parent: Node, text: String, pos: Vector3, font: int = 26, color: Color = Color.WHITE) -> Label3D:
	var l := label(parent, text, pos, font, color, 0.0013)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


static func quad(parent: Node, pos: Vector3, size: Vector2, color: Color) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, 0.02)
	var m := MeshInstance3D.new()
	m.mesh = box
	m.material_override = Meshes.solid_material(color, 0.12)
	m.position = pos
	parent.add_child(m)
	return m


static func button(parent: Node, text: String, pos: Vector3, size: Vector2, color: Color, callback: Callable, font: int = 30) -> Button3D:
	var b := Button3D.new(size, text, color, font)
	b.position = pos
	b.callback = callback
	parent.add_child(b)
	buttons.append(b)
	return b


## Forgets every button. The caller frees the node that owned them.
static func reset() -> void:
	buttons.clear()


## Forgets one button. Untyped so a freed button can be passed safely.
static func remove(b) -> void:
	buttons.erase(b)


## Faces a panel toward the target point (the player stands near the world origin).
static func face_center(node: Node3D, target: Vector3) -> void:
	var d: Vector3 = target - node.position
	node.rotation = Vector3(0.0, atan2(d.x, d.z), 0.0)


## Hit-tests every pointer, updates hover state, and fires each pointer's own press on the button it hovers.
## presses[i] belongs to pointers[i]. Returns true if any pointer is over a button.
static func update(pointers: Array, presses: Array) -> bool:
	_prune_and_clear_hover()
	var over: bool = false
	for pi in pointers.size():
		var p: Pointer = pointers[pi]
		if not p.valid:
			continue
		var best: Button3D = null
		var best_dist: float = INF
		for bi in buttons.size():
			var entry = buttons[bi]
			if not is_instance_valid(entry) or not entry.enabled or not entry.is_inside_tree():
				continue
			var d: float = entry.hit_distance(p.origin, p.dir)
			if d >= 0.0 and d < best_dist:
				best_dist = d
				best = entry
		if best == null:
			continue
		over = true
		best.set_hovered(true)
		var pressed: bool = pi < presses.size() and bool(presses[pi])
		if pressed and best.callback.is_valid():
			best.callback.call()
	return over


## Drops buttons that have been freed without Ui.remove, and clears hover on the rest.
static func _prune_and_clear_hover() -> void:
	var i: int = buttons.size() - 1
	while i >= 0:
		var entry = buttons[i]
		if is_instance_valid(entry):
			entry.set_hovered(false)
		else:
			buttons.remove_at(i)
		i -= 1
