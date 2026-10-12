# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Menus
extends Control
## Menu screens built in code: title, briefing, upgrade pick, sector clear, debrief, pause, options and high scores.
## Every button emits action(id, payload). Only the visible screen takes input. Each screen sits in a scroll container,
## so long screens stay usable on a phone held in landscape.

signal action(id: String, payload: Variant)

const SCREEN_NAMES := ["title", "briefing", "upgrades", "sector_clear", "debrief", "pause", "options", "scores"]
const BTN_MIN_H := 56.0

const C_BG := Color(0.03, 0.05, 0.09, 0.92)
const C_PANEL := Color(0.07, 0.10, 0.16, 0.95)
const C_CYAN := Color(0.35, 0.85, 1.0)
const C_WARN := Color(1.0, 0.55, 0.2)
const C_GOOD := Color(0.45, 1.0, 0.55)
const C_GOLD := Color(1.0, 0.82, 0.3)
const C_HOT := Color(1.0, 0.36, 0.32)
const C_TEXT := Color(0.92, 0.96, 1.0)
const C_DIM := Color(0.92, 0.96, 1.0, 0.6)
const C_BTN := Color(0.09, 0.14, 0.22, 0.96)
const C_BTN_HOVER := Color(0.13, 0.2, 0.3, 0.98)
const C_BTN_DOWN := Color(0.05, 0.1, 0.16, 1.0)
const C_PRIMARY := Color(0.08, 0.26, 0.34, 0.97)
const C_PRIMARY_HOVER := Color(0.11, 0.34, 0.44, 0.98)
const C_DANGER := Color(0.2, 0.1, 0.06, 0.96)
const C_DANGER_HOVER := Color(0.3, 0.15, 0.08, 0.98)

enum Style { NORMAL, PRIMARY, DANGER }

var _built := false
var _backdrop: Panel = null
var _screens: Dictionary = {}
var _content: Dictionary = {}
var _panels: Dictionary = {}
var _current := ""
var _last_action := ""
var _cards: Array[Button] = []
var _cards_grid: GridContainer = null

var _sb_backdrop: StyleBoxFlat = null
var _sb_panel: StyleBoxFlat = null
var _sb_normal: StyleBoxFlat = null
var _sb_hover: StyleBoxFlat = null
var _sb_down: StyleBoxFlat = null
var _sb_focus: StyleBoxFlat = null
var _sb_disabled: StyleBoxFlat = null
var _sb_primary: StyleBoxFlat = null
var _sb_primary_hover: StyleBoxFlat = null
var _sb_danger: StyleBoxFlat = null
var _sb_danger_hover: StyleBoxFlat = null
var _sb_row_hi: StyleBoxFlat = null
var _sb_empty: StyleBoxFlat = null
var _sb_track: StyleBoxFlat = null
var _sb_fill: StyleBoxFlat = null
var _sb_fill_hi: StyleBoxFlat = null


func _ready() -> void:
	build()


## Creates all screens, hidden. Safe to call more than once.
func build() -> void:
	if _built:
		return
	_built = true
	_make_styles()
	theme = _make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = Panel.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.add_theme_stylebox_override("panel", _sb_backdrop)
	_backdrop.visible = false
	add_child(_backdrop)
	for screen_name in SCREEN_NAMES:
		var scroll := ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.visible = false
		var center := CenterContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(center)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _sb_panel)
		panel.custom_minimum_size.x = _panel_width()
		center.add_child(panel)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 14)
		panel.add_child(vb)
		add_child(scroll)
		_screens[screen_name] = scroll
		_content[screen_name] = vb
		_panels[screen_name] = panel
	resized.connect(_on_resized)


## Shows one screen, rebuilt from data. The first control gets focus, or the button that was last pressed when present.
func show_screen(screen: String, data: Dictionary = {}) -> void:
	if not _built:
		build()
	if not _content.has(screen):
		push_warning("Menus: unknown screen '%s'" % screen)
		return
	for k in _screens:
		var hidden: Control = _screens[k]
		hidden.visible = false
	var vb: VBoxContainer = _content[screen]
	_clear(vb)
	_cards.clear()
	_cards_grid = null
	match screen:
		"title":
			_fill_title(vb, data)
		"briefing":
			_fill_briefing(vb, data)
		"upgrades":
			_fill_upgrades(vb, data)
		"sector_clear":
			_fill_sector_clear(vb, data)
		"debrief":
			_fill_debrief(vb, data)
		"pause":
			_fill_pause(vb)
		"options":
			_fill_options(vb, data)
		"scores":
			_fill_scores(vb, data)
	_current = screen
	var scr: ScrollContainer = _screens[screen]
	scr.visible = true
	scr.scroll_vertical = 0
	_backdrop.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_on_resized()
	_focus_first(scr)


## Hides every screen and lets the battlefield take the mouse again.
func hide_all() -> void:
	_current = ""
	for k in _screens:
		var ctl: Control = _screens[k]
		ctl.visible = false
	_backdrop.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return _current != ""


func _unhandled_input(event: InputEvent) -> void:
	if _current == "" or not event.is_action_pressed("ui_cancel"):
		return
	if _current == "options" or _current == "scores":
		action.emit("back", null)
	elif _current == "pause":
		action.emit("resume", null)
	else:
		return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- layout

func _panel_width() -> float:
	return clampf(size.x - 32.0, 240.0, 640.0)


func _on_resized() -> void:
	var pw: float = _panel_width()
	for k in _panels:
		var pn: PanelContainer = _panels[k]
		pn.custom_minimum_size.x = pw
	var wide: bool = size.x >= 720.0
	if _cards_grid != null and is_instance_valid(_cards_grid):
		_cards_grid.columns = 3 if wide else 1
	for c in _cards:
		if is_instance_valid(c):
			c.custom_minimum_size.y = 170.0 if wide else 118.0


func _clear(vb: VBoxContainer) -> void:
	for child in vb.get_children():
		vb.remove_child(child)
		child.queue_free()


func _focus_first(scr: Node) -> void:
	var cands: Array = []
	_collect_focus(scr, cands)
	if cands.is_empty():
		return
	var target: Control = cands[0]
	if _last_action != "":
		for c in cands:
			var ctl: Control = c
			if ctl.has_meta("action") and String(ctl.get_meta("action")) == _last_action:
				target = ctl
				break
	target.grab_focus()


func _collect_focus(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Control:
			var ctl: Control = child
			if ctl.focus_mode != Control.FOCUS_NONE and ctl.is_visible_in_tree():
				out.append(ctl)
		_collect_focus(child, out)


# ---------------------------------------------------------------- screens

func _fill_title(vb: VBoxContainer, data: Dictionary) -> void:
	var diff: String = String(data.get("difficulty", "Ensign"))
	var best: int = int(data.get("best", 0))
	var has_run: bool = bool(data.get("has_run", false))
	vb.add_child(_label("PICKET LINE", 44, C_CYAN))
	vb.add_child(_label("Hold the line. Shoot them down before they reach the station.", 16, C_DIM))
	vb.add_child(_label("BEST SCORE  %d" % best, 20, C_TEXT))
	if has_run:
		vb.add_child(_label("A run is in progress. START RUN begins a new one.", 15, C_WARN))
	vb.add_child(_spacer(8.0))
	vb.add_child(_button("START RUN", "start", null, Style.PRIMARY))
	vb.add_child(_button("DIFFICULTY: %s" % diff.to_upper(), "cycle_difficulty", null))
	vb.add_child(_button("HIGH SCORES", "scores", null))
	vb.add_child(_button("OPTIONS", "options", null))
	vb.add_child(_button("ALL GAMES", "games", null))
	vb.add_child(_button("QUIT", "quit", null, Style.DANGER))


func _fill_briefing(vb: VBoxContainer, data: Dictionary) -> void:
	var idx: int = int(data.get("sector_index", 0))
	var sname: String = String(data.get("name", "Sector"))
	var waves: int = int(data.get("waves", 0))
	var boss: bool = bool(data.get("boss", false))
	var boss_name: String = String(data.get("boss_name", ""))
	var owned: Array = data.get("owned", [])
	var total: int = int(data.get("total_score", 0))
	var mission: String = String(data.get("mission", ""))
	vb.add_child(_label("SECTOR %d: %s" % [idx + 1, sname.to_upper()], 30, C_CYAN))
	vb.add_child(_label(mission, 18, C_TEXT))
	if boss:
		vb.add_child(_label("BOSS: %s waits at the end of the sector" % boss_name.to_upper(), 16, C_WARN))
	else:
		vb.add_child(_label("No boss in this sector", 16, C_DIM))
	vb.add_child(_label("%d waves" % waves, 16, C_DIM))
	vb.add_child(_label("UPGRADES: %s" % _upgrade_names(owned), 16, C_TEXT))
	vb.add_child(_label("RUN SCORE  %d" % total, 18, C_TEXT))
	vb.add_child(_spacer(8.0))
	vb.add_child(_button("LAUNCH", "begin", null, Style.PRIMARY))
	vb.add_child(_button("ABORT RUN", "abort_run", null, Style.DANGER))


func _fill_upgrades(vb: VBoxContainer, data: Dictionary) -> void:
	var offers: Array = data.get("offers", [])
	var sname: String = String(data.get("sector_name", ""))
	vb.add_child(_label("UPGRADE", 36, C_CYAN))
	vb.add_child(_label("%s cleared. Choose one upgrade for the next sector." % sname, 17, C_DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(grid)
	_cards_grid = grid
	for raw in offers:
		var o: Dictionary = raw
		var card: Button = _card(String(o.get("id", "")), String(o.get("name", "")), String(o.get("text", "")))
		grid.add_child(card)
		_cards.append(card)
	vb.add_child(_spacer(4.0))
	vb.add_child(_button("SKIP", "pick", "", Style.NORMAL))


func _fill_sector_clear(vb: VBoxContainer, data: Dictionary) -> void:
	var sname: String = String(data.get("name", ""))
	var bonus: int = int(data.get("bonus", 0))
	var clean: bool = bool(data.get("clean", false))
	var kills: int = int(data.get("kills", 0))
	var acc: float = float(data.get("accuracy", 0.0))
	var score: int = int(data.get("score", 0))
	var won: bool = bool(data.get("won", true))
	vb.add_child(_label("SECTOR CLEAR" if won else "SECTOR LOST", 36, C_GOOD if won else C_WARN))
	vb.add_child(_label(sname.to_upper(), 18, C_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat(grid, "Kills", str(kills), C_TEXT)
	_stat(grid, "Accuracy", "%d%%" % roundi(acc * 100.0), C_TEXT)
	_stat(grid, "Clean sector", "YES" if clean else "NO", C_GOOD if clean else C_DIM)
	_stat(grid, "Bonus", "+%d" % bonus, C_CYAN)
	_stat(grid, "Score", str(score), C_TEXT)
	vb.add_child(grid)
	vb.add_child(_spacer(8.0))
	vb.add_child(_button("CONTINUE", "continue", null, Style.PRIMARY))


func _fill_debrief(vb: VBoxContainer, data: Dictionary) -> void:
	var victory: bool = bool(data.get("victory", false))
	var total: int = int(data.get("total_score", 0))
	var reached: int = int(data.get("sector_reached", 0))
	var rank: int = int(data.get("rank", -1))
	var history: Array = data.get("history", [])
	var count: int = Sectors.count()
	vb.add_child(_label("VICTORY" if victory else "DOWN", 44, C_GOOD if victory else C_HOT))
	vb.add_child(_label("TOTAL SCORE  %d" % total, 26, C_TEXT))
	vb.add_child(_label("Reached sector %d of %d" % [mini(reached + 1, count), count], 16, C_DIM))
	if rank >= 0:
		vb.add_child(_label("NEW HIGH SCORE  #%d" % (rank + 1), 20, C_GOLD))
	else:
		vb.add_child(_label("Not in the top ten this time", 16, C_DIM))
	if not history.is_empty():
		vb.add_child(_spacer(6.0))
		vb.add_child(_label("SECTOR LOG", 15, C_CYAN))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 6)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(_label("SECTOR", 13, C_DIM, HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(_label("SCORE", 13, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
		grid.add_child(_label("KILLS", 13, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
		grid.add_child(_label("ACC", 13, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
		for raw in history:
			var h: Dictionary = raw
			var si: int = int(h.get("sector", 0))
			grid.add_child(_label(String(Sectors.info(si).get("name", "")), 15, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT))
			grid.add_child(_label(str(int(h.get("score", 0))), 15, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
			grid.add_child(_label(str(int(h.get("kills", 0))), 15, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
			grid.add_child(_label("%d%%" % roundi(float(h.get("accuracy", 0.0)) * 100.0), 15, C_TEXT,
				HORIZONTAL_ALIGNMENT_RIGHT))
		vb.add_child(grid)
	vb.add_child(_spacer(8.0))
	vb.add_child(_button("BACK TO TITLE", "title", null, Style.PRIMARY))


func _fill_pause(vb: VBoxContainer) -> void:
	vb.add_child(_label("PAUSED", 40, C_CYAN))
	vb.add_child(_label("Esc or B to resume", 15, C_DIM))
	vb.add_child(_spacer(6.0))
	vb.add_child(_button("RESUME", "resume", null, Style.PRIMARY))
	vb.add_child(_button("OPTIONS", "options", null))
	vb.add_child(_button("ABORT RUN", "abort_run", null, Style.DANGER))


func _fill_options(vb: VBoxContainer, data: Dictionary) -> void:
	var st: Dictionary = data.get("settings", SaveData.default_settings())
	vb.add_child(_label("OPTIONS", 36, C_CYAN))
	_slider_row(vb, "SENSITIVITY", "sensitivity", float(st.get("sensitivity", 1.0)), 0.2, 3.0, 0.05)
	_toggle_row(vb, "INVERT Y", "invert_y", bool(st.get("invert_y", false)))
	_slider_row(vb, "FIELD OF VIEW", "fov", float(st.get("fov", 75.0)), 60.0, 100.0, 1.0)
	_slider_row(vb, "MASTER VOLUME", "master", float(st.get("master", 0.8)), 0.0, 1.0, 0.05)
	_slider_row(vb, "MUSIC", "music", float(st.get("music", 0.6)), 0.0, 1.0, 0.05)
	_slider_row(vb, "EFFECTS", "sfx", float(st.get("sfx", 0.8)), 0.0, 1.0, 0.05)
	_cycle_row(vb, "QUALITY", "quality", int(st.get("quality", 1)), ["LOW", "MEDIUM", "HIGH"])
	_cycle_row(vb, "DODGE", "dodge_mode", int(st.get("dodge_mode", 0)), ["DOUBLE TAP", "SHIFT"])
	_slider_row(vb, "SCREEN SHAKE", "shake", float(st.get("shake", 1.0)), 0.0, 1.5, 0.05)
	vb.add_child(_spacer(6.0))
	vb.add_child(_button("BACK", "back", null, Style.PRIMARY))


func _fill_scores(vb: VBoxContainer, data: Dictionary) -> void:
	var scores: Array = data.get("scores", [])
	var hi: int = int(data.get("highlight_rank", -1))
	vb.add_child(_label("HIGH SCORES", 36, C_CYAN))
	if scores.is_empty():
		vb.add_child(_label("No scores yet. Go and fly.", 17, C_DIM))
	for i in mini(scores.size(), SaveData.TOP_COUNT):
		var e: Dictionary = scores[i]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _sb_row_hi if i == hi else _sb_empty)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		row.add_child(hb)
		var rank_l: Label = _label("%d" % (i + 1), 16, C_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		rank_l.size_flags_horizontal = Control.SIZE_FILL
		rank_l.custom_minimum_size = Vector2(30.0, 0.0)
		hb.add_child(rank_l)
		var nb := VBoxContainer.new()
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.add_child(_label(String(e.get("name", "???")), 18, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT))
		var sec: int = int(e.get("sector", 0))
		var res: String = "VICTORY" if bool(e.get("victory", false)) else "DOWN"
		nb.add_child(_label("%s  -  %s" % [String(Sectors.info(sec).get("name", "")), res], 13, C_DIM,
			HORIZONTAL_ALIGNMENT_LEFT))
		hb.add_child(nb)
		var score_col: Color = C_GOOD if i == hi else C_TEXT
		var score_l: Label = _label(str(int(e.get("score", 0))), 20, score_col, HORIZONTAL_ALIGNMENT_RIGHT)
		score_l.size_flags_horizontal = Control.SIZE_SHRINK_END
		hb.add_child(score_l)
		vb.add_child(row)
	vb.add_child(_spacer(6.0))
	vb.add_child(_button("BACK", "back", null, Style.PRIMARY))


# ---------------------------------------------------------------- widgets

func _label(text: String, size_px: int, col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _button(text: String, id: String, payload: Variant, style: int = Style.NORMAL) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0.0, BTN_MIN_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("action", id)
	if style == Style.PRIMARY:
		b.add_theme_stylebox_override("normal", _sb_primary)
		b.add_theme_stylebox_override("hover", _sb_primary_hover)
	elif style == Style.DANGER:
		b.add_theme_stylebox_override("normal", _sb_danger)
		b.add_theme_stylebox_override("hover", _sb_danger_hover)
	b.pressed.connect(_on_button_pressed.bind(id, payload))
	return b


func _card(id: String, card_name: String, card_text: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(160.0, 170.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("action", "pick")
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 14)
	mc.add_theme_constant_override("margin_top", 14)
	mc.add_theme_constant_override("margin_right", 14)
	mc.add_theme_constant_override("margin_bottom", 14)
	b.add_child(mc)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	mc.add_child(box)
	box.add_child(_label(card_name, 20, C_CYAN, HORIZONTAL_ALIGNMENT_LEFT))
	box.add_child(_label(card_text, 15, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	b.pressed.connect(_on_button_pressed.bind("pick", id))
	return b


func _stat(grid: GridContainer, key: String, value: String, col: Color) -> void:
	grid.add_child(_label(key, 17, C_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	grid.add_child(_label(value, 18, col, HORIZONTAL_ALIGNMENT_RIGHT))


func _row(vb: VBoxContainer, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0.0, BTN_MIN_H)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_l: Label = _label(title, 15, C_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	name_l.size_flags_horizontal = Control.SIZE_FILL
	name_l.custom_minimum_size = Vector2(118.0, 0.0)
	row.add_child(name_l)
	vb.add_child(row)
	return row


func _slider_row(vb: VBoxContainer, title: String, key: String, value: float,
		lo: float, hi: float, step: float) -> void:
	var row: HBoxContainer = _row(vb, title)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.focus_mode = Control.FOCUS_ALL
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(110.0, 44.0)
	sl.set_value_no_signal(value)
	row.add_child(sl)
	var val_l: Label = _label(_fmt_setting(key, value), 16, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	val_l.size_flags_horizontal = Control.SIZE_FILL
	val_l.custom_minimum_size = Vector2(74.0, 0.0)
	row.add_child(val_l)
	sl.value_changed.connect(_on_slider.bind(key, val_l))


func _toggle_row(vb: VBoxContainer, title: String, key: String, on: bool) -> void:
	var row: HBoxContainer = _row(vb, title)
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(150.0, BTN_MIN_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("action", "setting")
	b.button_pressed = on
	b.text = "ON" if on else "OFF"
	b.toggled.connect(_on_toggle.bind(key, b))
	row.add_child(b)


func _cycle_row(vb: VBoxContainer, title: String, key: String, value: int, labels: Array) -> void:
	var row: HBoxContainer = _row(vb, title)
	var v: int = clampi(value, 0, labels.size() - 1)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(170.0, BTN_MIN_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("action", "setting")
	b.set_meta("cycle_value", v)
	b.text = String(labels[v])
	b.pressed.connect(_on_cycle.bind(b, key, labels))
	row.add_child(b)


func _fmt_setting(key: String, v: float) -> String:
	match key:
		"sensitivity":
			return "%.2f" % v
		"fov":
			return "%d" % roundi(v)
		"master", "music", "sfx":
			return "%d%%" % roundi(v * 100.0)
		"shake":
			return "%.1f" % v
	return "%.2f" % v


func _upgrade_names(ids: Array) -> String:
	if ids.is_empty():
		return "none yet"
	var names: PackedStringArray = PackedStringArray()
	for id in ids:
		names.append(_upgrade_name(String(id)))
	return ", ".join(names)


func _upgrade_name(id: String) -> String:
	for card in Upgrades.pool():
		var d: Dictionary = card
		if String(d.get("id", "")) == id:
			return String(d.get("name", id))
	return id


# ---------------------------------------------------------------- signal handlers

func _on_button_pressed(id: String, payload: Variant) -> void:
	_last_action = id
	action.emit(id, payload)


func _on_slider(v: float, key: String, lbl: Label) -> void:
	lbl.text = _fmt_setting(key, v)
	action.emit("setting", {"key": key, "value": v})


func _on_toggle(on: bool, key: String, b: Button) -> void:
	b.text = "ON" if on else "OFF"
	action.emit("setting", {"key": key, "value": on})


func _on_cycle(b: Button, key: String, labels: Array) -> void:
	var v: int = (int(b.get_meta("cycle_value")) + 1) % labels.size()
	b.set_meta("cycle_value", v)
	b.text = String(labels[v])
	action.emit("setting", {"key": key, "value": v})


# ---------------------------------------------------------------- styles

func _box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb


func _pad(sb: StyleBoxFlat, h: float, v: float) -> void:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v


func _make_styles() -> void:
	var cyan_soft := Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.3)
	var cyan_mid := Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.65)
	_sb_backdrop = _box(C_BG, Color(0.0, 0.0, 0.0, 0.0), 0, 0)
	_sb_panel = _box(C_PANEL, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.35), 2, 16)
	_pad(_sb_panel, 24.0, 22.0)
	_sb_normal = _box(C_BTN, cyan_soft, 1, 12)
	_pad(_sb_normal, 18.0, 8.0)
	_sb_hover = _box(C_BTN_HOVER, cyan_mid, 2, 12)
	_pad(_sb_hover, 18.0, 8.0)
	_sb_down = _box(C_BTN_DOWN, C_CYAN, 2, 12)
	_pad(_sb_down, 18.0, 8.0)
	_sb_focus = _box(Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.1), C_CYAN, 3, 12)
	_sb_disabled = _box(Color(0.06, 0.08, 0.11, 0.7), Color(1.0, 1.0, 1.0, 0.12), 1, 12)
	_sb_primary = _box(C_PRIMARY, Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.9), 2, 12)
	_pad(_sb_primary, 18.0, 8.0)
	_sb_primary_hover = _box(C_PRIMARY_HOVER, C_CYAN, 2, 12)
	_pad(_sb_primary_hover, 18.0, 8.0)
	_sb_danger = _box(C_DANGER, Color(C_WARN.r, C_WARN.g, C_WARN.b, 0.75), 2, 12)
	_pad(_sb_danger, 18.0, 8.0)
	_sb_danger_hover = _box(C_DANGER_HOVER, C_WARN, 2, 12)
	_pad(_sb_danger_hover, 18.0, 8.0)
	_sb_row_hi = _box(Color(0.1, 0.22, 0.3, 0.8), C_CYAN, 2, 10)
	_pad(_sb_row_hi, 12.0, 8.0)
	_sb_empty = _box(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0, 0)
	_pad(_sb_empty, 12.0, 8.0)
	_sb_track = _box(Color(1.0, 1.0, 1.0, 0.12), Color(0.0, 0.0, 0.0, 0.0), 0, 3)
	_pad(_sb_track, 0.0, 3.0)
	_sb_fill = _box(C_CYAN, Color(0.0, 0.0, 0.0, 0.0), 0, 3)
	_pad(_sb_fill, 0.0, 3.0)
	_sb_fill_hi = _box(Color(0.6, 0.95, 1.0), Color(0.0, 0.0, 0.0, 0.0), 0, 3)
	_pad(_sb_fill_hi, 0.0, 3.0)


func _make_theme() -> Theme:
	var th := Theme.new()
	th.set_color("font_color", "Label", C_TEXT)
	th.set_font_size("font_size", "Label", 18)
	th.set_color("font_color", "Button", C_TEXT)
	th.set_color("font_hover_color", "Button", Color(1.0, 1.0, 1.0))
	th.set_color("font_pressed_color", "Button", C_CYAN)
	th.set_color("font_focus_color", "Button", Color(1.0, 1.0, 1.0))
	th.set_color("font_disabled_color", "Button", C_DIM)
	th.set_font_size("font_size", "Button", 22)
	th.set_stylebox("normal", "Button", _sb_normal)
	th.set_stylebox("hover", "Button", _sb_hover)
	th.set_stylebox("pressed", "Button", _sb_down)
	th.set_stylebox("focus", "Button", _sb_focus)
	th.set_stylebox("disabled", "Button", _sb_disabled)
	th.set_stylebox("slider", "HSlider", _sb_track)
	th.set_stylebox("grabber_area", "HSlider", _sb_fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", _sb_fill_hi)
	return th
