class_name Voice
extends Node
## Speech for dialogue lines.
## Android: the platform text-to-speech engine through DisplayServer.
## Desktop: the Piper CLI and a VITS voice model in user://voice (see scripts/fetch_voice.py). Piper runs as a child
## process with the text on stdin; _process plays the cached WAV once the process has exited. Nothing blocks the frame.
## Port of Game/Voice.cs. The Piper path is desktop only.

const FOLDER: String = "user://voice"
const PIPER_PATH: String = "user://voice/piper/piper"
const MODEL_PATH: String = "user://voice/en_US-amy-low.onnx"
const CACHE_FOLDER: String = "user://voice/cache"
const TTS_VOLUME: int = 50

var _player: AudioStreamPlayer = null
var _probed: bool = false
var _available: bool = false
var _android: bool = false
var _piper_abs: String = ""
var _model_abs: String = ""
var _pending_pid: int = -1
var _pending_wav: String = ""
var _pending_err: FileAccess = null   # kept open so piper does not hit a closed stderr pipe


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = -1.0
	add_child(_player)
	_probe()


## True when speech can run: TTS on Android, or the Piper binary and model on desktop.
func available() -> bool:
	if not _probed:
		_probe()
	return _available


## Speaks one line at the given rate (speaker speed). Stops whatever is playing or pending first.
func speak(text: String, rate: float) -> void:
	stop()
	if not available() or text.strip_edges() == "":
		return
	var speed: float = clampf(rate, 0.1, 10.0)
	if _android:
		DisplayServer.tts_speak(text, "", TTS_VOLUME, 1.0, speed, 0, true)
		return
	var wav_user: String = "%s/%s.wav" % [CACHE_FOLDER, ("%s|%.2f" % [text, speed]).md5_text()]
	if FileAccess.file_exists(wav_user):
		_play_file(wav_user)
		return
	_start_piper(text, wav_user)


## Silences speech and forgets any synthesis still running. A piper process that is still running is left to
## finish and its WAV is simply not played.
func stop() -> void:
	_pending_pid = -1
	_pending_wav = ""
	if _android:
		DisplayServer.tts_stop()
	elif _player != null and _player.playing:
		_player.stop()


func _process(_delta: float) -> void:
	if _pending_pid < 0:
		return
	if OS.is_process_running(_pending_pid):
		return
	var wav: String = _pending_wav
	_pending_pid = -1
	_pending_wav = ""
	_pending_err = null
	if FileAccess.file_exists(wav):
		_play_file(wav)


func _probe() -> void:
	_probed = true
	_android = OS.get_name() == "Android"
	if _android:
		_available = DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) and DisplayServer.tts_get_voices().size() > 0
		return
	_piper_abs = ProjectSettings.globalize_path(PIPER_PATH)
	_model_abs = ProjectSettings.globalize_path(MODEL_PATH)
	_available = FileAccess.file_exists(PIPER_PATH) and FileAccess.file_exists(MODEL_PATH)
	if _available:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_FOLDER))


func _start_piper(text: String, wav_user: String) -> void:
	var args: PackedStringArray = PackedStringArray([
		"--model", _model_abs,
		"--output_file", ProjectSettings.globalize_path(wav_user),
	])
	var pipes: Dictionary = OS.execute_with_pipe(_piper_abs, args)
	if pipes.is_empty():
		return
	var pipe_in: FileAccess = pipes["stdio"]
	pipe_in.store_string(text)
	pipe_in.close()
	_pending_err = pipes["stderr"]
	_pending_pid = int(pipes["pid"])
	_pending_wav = wav_user


func _play_file(wav_user: String) -> void:
	if _player == null:
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(wav_user)
	if bytes.is_empty():
		return
	var stream: AudioStreamWAV = AudioStreamWAV.load_from_buffer(bytes)
	if stream == null:
		return
	_player.stream = stream
	_player.play()
