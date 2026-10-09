class_name Dialogue
extends Node3D
## In-world story panel: typewriter text, speaker portrait, offline voice line, and branching choices.
## Port of Game/Dialogue.cs. A choice sets a profile flag, then calls on_choice so Boot saves at once.
## Buttons this panel creates are removed from Ui.buttons before they are freed.

const ANCHOR: Vector3 = Vector3(0.95, 1.45, -1.6)
const CHARS_PER_SECOND: float = 42.0

var voice: Voice = null
var profile: Profile = null
var active: bool = false

var _on_choice: Callable = Callable()
var _on_done: Callable = Callable()
var _speakers: Array = []
var _lines: Array = []
var _current: Dictionary = {}
var _index: int = -1
var _text: String = ""
var _shown: int = -1
var _typed: float = 0.0
var _typing: bool = false

var _speaker: Label3D = null
var _body: Label3D = null
var _hint: Label3D = null
var _portrait: MeshInstance3D = null
var _next_button: Button3D = null
var _option_root: Node3D = null


func _init(voice_ref: Voice, profile_ref: Profile, on_choice: Callable) -> void:
	voice = voice_ref
	profile = profile_ref
	_on_choice = on_choice
	_speakers = Story.speakers()
	position = ANCHOR

	Ui.quad(self, Vector3.ZERO, Vector2(1.3, 0.95), Ui.PANEL)
	_portrait = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	_portrait.mesh = sphere
	_portrait.position = Vector3(-0.5, 0.28, 0.03)
	add_child(_portrait)
	_speaker = Ui.label(self, "", Vector3(-0.3, 0.3, 0.03), 36, Ui.ACCENT, 0.0013)
	_body = Ui.label(self, "", Vector3(0.0, 0.02, 0.03), 28, Color.WHITE, 0.0013)
	_body.width = 800.0
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = Ui.label(self, "", Vector3(0.0, -0.38, 0.03), 22, Ui.DIM, 0.0013)
	_next_button = Ui.button(self, "NEXT", Vector3(0.45, -0.36, 0.04), Vector2(0.36, 0.12), Ui.ACCENT, Callable(self, "_advance"), 28)
	_next_button.visible = false
	_next_button.enabled = false
	visible = false


## Starts the lines (filtered by their requires_flag). done is called once when the last line is passed.
func play(lines: Array, done: Callable) -> void:
	_lines = _filter(lines)
	_on_done = done
	_index = -1
	active = true
	visible = true
	_next()


## Called once per frame. advance_pressed is the edge-detected advance intent.
func tick(dt: float, advance_pressed: bool) -> void:
	if not active:
		return
	if advance_pressed:
		_advance()
	if not _typing:
		return
	_typed += dt * CHARS_PER_SECOND
	var shown: int = mini(_text.length(), int(_typed))
	if shown != _shown:
		_shown = shown
		_body.text = _text.substr(0, shown)
	if shown >= _text.length():
		_show_controls()


func _exit_tree() -> void:
	if _next_button != null:
		Ui.remove(_next_button)
	_clear_options()


func _filter(all: Array) -> Array:
	var kept: Array = []
	for entry in all:
		var line: Dictionary = entry
		var req: String = String(line.get("requires_flag", ""))
		if req == "" or profile.has_flag(req):
			kept.append(line)
	return kept


func _next() -> void:
	_clear_options()
	_index += 1
	if _index >= _lines.size():
		active = false
		visible = false
		voice.stop()
		var done: Callable = _on_done
		_on_done = Callable()
		if done.is_valid():
			done.call()
		return

	_current = _lines[_index]
	var sp_index: int = int(_current.get("speaker", -1))
	var sp: Dictionary = _speakers[sp_index] if sp_index >= 0 else {}
	_speaker.text = String(sp.get("name", ""))
	var tint: Color = Meshes.hex_color(int(sp["color"])) if not sp.is_empty() else Color.GRAY
	_portrait.material_override = Meshes.solid_material(tint, 2.0, false)
	_text = String(_current["text"])
	_typed = 0.0
	_shown = -1
	_typing = true
	_body.text = ""
	_hint.text = ""
	_next_button.visible = false
	_next_button.enabled = false

	if profile.tts_on:
		voice.speak(_text, float(sp.get("speed", 1.0)))


## Finishes the typewriter if it is running, otherwise moves to the next line. A choice must be made first.
func _advance() -> void:
	if not active:
		return
	if _typing:
		_typed = float(_text.length())
		return
	if _current.get("options") != null:
		return
	_next()


func _show_controls() -> void:
	_typing = false
	var opts = _current.get("options")
	if opts != null:
		var options: Array = opts
		_hint.text = "CHOOSE"
		_option_root = Node3D.new()
		add_child(_option_root)
		for i in options.size():
			Ui.button(_option_root, String(options[i]), Vector3(0.0, -0.3 - i * 0.12, 0.04), Vector2(1.0, 0.1), Ui.ACCENT,
				Callable(self, "_choose").bind(i), 26)
	else:
		_hint.text = "PRESS NEXT  (A / SPACE)"
		_next_button.visible = true
		_next_button.enabled = true


func _choose(i: int) -> void:
	var flags = _current.get("option_flags")
	if flags is Array and i < flags.size():
		var flag: String = String(flags[i])
		if flag != "":
			profile.set_flag(flag)
	if _on_choice.is_valid():
		_on_choice.call()
	_next()


func _clear_options() -> void:
	if _option_root == null:
		return
	for child in _option_root.get_children():
		if child is Button3D:
			Ui.remove(child)
	_option_root.queue_free()
	_option_root = null
