class_name StageCatalog
extends RefCounted
## Campaign stages, themes and procedural waves. Port of Stages.cs (StageCatalog and WaveFactory).
##
## Dictionary shapes:
##   theme: {kind, name, enemy (Array of 0xRRGGBB ints), accent, fog, table, grid}
##   stage: {index, title, subtitle, theme, path (PackedFloat32Array x,z pairs, last point is the core),
##           waves (Array of wave), hp_scale}
##   wave:  {groups (Array of group), total_count}
##   group: {kind (Balance.EnemyKind int), count, delay, interval}
##
## The C# maths is float32. Stage and wave values that feed integer rounding (wave counts) are
## rounded through float32 here, so the counts match C# exactly.

const WAVES_PER_STAGE: int = 8

const TITLES: Array = [
	"Starfall Reach", "Neon Ascendancy", "Midnight Harbor",
	"Sands of the Scarab King", "Iron Pantheon", "The Last Frequency",
]

const SUBTITLES: Array = [
	"The Hollow Tide breaches the outer colonies.",
	"The skyline becomes the front line.",
	"Something climbs out of Ravenport's storm drains.",
	"Golden scarabs cross the Sun Gate for the first time.",
	"A frozen rift shatters the gates of the Pantheon.",
	"Every rift converges on one frequency.",
]

static var _themes_cache: Array = []
static var _stages_cache: Array = []


static func themes() -> Array:
	if _themes_cache.is_empty():
		_themes_cache = _build_themes()
	return _themes_cache


static func all() -> Array:
	if _stages_cache.is_empty():
		_stages_cache = _build_stages()
	return _stages_cache


static func count() -> int:
	return all().size()


## Procedural waves: the swarm grows each wave, brutes join late, a Titan closes every chapter.
static func build_waves(stage_index: int, wave_count_value: int) -> Array:
	var k: float = _f32(1.0 + _f32(_f32(0.35) * float(stage_index)))
	var out: Array = []
	for w in range(wave_count_value):
		var groups: Array = []
		groups.append(_group(Balance.EnemyKind.DRONE, _scale(40 + 25 * w, k), 0.0, 0.03))
		if w >= 1:
			groups.append(_group(Balance.EnemyKind.WALKER, _scale(14 + 10 * w, k), 2.0, 0.12))
		if w >= 2:
			groups.append(_group(Balance.EnemyKind.SHADE, _scale(10 + 8 * w, k), 4.0, 0.08))
		if w >= 4:
			groups.append(_group(Balance.EnemyKind.BRUTE, _scale(3 + 2 * (w - 3), k), 7.0, 0.8))
		if w == wave_count_value - 1:
			var titans: int = 2 if stage_index >= 3 else 1
			groups.append(_group(Balance.EnemyKind.TITAN, titans, 9.0, 6.0))
		var total: int = 0
		for g in groups:
			total += int(g["count"])
		out.append({"groups": groups, "total_count": total})
	return out


static func _build_themes() -> Array:
	return [
		{"kind": Balance.ThemeKind.SPACE_OPERA, "name": "Space Opera",
			"enemy": [0x3DFFEA, 0xFFD23F, 0xFF4D6D, 0x7B61FF],
			"accent": 0xE8F7FF, "fog": 0x05060F, "table": 0x0B1026, "grid": 0x2AF5FF},
		{"kind": Balance.ThemeKind.METROPOLIS, "name": "Superhero Metropolis",
			"enemy": [0xFF3B3B, 0x3B82FF, 0xFFE14D, 0xB84DFF],
			"accent": 0xFF2E88, "fog": 0x0A0716, "table": 0x140B22, "grid": 0xFF2E88},
		{"kind": Balance.ThemeKind.NOIR_HARBOR, "name": "Noir Harbor",
			"enemy": [0x9BA3B5, 0x5CFFB0, 0xFFB347, 0x6B7BFF],
			"accent": 0x5CFFB0, "fog": 0x06080C, "table": 0x0E131B, "grid": 0x3DFFB0},
		{"kind": Balance.ThemeKind.EGYPT, "name": "Ancient Egypt",
			"enemy": [0xFFC53D, 0x2EE6D6, 0xF2A65A, 0xE8D8A0],
			"accent": 0xFFE08A, "fog": 0x1A1206, "table": 0x2A1E0E, "grid": 0x2EE6D6},
		{"kind": Balance.ThemeKind.NORSE, "name": "Iron Pantheon",
			"enemy": [0x9FD8FF, 0xE0F7FF, 0x6AA8FF, 0xB8C7FF],
			"accent": 0xE0F7FF, "fog": 0x061020, "table": 0x0C1B30, "grid": 0x9FD8FF},
		{"kind": Balance.ThemeKind.NEON_FUTURE, "name": "The Last Frequency",
			"enemy": [0xFF00E6, 0x00FFF0, 0x7CFF00, 0xFF8A00],
			"accent": 0x00FFF0, "fog": 0x04000A, "table": 0x0B0018, "grid": 0xFF00E6},
	]


# Paths stay inside +-1.35 m so every chapter keeps buildable ground.
static func _build_paths() -> Array:
	return [
		PackedFloat32Array([-1.4, -1.2, -0.4, -1.2, -0.4, 0.2, 0.7, 0.2, 0.7, -0.6, 1.2, -0.6, 1.2, 0.9]),
		PackedFloat32Array([-1.4, 0.9, -0.2, 0.9, -0.2, -0.2, -1.0, -0.2, -1.0, -1.1, 0.5, -1.1, 0.5, 0.5, 1.3, 0.5]),
		PackedFloat32Array([1.4, -1.3, -0.3, -1.3, -0.3, -0.4, 0.9, -0.4, 0.9, 0.5, -0.9, 0.5, -0.9, 1.3, -1.3, 1.3]),
		PackedFloat32Array([-1.4, -1.4, 1.2, -1.4, 1.2, 1.2, -0.9, 1.2, -0.9, -0.7, 0.5, -0.7, 0.5, 0.4, -0.2, 0.4]),
		PackedFloat32Array([-1.4, 1.3, -0.6, 0.3, 0.2, -0.5, 1.1, -1.1, 1.3, 0.1, 0.0, 0.9, -0.8, 0.0]),
		PackedFloat32Array([-1.4, -0.5, -0.7, -0.5, -0.2, 0.4, 0.5, 0.9, 1.3, 0.9, 1.3, -0.2, 0.4, -0.5, 0.1, -1.3]),
	]


static func _build_stages() -> Array:
	var theme_list: Array = themes()
	var paths: Array = _build_paths()
	var out: Array = []
	for s in range(theme_list.size()):
		out.append({
			"index": s,
			"title": TITLES[s],
			"subtitle": SUBTITLES[s],
			"theme": theme_list[s],
			"path": paths[s],
			"waves": build_waves(s, WAVES_PER_STAGE),
			"hp_scale": _f32(1.0 + _f32(_f32(0.2) * float(s))),
		})
	return out


static func _group(kind: int, count: int, delay: float, interval: float) -> Dictionary:
	return {"kind": kind, "count": count, "delay": _f32(delay), "interval": _f32(interval)}


# C# (int)(baseCount * k + 0.5f) with float32 intermediates.
static func _scale(base_count: int, k: float) -> int:
	var prod: float = _f32(float(base_count) * k)
	return int(_f32(prod + 0.5))


# Rounds a 64-bit float to float32 precision.
static func _f32(v: float) -> float:
	return PackedFloat32Array([v])[0]
