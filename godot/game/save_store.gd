class_name SaveStore
extends RefCounted
## Profile persistence in user://profile.json.
## Saves go to a temp file that is renamed over the save, so a crash cannot leave a half-written file.
## A save that cannot be parsed is copied to user://profile.corrupt-<unix>.json before a fresh profile is used,
## so nothing is silently overwritten. Port of Game/SaveStore.cs (static).

const PROFILE_PATH: String = "user://profile.json"
const TEMP_PATH: String = "user://profile.json.tmp"


## Profile as pretty JSON text. No file access.
static func to_json(p: Profile) -> String:
	return JSON.stringify(p.to_dict(), "  ")


## Profile from JSON text. Unreadable text gives a fresh profile. No file access.
static func from_json(text: String) -> Profile:
	var data = _decode(text)
	if data == null:
		return Profile.new()
	return Profile.from_dict(data)


## Reads the save. Returns {profile: Profile, status: "ok" | "missing" | "corrupt", backup: String}.
## For a corrupt file, backup is the path of the copy that was kept, or "" if the copy could not be written.
static func load_profile() -> Dictionary:
	if not FileAccess.file_exists(PROFILE_PATH):
		return {"profile": Profile.new(), "status": "missing", "backup": ""}
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(PROFILE_PATH)
	var data = _decode(bytes.get_string_from_utf8())
	if data == null:
		return {"profile": Profile.new(), "status": "corrupt", "backup": _backup_corrupt(bytes)}
	return {"profile": Profile.from_dict(data), "status": "ok", "backup": ""}


## Writes the profile atomically: temp file first, then rename over profile.json. Returns false on any failure.
static func save_profile(p: Profile) -> bool:
	var f: FileAccess = FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_json(p))
	var written: bool = f.get_error() == OK
	f.close()
	if not written:
		return false
	var err: int = DirAccess.rename_absolute(ProjectSettings.globalize_path(TEMP_PATH), ProjectSettings.globalize_path(PROFILE_PATH))
	return err == OK


## Parses JSON text into a Dictionary, or null when it is not a JSON object.
static func _decode(text: String) -> Variant:
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		return null
	if typeof(parser.data) != TYPE_DICTIONARY:
		return null
	return parser.data


## Copies the unreadable save next to itself. Never overwrites an existing backup. Returns the path, or "".
static func _backup_corrupt(bytes: PackedByteArray) -> String:
	var stamp: int = int(Time.get_unix_time_from_system())
	var path: String = "user://profile.corrupt-%d.json" % stamp
	var n: int = 1
	while FileAccess.file_exists(path):
		path = "user://profile.corrupt-%d-%d.json" % [stamp, n]
		n += 1
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(bytes)
	var written: bool = f.get_error() == OK
	f.close()
	return path if written else ""
