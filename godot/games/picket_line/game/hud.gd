# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Hud
extends Control
## In-flight HUD. The engine layer calls handle_events() with each Sim.step() result and render() once per frame.
## Crosshair, scope, bars, weapon strip, score, threat arrows and edge vignettes are drawn in _draw().
## Popups and the banner are pooled Label children created by build(). Layout is computed from the Control size,
## so the same code runs from phone portrait up to desktop.

const POP_COUNT := 24
const ANCHOR_WORLD := 0
const ANCHOR_STATION := 1
const ANCHOR_COMBO := 2
const HIT_TIME := 0.15
const DRY_TIME := 0.9
const ARROW_MAX := 8
const ARROW_INSET := 44.0
const BANNER_FADE_IN := 0.15
const BANNER_FADE_OUT := 0.35
const KEYS := ["1", "2", "3", "4"]

const C_TEXT := Color(0.92, 0.96, 1.0)
const C_DIM := Color(0.92, 0.96, 1.0, 0.55)
const C_CYAN := Color(0.35, 0.85, 1.0)
const C_RED := Color(1.0, 0.3, 0.28)
const C_GOLD := Color(1.0, 0.82, 0.3)
const C_ORANGE := Color(1.0, 0.55, 0.2)
const C_GREEN := Color(0.45, 1.0, 0.55)
const C_VIOLET := Color(0.72, 0.5, 1.0)
const C_YELLOW := Color(1.0, 0.86, 0.3)
const C_HULL := Color(0.95, 0.25, 0.25)
const C_SHIELD := Color(0.35, 0.9, 1.0)
const C_BAR_BG := Color(0.03, 0.05, 0.09, 0.72)
const C_EDGE := Color(0.92, 0.96, 1.0, 0.28)
const C_SLOT_BG := Color(0.03, 0.05, 0.09, 0.62)
const C_SLOT_ON := Color(0.1, 0.22, 0.3, 0.8)
const C_SWEEP := Color(0.0, 0.0, 0.0, 0.55)
const C_SHADOW := Color(0.0, 0.0, 0.0, 0.7)
const C_OUTLINE := Color(0.0, 0.0, 0.0, 0.9)
const C_SCOPE := Color(0.0, 0.0, 0.0, 0.8)
const C_FLASH := Color(0.9, 0.06, 0.06, 0.75)
const C_ARROW := Color(1.0, 0.25, 0.22)

var _built := false
var _font: Font = null
var _cam: Camera3D = null
var _sim: Sim = null
var _last_sim: Sim = null
var _boss: Enemy = null
var _sz := Vector2.ZERO
var _laid_size := Vector2(-1.0, -1.0)
var _s := 1.0
var _m := 16.0
var _compact := false
var _r_hull := Rect2()
var _r_shield := Rect2()
var _r_energy := Rect2()
var _r_heat := Rect2()
var _r_focus := Rect2()
var _r_strip := Rect2()
var _slot_w := 0.0
var _slot_h := 0.0
var _slot_gap := 0.0
var _pulse := 0.0
var _flash := 0.0
var _kick := 0.0
var _hit_t := 0.0
var _hit_crit := false
var _scope_k := 0.0
var _score_shown := 0.0
var _dry_txt := ""
var _dry_col := C_TEXT
var _dry_t := 0.0
var _banner_life := 0.0
var _banner_span := 0.0
var _banner_pri := 0
var _banner_label: Label = null
var _pop_label: Array[Label] = []
var _pop_anchor := PackedInt32Array()
var _pop_world := PackedVector3Array()
var _pop_off := PackedVector2Array()
var _pop_life := PackedFloat32Array()
var _pop_span := PackedFloat32Array()
var _pop_rise := PackedFloat32Array()
var _pop_next := 0
var _quad := PackedVector2Array()
var _quad_cols := PackedColorArray()
var _chev := PackedVector2Array()
var _sector_idx := -1
var _sector_given := ""
var _sector_title := ""
var _sector_cap := ""
var _wave_key := -1
var _wave_txt := ""
var _hull_v := -1
var _hull_txt := ""
var _shield_v := -1
var _shield_txt := ""
var _energy_v := -1
var _energy_txt := ""
var _heat_v := -1
var _heat_txt := ""
var _focus_v := -1
var _focus_txt := ""
var _score_v := -1
var _score_txt := ""
var _combo_key := -1
var _combo_txt := ""
var _pods_key := -1
var _pods_txt := ""
var _boss_kind := -1
var _boss_title := ""
var _boss_v := -1
var _boss_txt := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	build()


## Creates the pooled popup labels and the banner label. Safe to call more than once.
func build() -> void:
	if _built:
		return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	_quad.resize(4)
	_quad_cols.resize(4)
	_chev.resize(3)
	_pop_anchor.resize(POP_COUNT)
	_pop_world.resize(POP_COUNT)
	_pop_off.resize(POP_COUNT)
	_pop_life.resize(POP_COUNT)
	_pop_span.resize(POP_COUNT)
	_pop_rise.resize(POP_COUNT)
	for i in POP_COUNT:
		var lbl: Label = Label.new()
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.visible = false
		add_child(lbl)
		_pop_label.append(lbl)
	var banner: Label = Label.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_color_override("font_outline_color", C_OUTLINE)
	banner.visible = false
	add_child(banner)
	_banner_label = banner


## Camera used to project enemies and popups to the screen.
func set_camera(cam: Camera3D) -> void:
	_cam = cam


## Draws one frame of HUD for the given sim. Call every frame during play.
func render(sim: Sim, dt: float, settings: Dictionary) -> void:
	if not visible or sim == null:
		return
	if not _built:
		build()
	if size != _laid_size:
		_layout()
	if sim != _last_sim:
		_on_new_sim(sim)
	_sim = sim
	_pulse += dt
	_flash = maxf(0.0, _flash - dt * 1.6)
	_kick = maxf(0.0, _kick - dt * 6.0)
	_hit_t = maxf(0.0, _hit_t - dt)
	_dry_t = maxf(0.0, _dry_t - dt)
	_scope_k = move_toward(_scope_k, 1.0 if sim.station.scoping else 0.0, dt * 6.0)
	var target: float = float(sim.score)
	if target < _score_shown:
		_score_shown = target
	else:
		_score_shown = lerpf(_score_shown, target, 1.0 - exp(-dt * 8.0))
		if target - _score_shown < 0.5:
			_score_shown = target
	_refresh_sector(sim, String(settings.get("sector_name", "")))
	_refresh_texts(sim)
	_boss = _find_boss(sim)
	_refresh_boss()
	_update_pops(dt)
	_update_banner(dt)
	queue_redraw()


## Feeds sim events into the HUD: hit markers, kill and combo popups, damage, banners and dry-fire text.
func handle_events(events: Array) -> void:
	for raw in events:
		var ev: Dictionary = raw
		var kind_s: String = String(ev.get("type", ""))
		match kind_s:
			"hit":
				_hit_t = HIT_TIME
				_hit_crit = bool(ev.get("crit", false))
			"shot":
				_kick = minf(1.0, _kick + 0.5)
			"kill":
				_ev_kill(ev)
			"combo":
				var mult: int = int(ev.get("mult", 1))
				if mult >= 2:
					_spawn(ANCHOR_COMBO, Vector3.ZERO, "x%d" % mult, C_ORANGE, 24.0, Vector2.ZERO, 1.0, 22.0)
			"snap":
				var sp: Vector3 = ev.get("pos", Vector3.ZERO)
				_spawn(ANCHOR_WORLD, sp, "SNAP", C_CYAN, 22.0, Vector2(58.0, -8.0), 1.0, 26.0)
			"weak_hit":
				var wp: Vector3 = ev.get("pos", Vector3.ZERO)
				_spawn(ANCHOR_WORLD, wp, "WEAK", C_GOLD, 16.0, Vector2(0.0, -30.0), 0.9, 30.0)
			"player_hit":
				_ev_player_hit(ev)
			"wave_start":
				_banner_try("WAVE %d" % int(ev.get("wave", 0)), C_CYAN, 1.6, 1)
			"boss_warning":
				_banner_try("WARNING: BOSS INCOMING", C_RED, 2.5, 5)
			"boss_spawn":
				var kind: int = int(ev.get("kind", 0))
				var bname: String = String(PLBalance.ENEMY_DEFS[kind]["name"]).to_upper()
				_banner_try(bname, Color(1.0, 0.45, 0.3), 2.5, 4)
			"boss_phase":
				_banner_try("PHASE %d" % int(ev.get("phase", 1)), C_ORANGE, 2.0, 4)
			"sector_clear":
				_banner_try("SECTOR CLEAR  +%d" % int(ev.get("bonus", 0)), C_GREEN, 3.0, 5)
			"game_over":
				_banner_try("HULL BREACHED", C_RED, 4.0, 6)
			"overheat":
				_banner_try("OVERHEAT, COOLING", C_ORANGE, 1.6, 2)
			"dry":
				_ev_dry(ev)
			_:
				pass


func hurt(amount: float) -> void:
	_flash = maxf(_flash, clampf(0.4 + amount / 35.0, 0.4, 1.0))


func banner(text: String, color: Color = Color.WHITE, seconds: float = 2.0) -> void:
	_banner_pri = 0
	_show_banner(text, color, seconds)


func set_hud_visible(on: bool) -> void:
	visible = on
	if not on:
		_banner_life = 0.0
		if _built:
			_banner_label.visible = false
			for i in POP_COUNT:
				_pop_life[i] = 0.0
				_pop_label[i].visible = false


# ---------------------------------------------------------------- events

func _ev_kill(ev: Dictionary) -> void:
	var pts: int = int(ev.get("points", 0))
	var weak: bool = bool(ev.get("weak", false))
	var p: Vector3 = ev.get("pos", Vector3.ZERO)
	var col: Color = C_GOLD if weak else C_TEXT
	_spawn(ANCHOR_WORLD, p, "+%d" % pts, col, 30.0 if weak else 22.0, Vector2.ZERO, 1.0, 46.0)


func _ev_player_hit(ev: Dictionary) -> void:
	if bool(ev.get("blocked", false)):
		_spawn(ANCHOR_STATION, Vector3.ZERO, "DODGED", C_CYAN, 18.0, Vector2(0.0, 0.0), 0.8, 26.0)
		return
	var dmg: float = float(ev.get("damage", 0.0))
	hurt(dmg)
	var hull_part: float = float(ev.get("applied_hull", 0.0))
	var col: Color = C_RED if hull_part > 0.0 else C_SHIELD
	_spawn(ANCHOR_STATION, Vector3.ZERO, "-%d" % roundi(dmg), col, 26.0, Vector2(0.0, 0.0), 0.9, 40.0)


func _ev_dry(ev: Dictionary) -> void:
	var reason: String = String(ev.get("reason", ""))
	match reason:
		"heat":
			_dry_txt = "OVERHEAT"
			_dry_col = C_ORANGE
		"energy":
			_dry_txt = "NO ENERGY"
			_dry_col = C_YELLOW
		"pods":
			_dry_txt = "NO PODS"
			_dry_col = C_CYAN
		_:
			return
	_dry_t = DRY_TIME


# ---------------------------------------------------------------- banner and popups

func _banner_try(text: String, col: Color, secs: float, pri: int) -> void:
	if _banner_life > 0.0 and _banner_pri > pri:
		return
	_show_banner(text, col, secs)
	_banner_pri = pri


func _show_banner(text: String, col: Color, secs: float) -> void:
	if not _built:
		return
	_banner_label.text = text
	_banner_label.add_theme_color_override("font_color", col)
	_banner_life = secs
	_banner_span = maxf(secs, 0.01)


func _spawn(anchor: int, world: Vector3, txt: String, col: Color, fs: float, off: Vector2,
		span: float, rise: float) -> void:
	if not _built:
		return
	var idx := -1
	for i in POP_COUNT:
		if _pop_life[i] <= 0.0:
			idx = i
			break
	if idx < 0:
		idx = _pop_next
		_pop_next = (_pop_next + 1) % POP_COUNT
	_pop_anchor[idx] = anchor
	_pop_world[idx] = world
	_pop_off[idx] = off
	_pop_life[idx] = span
	_pop_span[idx] = span
	_pop_rise[idx] = rise
	var lbl: Label = _pop_label[idx]
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", roundi(fs * _s))
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", C_OUTLINE)
	lbl.add_theme_constant_override("outline_size", roundi(4.0 * _s))
	lbl.reset_size()
	lbl.modulate = Color(1.0, 1.0, 1.0, 1.0)
	lbl.visible = true


func _update_pops(dt: float) -> void:
	var station_pt := Vector2(_sz.x * 0.5, _sz.y * 0.5 + 64.0 * _s)
	var combo_pt := Vector2(_sz.x - _m - 170.0 * _s, _m + 60.0 * _s)
	for i in POP_COUNT:
		var lbl: Label = _pop_label[i]
		if _pop_life[i] <= 0.0:
			if lbl.visible:
				lbl.visible = false
			continue
		_pop_life[i] = _pop_life[i] - dt
		if _pop_life[i] <= 0.0:
			lbl.visible = false
			continue
		var t: float = 1.0 - _pop_life[i] / _pop_span[i]
		var anchor := Vector2.ZERO
		match _pop_anchor[i]:
			ANCHOR_WORLD:
				var wp: Vector3 = _pop_world[i]
				if _cam == null or not is_instance_valid(_cam) or _cam.is_position_behind(wp):
					lbl.visible = false
					continue
				anchor = _cam.unproject_position(wp)
			ANCHOR_STATION:
				anchor = station_pt
			_:
				anchor = combo_pt
		lbl.visible = true
		lbl.position = anchor + _pop_off[i] * _s + Vector2(0.0, -_pop_rise[i] * _s * t) - lbl.size * 0.5
		var a: float = 1.0
		if t > 0.6:
			a = clampf(1.0 - (t - 0.6) / 0.4, 0.0, 1.0)
		lbl.modulate = Color(1.0, 1.0, 1.0, a)


func _update_banner(dt: float) -> void:
	if _banner_life <= 0.0:
		if _banner_label.visible:
			_banner_label.visible = false
		return
	_banner_life -= dt
	if _banner_life <= 0.0:
		_banner_label.visible = false
		return
	var age: float = _banner_span - _banner_life
	var a: float = clampf(age / BANNER_FADE_IN, 0.0, 1.0)
	a = minf(a, clampf(_banner_life / BANNER_FADE_OUT, 0.0, 1.0))
	var lh: float = 40.0 * _s * 1.5
	_banner_label.position = Vector2(0.0, _sz.y * 0.26 - lh * 0.5)
	_banner_label.size = Vector2(_sz.x, lh)
	_banner_label.modulate = Color(1.0, 1.0, 1.0, a)
	_banner_label.visible = true


# ---------------------------------------------------------------- layout and cached text

func _layout() -> void:
	_laid_size = size
	_sz = size
	var w: float = size.x
	var h: float = size.y
	_s = clampf(minf(w, h) / 760.0, 0.8, 1.5)
	var s: float = _s
	_m = roundf(16.0 * s)
	var m: float = _m
	_compact = h > w or w < 700.0
	if _compact:
		_slot_gap = 6.0 * s
		_slot_h = 46.0 * s
		_slot_w = (w - 2.0 * m - 3.0 * _slot_gap) / 4.0
		_r_strip = Rect2(m, h - m - _slot_h, w - 2.0 * m, _slot_h)
		var bar_h: float = 9.0 * s
		var step: float = 28.0 * s
		var y0: float = _r_strip.position.y - 18.0 * s - bar_h
		var bw: float = w - 2.0 * m
		_r_focus = Rect2(m, y0, bw, bar_h)
		_r_heat = Rect2(m, y0 - step, bw, bar_h)
		_r_energy = Rect2(m, y0 - 2.0 * step, bw, bar_h)
		_r_shield = Rect2(m, y0 - 3.0 * step, bw, bar_h)
		_r_hull = Rect2(m, y0 - 4.0 * step, bw, bar_h)
	else:
		_slot_gap = 8.0 * s
		_slot_h = 56.0 * s
		_slot_w = minf(w * 0.095, 110.0 * s)
		var strip_w: float = 4.0 * _slot_w + 3.0 * _slot_gap
		_r_strip = Rect2(w - m - strip_w, h - m - _slot_h, strip_w, _slot_h)
		var bar_h2: float = 12.0 * s
		var step2: float = 34.0 * s
		var bw_l: float = minf(w * 0.2, 300.0 * s)
		var base_y: float = h - m - bar_h2
		_r_shield = Rect2(m, base_y, bw_l, bar_h2)
		_r_hull = Rect2(m, base_y - step2, bw_l, bar_h2)
		var cw: float = minf(w * 0.16, 300.0 * s)
		var cx: float = (w - cw) * 0.5
		_r_focus = Rect2(cx, base_y, cw, bar_h2)
		_r_heat = Rect2(cx, base_y - step2, cw, bar_h2)
		_r_energy = Rect2(cx, base_y - 2.0 * step2, cw, bar_h2)
	if _built:
		_banner_label.add_theme_font_size_override("font_size", roundi(40.0 * s))
		_banner_label.add_theme_constant_override("outline_size", roundi(6.0 * s))


func _on_new_sim(sim: Sim) -> void:
	_last_sim = sim
	_score_shown = float(sim.score)
	_flash = 0.0
	_hit_t = 0.0
	_dry_t = 0.0
	_scope_k = 0.0
	if _built:
		for i in POP_COUNT:
			_pop_life[i] = 0.0


func _refresh_sector(sim: Sim, given: String) -> void:
	if sim.sector == _sector_idx and given == _sector_given:
		return
	_sector_idx = sim.sector
	_sector_given = given
	_sector_cap = "SECTOR %d" % (sim.sector + 1)
	if given != "":
		_sector_title = given
	else:
		_sector_title = String(Sectors.info(sim.sector).get("name", "Sector"))


func _refresh_texts(sim: Sim) -> void:
	var st: Station = sim.station
	var v: int = roundi(st.hull)
	if v != _hull_v:
		_hull_v = v
		_hull_txt = str(v)
	v = roundi(st.shield)
	if v != _shield_v:
		_shield_v = v
		_shield_txt = str(v)
	v = roundi(st.energy)
	if v != _energy_v:
		_energy_v = v
		_energy_txt = str(v)
	v = roundi(st.heat / PLBalance.HEAT_MAX * 100.0)
	if v != _heat_v:
		_heat_v = v
		_heat_txt = "%d%%" % v
	v = roundi(st.focus / maxf(st.focus_max, 1.0) * 100.0)
	if v != _focus_v:
		_focus_v = v
		_focus_txt = "%d%%" % v
	v = int(_score_shown)
	if v != _score_v:
		_score_v = v
		_score_txt = str(v)
	var ck: int = sim.combo * 100 + sim.combo_mult
	if ck != _combo_key:
		_combo_key = ck
		_combo_txt = "CHAIN %d   x%d" % [sim.combo, sim.combo_mult]
	var now: int = 0
	for raw in sim.schedule:
		var it: Dictionary = raw
		if bool(it.get("boss", false)):
			continue
		if float(it.get("t", 0.0)) <= sim.time:
			now = maxi(now, int(it.get("group", 0)))
	var total: int = int(Sectors.info(sim.sector).get("waves", 0))
	var alive: int = sim.alive_count()
	var wkey: int = ((now * 1000) + alive) * 100 + total
	if wkey != _wave_key:
		_wave_key = wkey
		_wave_txt = "WAVE %d/%d   ALIVE %d" % [now, total, alive]
	var wpn: Weapons = sim.weapons
	var pkey: int = int(floor(wpn.pods)) * 100 + wpn.max_pods()
	if pkey != _pods_key:
		_pods_key = pkey
		_pods_txt = "%d/%d" % [int(floor(wpn.pods)), wpn.max_pods()]


func _refresh_boss() -> void:
	if _boss == null:
		return
	if _boss.kind != _boss_kind:
		_boss_kind = _boss.kind
		_boss_title = String(PLBalance.ENEMY_DEFS[_boss.kind]["name"]).to_upper()
	var pct: int = roundi(_boss.hp / maxf(_boss.max_hp, 1.0) * 100.0)
	if pct != _boss_v:
		_boss_v = pct
		_boss_txt = "%d%%" % pct


func _find_boss(sim: Sim) -> Enemy:
	for e: Enemy in sim.enemies:
		if e.alive and e.boss:
			return e
	return null


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if _sim == null or _font == null or _sz.x <= 0.0 or _sz.y <= 0.0:
		return
	var c: Vector2 = _sz * 0.5
	var st: Station = _sim.station
	var wpn: Weapons = _sim.weapons
	var has_cam: bool = _cam != null and is_instance_valid(_cam)
	if _scope_k > 0.001:
		_vignette(0.2, 0.18, C_SCOPE, _scope_k)
	if _flash > 0.001:
		_vignette(0.12, 0.12, C_FLASH, _flash)
	if st.scoping:
		_draw_scope(c, has_cam)
	else:
		_draw_crosshair(c, st, wpn)
	_draw_hit(c)
	if has_cam:
		_draw_threats()
	_draw_status(st)
	_draw_weapons(st, wpn)
	_draw_top(_sim)
	_draw_boss()
	_draw_dry()


## Draws text with a one pixel shadow. Font size is scaled with the layout factor.
func _text(pos: Vector2, txt: String, fs: float, col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var px: int = roundi(fs * _s)
	var off: float = maxf(1.0, _s)
	draw_string(_font, pos + Vector2(off, off), txt, align, width, px, Color(0.0, 0.0, 0.0, C_SHADOW.a * col.a))
	draw_string(_font, pos, txt, align, width, px, col)


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, C_BAR_BG, true)
	var f: float = clampf(frac, 0.0, 1.0)
	if f > 0.0:
		var fill := Rect2(r.position, Vector2(r.size.x * f, r.size.y))
		draw_rect(fill, col, true)
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, maxf(1.0, r.size.y * 0.3))), Color(1.0, 1.0, 1.0, 0.22), true)
	draw_rect(r, C_EDGE, false, 1.0)


func _bar_block(r: Rect2, label: String, value: String, frac: float, col: Color) -> void:
	_bar(r, frac, col)
	var by: float = r.position.y - 4.0 * _s
	_text(Vector2(r.position.x, by), label, 12.0, C_DIM)
	_text(Vector2(r.position.x, by), value, 12.0, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x)


func _draw_crosshair(c: Vector2, st: Station, wpn: Weapons) -> void:
	var s: float = _s
	var heat_f: float = clampf(st.heat / PLBalance.HEAT_MAX, 0.0, 1.0)
	var gap: float = (5.0 + 12.0 * heat_f + 10.0 * _kick) * s
	if st.focusing:
		gap *= 0.6
		draw_arc(c, 11.0 * s, 0.0, TAU, 24, C_VIOLET, 1.5 * s, true)
	var col: Color = C_RED if st.overheated else C_TEXT
	var len_px: float = 7.0 * s
	var th: float = 2.0 * s
	_tick(c, Vector2(1.0, 0.0), gap, len_px, th, col)
	_tick(c, Vector2(-1.0, 0.0), gap, len_px, th, col)
	_tick(c, Vector2(0.0, 1.0), gap, len_px, th, col)
	_tick(c, Vector2(0.0, -1.0), gap, len_px, th, col)
	if wpn.charging and wpn.current == PLBalance.Weapon.LANCE:
		var cdef: Dictionary = PLBalance.WEAPON_DEFS[PLBalance.Weapon.LANCE]
		var cmax: float = maxf(float(cdef["charge_max"]) * float(wpn.mods["charge_mult"]), 0.001)
		var t01: float = clampf(wpn.charge_t / cmax, 0.0, 1.0)
		if t01 > 0.01:
			draw_arc(c, 22.0 * s, -PI * 0.5, -PI * 0.5 + TAU * t01, 32, C_YELLOW, 3.0 * s, true)


func _tick(c: Vector2, d: Vector2, gap: float, len_px: float, th: float, col: Color) -> void:
	var a: Vector2 = c + d * gap
	var b: Vector2 = c + d * (gap + len_px)
	draw_line(a, b, C_SHADOW, th + 2.0, true)
	draw_line(a, b, col, th, true)


func _draw_scope(c: Vector2, has_cam: bool) -> void:
	var s: float = _s
	var k: float = _scope_k
	var ring := Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.45 * k)
	draw_arc(c, 64.0 * s, 0.0, TAU, 48, ring, 1.5 * s, true)
	_tick_scope(c, Vector2(1.0, 0.0), ring, s)
	_tick_scope(c, Vector2(-1.0, 0.0), ring, s)
	_tick_scope(c, Vector2(0.0, 1.0), ring, s)
	_tick_scope(c, Vector2(0.0, -1.0), ring, s)
	draw_circle(c, 1.6 * s, C_TEXT)
	if not has_cam:
		return
	_draw_weak_reticle(c)
	var rng: float = _aim_range()
	var rtxt: String = "RANGE ---"
	if rng >= 0.0:
		rtxt = "RANGE %d m" % roundi(rng)
	_text(Vector2(0.0, c.y + 88.0 * s), rtxt, 14.0, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, _sz.x)


## Distance to the nearest enemy the aim ray passes through, or -1 when none.
func _aim_range() -> float:
	var o: Vector3 = _cam.global_position
	var f: Vector3 = -_cam.global_transform.basis.z
	var best: float = -1.0
	for e: Enemy in _sim.enemies:
		if not e.alive:
			continue
		var to: Vector3 = e.pos - o
		var along: float = to.dot(f)
		if along <= e.radius:
			continue
		var perp: float = (to - f * along).length()
		if perp > e.radius:
			continue
		var d: float = along - sqrt(e.radius * e.radius - perp * perp)
		if best < 0.0 or d < best:
			best = d
	return best


## Bracket reticle on the nearest open weak core. Green when the crosshair sits on it.
func _draw_weak_reticle(c: Vector2) -> void:
	var s: float = _s
	var best_d: float = 140.0 * s
	var best_e: Enemy = null
	var best_sp := Vector2.ZERO
	for e: Enemy in _sim.enemies:
		if not e.alive or not e.weak_open or e.weak_radius <= 0.0:
			continue
		var wp: Vector3 = e.pos + e.weak_offset
		if _cam.is_position_behind(wp):
			continue
		var sp: Vector2 = _cam.unproject_position(wp)
		var d: float = sp.distance_to(c)
		if d < best_d:
			best_d = d
			best_e = e
			best_sp = sp
	if best_e == null:
		return
	var wpos: Vector3 = best_e.pos + best_e.weak_offset
	var edge: Vector2 = _cam.unproject_position(wpos + _cam.global_transform.basis.x * best_e.weak_radius)
	var r: float = clampf(edge.distance_to(best_sp), 8.0 * s, 140.0 * s)
	var inside: bool = c.distance_to(best_sp) <= r
	var col: Color = C_GREEN if inside else C_CYAN
	var rr: float = r + 6.0 * s
	for k in 4:
		var a0: float = float(k) * PI * 0.5 + 0.35
		draw_arc(best_sp, rr, a0, a0 + 0.9, 6, col, 2.0 * s, true)
	if inside:
		_text(Vector2(best_sp.x - 60.0 * s, best_sp.y + rr + 18.0 * s), "WEAK", 13.0, C_GREEN,
			HORIZONTAL_ALIGNMENT_CENTER, 120.0 * s)


func _tick_scope(c: Vector2, d: Vector2, col: Color, s: float) -> void:
	draw_line(c + d * (56.0 * s), c + d * (72.0 * s), col, 1.5 * s, true)


func _draw_hit(c: Vector2) -> void:
	if _hit_t <= 0.0:
		return
	var a: float = clampf(_hit_t / HIT_TIME, 0.0, 1.0)
	var base: Color = C_GOLD if _hit_crit else C_TEXT
	var col := Color(base.r, base.g, base.b, a)
	var r0: float = 6.0 * _s
	var r1: float = 13.0 * _s
	var th: float = 2.0 * _s
	var k: float = 0.7071
	draw_line(c + Vector2(k, k) * r0, c + Vector2(k, k) * r1, col, th, true)
	draw_line(c + Vector2(k, -k) * r0, c + Vector2(k, -k) * r1, col, th, true)
	draw_line(c + Vector2(-k, k) * r0, c + Vector2(-k, k) * r1, col, th, true)
	draw_line(c + Vector2(-k, -k) * r0, c + Vector2(-k, -k) * r1, col, th, true)


## Red chevrons at the screen edge for telegraphing enemies that are off screen or behind.
func _draw_threats() -> void:
	var cam: Camera3D = _cam
	var inv: Transform3D = cam.global_transform.affine_inverse()
	var c: Vector2 = _sz * 0.5
	var inset: float = ARROW_INSET * _s
	var inner := Rect2(inset, inset, maxf(0.0, _sz.x - 2.0 * inset), maxf(0.0, _sz.y - 2.0 * inset))
	var half: Vector2 = inner.size * 0.5
	var n: int = 0
	for e: Enemy in _sim.enemies:
		if n >= ARROW_MAX:
			break
		if not e.alive or e.telegraph <= 0.0:
			continue
		if not cam.is_position_behind(e.pos):
			var sp: Vector2 = cam.unproject_position(e.pos)
			if inner.has_point(sp):
				continue
		var local: Vector3 = inv * e.pos
		var d := Vector2(local.x, -local.y)
		if d.length_squared() < 0.000001:
			d = Vector2.DOWN
		d = d.normalized()
		var tx: float = INF
		if absf(d.x) > 0.0001:
			tx = half.x / absf(d.x)
		var ty: float = INF
		if absf(d.y) > 0.0001:
			ty = half.y / absf(d.y)
		var p: Vector2 = c + d * minf(tx, ty)
		var perp := Vector2(-d.y, d.x)
		var tip: Vector2 = p + d * (14.0 * _s)
		var back: Vector2 = p - d * (4.0 * _s)
		var wing: float = 10.0 * _s
		_chev[0] = back + perp * wing
		_chev[1] = tip
		_chev[2] = back - perp * wing
		var a: float = 0.5 + 0.5 * sin(_pulse * 9.0)
		draw_polyline(_chev, Color(C_ARROW.r, C_ARROW.g, C_ARROW.b, a), 4.0 * _s, true)
		n += 1


func _draw_status(st: Station) -> void:
	var hull_f: float = clampf(st.hull / PLBalance.STATION_HULL, 0.0, 1.0)
	var hull_col: Color = C_HULL
	if hull_f < 0.3 and int(_pulse * 5.0) % 2 == 0:
		hull_col = Color(1.0, 0.55, 0.5)
	_bar_block(_r_hull, "HULL", _hull_txt, hull_f, hull_col)
	_bar_block(_r_shield, "SHIELD", _shield_txt, st.shield / maxf(st.shield_max, 1.0), C_SHIELD)
	_bar_block(_r_energy, "ENERGY", _energy_txt, st.energy / PLBalance.ENERGY_MAX, C_YELLOW)
	var heat_col: Color = C_ORANGE
	var heat_label: String = "HEAT"
	if st.overheated:
		heat_label = "OVERHEAT"
		heat_col = C_RED if sin(_pulse * 14.0) > 0.0 else Color(0.45, 0.1, 0.1)
	_bar_block(_r_heat, heat_label, _heat_txt, st.heat / PLBalance.HEAT_MAX, heat_col)
	var focus_a: float = 1.0 if st.focus > 1.0 else 0.35
	var focus_col := Color(C_VIOLET.r, C_VIOLET.g, C_VIOLET.b, focus_a)
	_bar_block(_r_focus, "FOCUS", _focus_txt, st.focus / maxf(st.focus_max, 1.0), focus_col)


func _draw_weapons(st: Station, wpn: Weapons) -> void:
	var yy: float = _r_strip.position.y
	var s: float = _s
	for i in 4:
		var x: float = _r_strip.position.x + float(i) * (_slot_w + _slot_gap)
		var rect := Rect2(x, yy, _slot_w, _slot_h)
		var def: Dictionary = PLBalance.WEAPON_DEFS[i]
		var on: bool = wpn.current == i
		draw_rect(rect, C_SLOT_ON if on else C_SLOT_BG, true)
		var reload: float = float(wpn.mods["reload_mult"])
		var cd_max: float = maxf(float(def["cooldown"]) * reload, 0.001)
		var frac: float = clampf(float(wpn.cooldown[i]) / cd_max, 0.0, 1.0)
		if frac > 0.0:
			draw_rect(Rect2(x, yy, _slot_w, _slot_h * frac), C_SWEEP, true)
		if i == PLBalance.Weapon.LANCE and wpn.charging:
			var cmax: float = maxf(float(def["charge_max"]) * float(wpn.mods["charge_mult"]), 0.001)
			var t01: float = clampf(wpn.charge_t / cmax, 0.0, 1.0)
			draw_rect(Rect2(x, yy + _slot_h * (1.0 - t01), _slot_w, _slot_h * t01),
				Color(C_YELLOW.r, C_YELLOW.g, C_YELLOW.b, 0.35), true)
		draw_rect(rect, C_CYAN if on else C_EDGE, false, (2.0 * s) if on else 1.0)
		var ready: bool = st.energy >= float(def["energy"])
		if i == PLBalance.Weapon.SWARM:
			ready = ready and wpn.pods >= 1.0
		var name_col: Color = C_TEXT if ready else C_DIM
		_text(Vector2(x + 6.0 * s, yy + 15.0 * s), KEYS[i], 12.0, C_CYAN if on else C_DIM)
		_text(Vector2(x, yy + _slot_h - 8.0 * s), String(def["name"]), 13.0, name_col,
			HORIZONTAL_ALIGNMENT_CENTER, _slot_w)
		if i == PLBalance.Weapon.SWARM:
			var mx: int = wpn.max_pods()
			var have: int = int(floor(wpn.pods))
			_text(Vector2(x, yy + 15.0 * s), _pods_txt, 11.0, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, _slot_w - 6.0 * s)
			var pip_y: float = yy + _slot_h * 0.52
			var step: float = 9.0 * s
			var start_x: float = x + _slot_w * 0.5 - float(mx - 1) * step * 0.5
			for j in mx:
				draw_circle(Vector2(start_x + float(j) * step, pip_y), 3.0 * s, C_CYAN if j < have else C_EDGE)


func _draw_top(sim: Sim) -> void:
	var s: float = _s
	var w: float = _sz.x
	var m: float = _m
	_text(Vector2(m, m + 12.0 * s), _sector_cap, 11.0, C_DIM)
	_text(Vector2(m, m + 36.0 * s), _sector_title, 20.0, C_TEXT)
	_text(Vector2(m, m + 58.0 * s), _wave_txt, 13.0, C_CYAN)
	var rw: float = w - 2.0 * m
	_text(Vector2(m, m + 12.0 * s), "SCORE", 11.0, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, rw)
	_text(Vector2(m, m + 46.0 * s), _score_txt, 34.0, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, rw)
	if sim.combo > 0 and sim.combo_left() > 0.0:
		var left: float = sim.combo_left() / PLBalance.COMBO_WINDOW
		var mult_col: Color = C_GOLD if sim.combo_mult >= 2 else C_DIM
		_text(Vector2(m, m + 72.0 * s), _combo_txt, 14.0, mult_col, HORIZONTAL_ALIGNMENT_RIGHT, rw)
		_bar(Rect2(w - m - 150.0 * s, m + 80.0 * s, 150.0 * s, 5.0 * s), left, C_ORANGE)


func _draw_boss() -> void:
	var b: Enemy = _boss
	if b == null:
		return
	var s: float = _s
	var w: float = _sz.x
	var m: float = _m
	var bw: float = (w - 2.0 * m) if _compact else minf(520.0 * s, w * 0.6)
	var bx: float = (w - bw) * 0.5
	var by: float = (m + 100.0 * s) if _compact else (m + 4.0 * s)
	var frac: float = clampf(b.hp / maxf(b.max_hp, 1.0), 0.0, 1.0)
	_text(Vector2(bx, by - 6.0 * s), _boss_title, 14.0, C_TEXT)
	_text(Vector2(bx, by - 6.0 * s), _boss_txt, 14.0, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, bw)
	var bar := Rect2(bx, by, bw, 12.0 * s)
	_bar(bar, frac, Color(1.0, 0.35, 0.3))
	if b.kind == PLBalance.Kind.DREADNOUGHT:
		for th in EnemyAI.PHASE_THRESHOLDS:
			var tx: float = bx + bw * float(th)
			draw_line(Vector2(tx, by - 2.0 * s), Vector2(tx, by + 14.0 * s), C_TEXT, 2.0 * s, true)


func _draw_dry() -> void:
	if _dry_t <= 0.0:
		return
	var a: float = clampf(_dry_t / 0.3, 0.0, 1.0)
	var col := Color(_dry_col.r, _dry_col.g, _dry_col.b, a)
	var y: float = _r_energy.position.y - 10.0 * _s
	_text(Vector2(0.0, y), _dry_txt, 16.0, col, HORIZONTAL_ALIGNMENT_CENTER, _sz.x)


## Two-sided gradient bands along the screen edges. ix and iy are band thickness as fractions of the size.
func _vignette(ix_frac: float, iy_frac: float, col: Color, alpha: float) -> void:
	var w: float = _sz.x
	var h: float = _sz.y
	var ix: float = w * ix_frac
	var iy: float = h * iy_frac
	var o := Color(col.r, col.g, col.b, col.a * alpha)
	var z := Color(col.r, col.g, col.b, 0.0)
	_quad_draw(Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w - ix, iy), Vector2(ix, iy), o, o, z, z)
	_quad_draw(Vector2(w, 0.0), Vector2(w, h), Vector2(w - ix, h - iy), Vector2(w - ix, iy), o, o, z, z)
	_quad_draw(Vector2(w, h), Vector2(0.0, h), Vector2(ix, h - iy), Vector2(w - ix, h - iy), o, o, z, z)
	_quad_draw(Vector2(0.0, h), Vector2(0.0, 0.0), Vector2(ix, iy), Vector2(ix, h - iy), o, o, z, z)


func _quad_draw(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	_quad[0] = p0
	_quad[1] = p1
	_quad[2] = p2
	_quad[3] = p3
	_quad_cols[0] = c0
	_quad_cols[1] = c1
	_quad_cols[2] = c2
	_quad_cols[3] = c3
	draw_polygon(_quad, _quad_cols)
