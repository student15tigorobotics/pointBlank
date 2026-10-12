# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Arcade.
# PointBlank Arcade is free software under GPL-3.0-or-later. See LICENSE in the repository root.
extends Node
## Pre-game menu for the combined project. Lists the games that run on this platform and starts the one picked.
##
## A platform with one game starts it straight away. Android has only the VR game, so the headset never
## sees a flat menu (a 2D CanvasLayer is not visible inside the headset).
##
## Command-line options (after --):
##   --game=<id>   start that game without the menu (ids are in GAMES)
##   --smoke       start the VR game in its headless self-test mode
##   --shots       start the VR game in its screenshot tour

const GAMES := [
	{
		"id": "swarm",
		"name": "PointBlank Swarm",
		"scene": "res://scenes/main.tscn",
		"platforms": ["desktop", "android"],
		"blurb": "VR tower defence and swarm shooter for the VIVE XR Elite. Desktop preview on a PC.",
	},
	{
		"id": "picket_line",
		"name": "Picket Line",
		"scene": "res://games/picket_line/scenes/main.tscn",
		"platforms": ["desktop"],
		"blurb": "First-person station shooter. Hold the picket line against an alien fleet.",
	},
]

var _menu_layer: CanvasLayer = null
var _menu_buttons: Array = []
var _game: Node = null


func _ready() -> void:
	var available := _available()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--game="):
			var entry := _find(arg.substr(7))
			if not entry.is_empty() and available.has(entry):
				_start(entry)
				return
			push_error("Game not available on this platform: %s" % arg)
	if args.has("--smoke") or args.has("--shots"):
		_start(_find("swarm"))
		return
	if available.is_empty():
		push_error("No game runs on this platform.")
		get_tree().quit(1)
		return
	if available.size() == 1:
		_start(available[0])
		return
	_build_menu(available)
	_show_menu()


func _platform() -> String:
	return "android" if OS.has_feature("android") else "desktop"


func _available() -> Array:
	var out: Array = []
	var platform := _platform()
	for entry in GAMES:
		if (entry.platforms as Array).has(platform):
			out.append(entry)
	return out


func _find(id: String) -> Dictionary:
	for entry in GAMES:
		if entry.id == id:
			return entry
	return {}


func _start(entry: Dictionary) -> void:
	var packed := load(String(entry.scene)) as PackedScene
	if packed == null:
		push_error("Cannot load game scene: %s" % entry.scene)
		return
	if _menu_layer != null:
		_menu_layer.hide()
	_game = packed.instantiate()
	add_child(_game)
	if _game.has_signal("menu_requested"):
		_game.connect("menu_requested", _show_menu)


func _show_menu() -> void:
	if _game != null:
		_game.queue_free()
		_game = null
	if _menu_layer == null:
		_build_menu(_available())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu_layer.show()
	(_menu_buttons[0] as Button).grab_focus()


func _build_menu(available: Array) -> void:
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 10
	add_child(_menu_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(centre)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(620, 0)
	column.add_theme_constant_override("separation", 18)
	centre.add_child(column)

	var title := Label.new()
	title.text = "PointBlank Arcade"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	column.add_child(title)

	var sub := Label.new()
	sub.text = "Choose a game"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.7, 0.8, 0.9)
	column.add_child(sub)

	for entry in available:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 6)
		column.add_child(card)
		var button := Button.new()
		button.text = String(entry.name)
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(620, 64)
		button.add_theme_font_size_override("font_size", 26)
		button.pressed.connect(_start.bind(entry))
		card.add_child(button)
		_menu_buttons.append(button)
		var blurb := Label.new()
		blurb.text = String(entry.blurb)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
		blurb.modulate = Color(0.75, 0.8, 0.85)
		card.add_child(blurb)

	var quit := Button.new()
	quit.text = "QUIT"
	quit.custom_minimum_size = Vector2(620, 52)
	quit.pressed.connect(get_tree().quit)
	column.add_child(quit)
	_menu_buttons.append(quit)
