# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name Save
extends RefCounted
## Settings and high scores in user:// as JSON. Writes go to a temporary file first, then replace the old one.

const SETTINGS_PATH := "user://picket_line_settings.json"
const SCORES_PATH := "user://picket_line_scores.json"


static func load_settings() -> Dictionary:
	var out := SaveData.default_settings()
	var data: Variant = _read_json(SETTINGS_PATH)
	if data is Dictionary:
		for k in out:
			if data.has(k):
				out[k] = _coerce(out[k], data[k])
	_clamp_settings(out)
	return out


static func save_settings(settings: Dictionary) -> bool:
	return _write_json(SETTINGS_PATH, settings)


static func load_scores() -> Array:
	var data: Variant = _read_json(SCORES_PATH)
	var out: Array = []
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				out.append(entry)
	while out.size() > SaveData.TOP_COUNT:
		out.pop_back()
	return out


static func save_scores(scores: Array) -> bool:
	return _write_json(SCORES_PATH, scores)


static func _clamp_settings(s: Dictionary) -> void:
	s.sensitivity = clampf(float(s.sensitivity), 0.2, 3.0)
	s.fov = clampf(float(s.fov), 60.0, 100.0)
	s.master = clampf(float(s.master), 0.0, 1.0)
	s.music = clampf(float(s.music), 0.0, 1.0)
	s.sfx = clampf(float(s.sfx), 0.0, 1.0)
	s.shake = clampf(float(s.shake), 0.0, 1.5)
	s.quality = clampi(int(s.quality), 0, 2)
	s.dodge_mode = clampi(int(s.dodge_mode), 0, 1)


static func _coerce(default_value: Variant, value: Variant) -> Variant:
	match typeof(default_value):
		TYPE_FLOAT:
			if value is float or value is int:
				return float(value)
		TYPE_INT:
			if value is float or value is int:
				return int(value)
		TYPE_BOOL:
			if value is bool:
				return value
	return default_value


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _write_json(path: String, value: Variant) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(value, "  "))
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp, path)
	return err == OK
