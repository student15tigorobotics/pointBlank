class_name Hub
extends Node3D
## Command hub: stage select, upgrade shop, leaderboard, cheat keypad and options. Rebuilt for each tab so every
## button reflects the saved profile. Port of Game/Hub.cs. Saves go through app.save(), never SaveStore directly.

const CENTER: Vector3 = Vector3(0.0, 1.45, -2.0)
const TABS: Array = ["stages", "shop", "board", "codes", "options"]
const TAB_NAMES: Array = ["STAGES", "SHOP", "BOARD", "CODES", "OPTIONS"]
const SHORT_NAMES: Array = ["STARFALL REACH", "NEON ASCENDANCY", "MIDNIGHT HARBOR", "SCARAB KING", "IRON PANTHEON", "LAST FREQUENCY"]
const TIER_NAMES: Array = ["LOW", "MEDIUM", "HIGH"]
const KEYS: Array = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "CLR", "0", "ENTER"]

var app: Boot = null
var profile: Profile = null


## Builds the whole tab. Called once per tab change; the caller frees the previous hub.
func _init(boot: Boot, tab: String, message: String) -> void:
	app = boot
	profile = boot.profile
	Ui.quad(self, _p(0.0, 0.0), Vector2(2.9, 2.05), Ui.PANEL)
	Ui.label(self, "POINTBLANK  COMMAND", _p(0.0, 0.9), 42, Ui.ACCENT)
	Ui.label(self, "BANK  %d CR" % profile.bank, _p(0.0, 0.76), 28, Ui.GOLD)

	for t in TABS.size():
		var key: String = TABS[t]
		var selected: bool = key == tab
		Ui.button(self, TAB_NAMES[t], _p(-1.2 + t * 0.6, 0.6), Vector2(0.56, 0.12), Ui.GOLD if selected else Ui.DIM,
			Callable(app, "show_hub").bind(key, ""), 26)

	match tab:
		"shop":
			_build_shop()
		"board":
			_build_board()
		"codes":
			_build_codes()
		"options":
			_build_options()
		_:
			_build_stages()

	Ui.label(self, message, _p(0.0, -0.92), 24, Ui.WARN)


func _p(x: float, y: float) -> Vector3:
	return Vector3(CENTER.x + x, CENTER.y + y, CENTER.z + 0.03)


func _build_stages() -> void:
	for i in StageCatalog.count():
		var stage: int = i
		var x: float = -0.95 + (i % 3) * 0.95
		var y: float = 0.12 - floori(i / 3.0) * 0.5
		var status: String
		if not profile.can_play_stage(i):
			status = "LOCKED"
		elif int(profile.stage_stars[i]) == 0:
			status = "NEW CHAPTER"
		else:
			status = "%d / 3 STARS" % int(profile.stage_stars[i])
		var label: String = "%d  %s\n%s" % [i + 1, SHORT_NAMES[i], status]
		Ui.button(self, label, _p(x, y), Vector2(0.84, 0.42),
			Ui.ACCENT if profile.can_play_stage(i) else Ui.DIM,
			Callable(app, "start_stage").bind(stage), 24)
	Ui.label(self, "Clear a chapter to unlock the next. Upgrades can be bought in SHOP between chapters.", _p(0.0, -0.62), 22, Ui.DIM)


func _build_shop() -> void:
	Ui.label_left(self, "UPGRADES", _p(-1.38, 0.45), 30, Ui.ACCENT)
	Ui.label_left(self, "UNLOCKS", _p(0.1, 0.45), 30, Ui.ACCENT)

	var upgrades: Array = UpgradeCatalog.all()
	for i in upgrades.size():
		var def: Dictionary = upgrades[i]
		var level: int = int(profile.upgrade_levels[i])
		var max_level: int = int(def["max_level"])
		var y: float = 0.3 - i * 0.11
		Ui.label_left(self, "%s  %d/%d" % [def["name"], level, max_level], _p(-1.38, y), 22, Color.WHITE)
		Ui.label_left(self, String(def["description"]), _p(-1.38, y - 0.045), 16, Ui.DIM)
		var upgrade_id: int = int(def["id"])
		var is_max: bool = level >= max_level
		var cost: int = UpgradeCatalog.next_cost(def, level)
		var cb: Callable = Callable()
		if not is_max:
			cb = Callable(self, "_purchase").bind(upgrade_id)
		var btn: Button3D = Ui.button(self, "MAX" if is_max else "BUY %d" % cost, _p(-0.42, y), Vector2(0.52, 0.085),
			Ui.DIM if is_max else Ui.GOLD, cb, 20)
		btn.enabled = not is_max

	var unlocks: Array = UnlockCatalog.all()
	for i in unlocks.size():
		var def: Dictionary = unlocks[i]
		var y: float = 0.3 - i * 0.11
		var owned: bool = profile.unlocks.has(def["key"])
		Ui.label_left(self, String(def["title"]), _p(0.1, y), 22, Ui.DIM if owned else Color.WHITE)
		var cb: Callable = Callable()
		if not owned:
			cb = Callable(self, "_buy_unlock").bind(def)
		var btn: Button3D = Ui.button(self, "OWNED" if owned else "BUY %d" % int(def["cost"]), _p(1.12, y), Vector2(0.52, 0.085),
			Ui.DIM if owned else Ui.GOLD, cb, 20)
		btn.enabled = not owned


func _purchase(id: int) -> void:
	var upgrade_name: String = String(UpgradeCatalog.get_def(id)["name"])
	var ok: bool = profile.try_buy_upgrade(id)
	if ok:
		app.save()
	app.show_hub("shop", (upgrade_name + " upgraded") if ok else "Not enough credits")


func _buy_unlock(def: Dictionary) -> void:
	var ok: bool = profile.try_buy_unlock(def)
	if ok:
		app.save()
	app.show_hub("shop", (String(def["title"]) + " unlocked") if ok else "Not enough credits")


func _build_board() -> void:
	Ui.label_left(self, "#", _p(-1.38, 0.45), 24, Ui.ACCENT)
	Ui.label_left(self, "CALLSIGN", _p(-1.2, 0.45), 24, Ui.ACCENT)
	Ui.label(self, "SCORE", _p(0.55, 0.45), 24, Ui.ACCENT)
	Ui.label(self, "CHAPTER", _p(1.2, 0.45), 24, Ui.ACCENT)
	for i in Leaderboard.SIZE:
		var y: float = 0.3 - i * 0.11
		var has: bool = i < profile.board.size()
		var entry: Dictionary = profile.board[i] if has else {}
		Ui.label_left(self, "%02d" % (i + 1), _p(-1.38, y), 24, Ui.DIM)
		Ui.label_left(self, String(entry["name"]) if has else "-", _p(-1.2, y), 24, Color.WHITE)
		Ui.label(self, "%d" % int(entry["score"]) if has else "-", _p(0.55, y), 24, Ui.GOLD)
		Ui.label(self, "%d" % int(entry["stage"]) if has else "-", _p(1.2, y), 24, Ui.DIM)


func _build_codes() -> void:
	var entry: String = app.code_entry
	var shown: String = ""
	for i in 4:
		shown += entry.substr(i, 1) if i < entry.length() else "_"
		if i < 3:
			shown += "  "
	Ui.label(self, shown, _p(-0.85, 0.42), 40, Ui.ACCENT)

	for k in KEYS.size():
		var key: String = KEYS[k]
		var x: float = -1.2 + (k % 3) * 0.35
		var y: float = 0.1 - floori(k / 3.0) * 0.2
		Ui.button(self, key, _p(x, y), Vector2(0.3, 0.14), Ui.GOLD if key == "ENTER" else Ui.ACCENT,
			Callable(self, "_key").bind(key), 26)

	Ui.label_left(self, "CHAPTER CODES", _p(0.25, 0.42), 28, Ui.ACCENT)
	for ch in StageCatalog.count():
		var y: float = 0.2 - ch * 0.13
		var def: Dictionary = CheatCatalog.for_chapter(ch)
		if def.is_empty():
			continue
		var code: String = String(def["code"])
		var revealed: bool = profile.revealed.has(code)
		var used: bool = profile.redeemed.has(code)
		var detail: String = (code + "   " + ("USED" if used else "READY")) if revealed else "????   LOCKED"
		Ui.label_left(self, "CH%d   %s" % [ch + 1, detail], _p(0.25, y), 24, Color.WHITE if revealed else Ui.DIM)
		if revealed and not used:
			Ui.label_left(self, "%s: %s" % [def["title"], def["text"]], _p(0.25, y - 0.05), 16, Ui.DIM)


func _key(key: String) -> void:
	if key == "CLR":
		app.code_entry = ""
		app.show_hub("codes", "")
		return
	if key == "ENTER":
		var entry: String = app.code_entry
		app.code_entry = ""
		if entry.length() < 4:
			app.show_hub("codes", "Enter four digits")
			return
		var res: Dictionary = profile.redeem(entry)
		if bool(res["ok"]):
			app.save()
		app.show_hub("codes", String(res["message"]))
		return
	if app.code_entry.length() < 4:
		app.code_entry += key
	app.show_hub("codes", "")


func _build_options() -> void:
	Ui.button(self, "VOICE  " + ("ON" if profile.tts_on else "OFF"), _p(0.0, 0.3), Vector2(1.1, 0.12), Ui.ACCENT,
		Callable(self, "_toggle_voice"), 26)
	Ui.button(self, "GRAPHICS  " + TIER_NAMES[profile.quality], _p(0.0, 0.12), Vector2(1.1, 0.12), Ui.ACCENT,
		Callable(self, "_cycle_quality"), 26)
	Ui.button(self, "SWARM BENCHMARK", _p(0.0, -0.06), Vector2(1.1, 0.12), Ui.ACCENT,
		Callable(app, "start_benchmark"), 26)
	Ui.button(self, "PRESS AGAIN TO WIPE" if app.reset_armed else "RESET CAMPAIGN", _p(0.0, -0.24), Vector2(1.1, 0.12), Ui.WARN,
		Callable(self, "_reset_campaign"), 26)

	if app.xr_active() and VrPassthrough.alpha_supported(XRServer.primary_interface):
		Ui.button(self, "PASSTHROUGH  " + ("ON" if app.passthrough_on() else "OFF"), _p(0.0, -0.38), Vector2(1.1, 0.12), Ui.ACCENT,
			Callable(self, "_toggle_passthrough"), 26)

	var voice_ok: bool = app.voice_available()
	Ui.label(self, "VOICE MODEL  " + ("FOUND" if voice_ok else "MISSING: run scripts/fetch_voice.py"), _p(0.0, -0.5), 22,
		Color.WHITE if voice_ok else Ui.DIM)

	var bench_text: String = "not run"
	if app.last_benchmark_aborted:
		bench_text = "ABORTED"
	elif profile.benchmark_tier >= 0:
		bench_text = "%d alive / %d visible (tier %s)" % [profile.benchmark_max, profile.benchmark_visible,
			TIER_NAMES[clampi(profile.benchmark_tier, 0, TIER_NAMES.size() - 1)]]
	Ui.label(self, "LAST BENCHMARK  " + bench_text, _p(0.0, -0.61), 22, Color.WHITE)
	Ui.label(self, "RENDER  " + ("OPENXR HEADSET" if app.xr_active() else "DESKTOP PREVIEW"), _p(0.0, -0.72), 22, Color.WHITE)
	Ui.label(self, "PASSTHROUGH PLUGIN  " + ("INSTALLED" if VrPassthrough.plugin_installed() else "MISSING: install godot_openxr_vendors v3.0.0+"),
		_p(0.0, -0.83), 22, Color.WHITE)


func _toggle_voice() -> void:
	profile.tts_on = not profile.tts_on
	app.save()
	app.show_hub("options", "")


func _cycle_quality() -> void:
	profile.quality = (profile.quality + 1) % 3
	app.apply_quality()
	app.save()
	app.show_hub("options", "")


func _toggle_passthrough() -> void:
	var ok: bool = app.toggle_passthrough()
	app.show_hub("options", "" if ok else "Passthrough is not available on this headset")


func _reset_campaign() -> void:
	if not app.reset_armed:
		app.reset_armed = true
		app.show_hub("options", "Press again to wipe campaign progress")
		return
	app.reset_armed = false
	profile.reset_campaign()
	app.save()
	app.show_hub("stages", "Campaign reset")
