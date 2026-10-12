# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
# Picket Line is free software under GPL-3.0-or-later. See LICENSE in the repository root.
class_name GameAudio
extends Node
## Music with crossfades, and a pool of one-shot players for sound effects.
## Files come from assets/audio (written by scripts/gen_audio.py). A missing file is skipped with one warning.

const AUDIO_DIR := "res://games/picket_line/assets/audio/"
const POOL_SIZE := 16
const FADE_TIME := 1.6
const SILENT_DB := -80.0
const MUSIC_LOOPS := {"menu": true, "calm": true, "combat": true, "boss": true, "victory": false, "defeat": false}

var _pool: Array = []
var _music: Array = []
var _music_index := 0
var _track := ""
var _next_voice := 0
var _cache: Dictionary = {}
var _warned: Dictionary = {}
var _master := 0.8
var _music_level := 0.6
var _sfx_level := 0.8
var _tween: Tween


func build() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.volume_db = SILENT_DB
		add_child(m)
		_music.append(m)


func set_volumes(master: float, music_level: float, sfx_level: float) -> void:
	_master = master
	_music_level = music_level
	_sfx_level = sfx_level
	var current: AudioStreamPlayer = _music[_music_index]
	if current.playing:
		current.volume_db = _music_db()


func music(track: String) -> void:
	if track == _track:
		return
	_track = track
	var out_player: AudioStreamPlayer = _music[_music_index]
	_music_index = 1 - _music_index
	var in_player: AudioStreamPlayer = _music[_music_index]
	var stream := _load("music_" + track)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = bool(MUSIC_LOOPS.get(track, true))
	in_player.stream = stream
	in_player.volume_db = SILENT_DB
	if stream != null:
		in_player.play()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(out_player, "volume_db", SILENT_DB, FADE_TIME)
	if stream != null:
		_tween.tween_property(in_player, "volume_db", _music_db(), FADE_TIME)
	_tween.chain().tween_callback(out_player.stop)


func play_sfx(sfx: String, pitch: float = 1.0, volume: float = 1.0) -> void:
	var stream := _load("sfx_" + sfx)
	if stream == null:
		return
	var p := _free_voice()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(maxf(0.0001, _master * _sfx_level * volume))
	p.play()


## Maps simulation events to sounds. Called once per step with the events the step returned.
func handle_events(events: Array) -> void:
	for ev in events:
		match ev.type:
			"shot":
				_shot_sound(int(ev.weapon), ev)
			"charge_start":
				play_sfx("lance_charge", 1.0, 0.5)
			"dry":
				play_sfx("fire_empty", 1.0, 0.6)
			"overheat":
				play_sfx("overheat", 1.0, 0.8)
			"hit":
				if bool(ev.crit):
					play_sfx("hit_crit", _jitter(), 0.7)
				else:
					play_sfx("hit_enemy", _jitter(), 0.35)
			"kill":
				_kill_sound(ev)
			"detonate":
				play_sfx("explosion", _jitter(0.06), 0.9)
			"snap":
				play_sfx("snap", 1.0, 0.9)
			"combo":
				play_sfx("combo_up", 1.0 + 0.05 * float(ev.mult), 0.7)
			"enemy_fire":
				play_sfx("enemy_beam" if String(ev.mode) == "beam" else "enemy_shell", _jitter(0.04), 0.6)
			"telegraph":
				if int(ev.kind) == PLBalance.Kind.GUNSHIP or int(ev.kind) == PLBalance.Kind.DREADNOUGHT:
					play_sfx("lock_tone", 1.0, 0.35)
			"player_hit":
				_hit_sound(ev)
			"dodge":
				play_sfx("dodge", 1.0, 0.8)
			"weapon":
				play_sfx("ui_click", 1.2, 0.5)
			"lock":
				play_sfx("lock_tone", 1.3, 0.4)
			"wave_start":
				play_sfx("wave_start", 1.0, 0.8)
			"boss_warning", "boss_phase":
				play_sfx("boss_warning", 1.0, 0.9)
			"boss_spawn":
				play_sfx("kill_big", 0.7, 0.6)
			"sector_clear":
				play_sfx("sector_clear", 1.0, 0.9)
			"game_over":
				play_sfx("game_over", 1.0, 0.9)
			"crash":
				play_sfx("explosion", _jitter(0.1), 0.35)


func ui(sfx: String) -> void:
	play_sfx(sfx, 1.0, 0.7)


func _shot_sound(weapon: int, ev: Dictionary) -> void:
	match weapon:
		PLBalance.Weapon.PULSE:
			play_sfx("fire_pulse", _jitter(0.05), 0.45)
		PLBalance.Weapon.LANCE:
			play_sfx("fire_lance", 1.0, 0.9)
		PLBalance.Weapon.FLAK:
			play_sfx("fire_flak", 1.0, 0.8)
		PLBalance.Weapon.SWARM:
			play_sfx("fire_swarm", _jitter(0.03), 0.7)


func _kill_sound(ev: Dictionary) -> void:
	if bool(ev.boss):
		play_sfx("boss_die", 1.0, 1.0)
	elif int(ev.kind) == PLBalance.Kind.CARRIER or int(ev.kind) == PLBalance.Kind.DREADNOUGHT:
		play_sfx("kill_big", 1.0, 0.9)
	elif int(ev.kind) == PLBalance.Kind.GUNSHIP or int(ev.kind) == PLBalance.Kind.BOMBER:
		play_sfx("kill_big", _jitter(0.05), 0.55)
	else:
		play_sfx("kill_small", _jitter(0.08), 0.6)


func _hit_sound(ev: Dictionary) -> void:
	if bool(ev.blocked):
		play_sfx("shield_hit", 1.0, 0.35)
	elif float(ev.applied_shield) > 0.0 and float(ev.applied_hull) <= 0.0:
		play_sfx("shield_hit", 1.0, 0.8)
	else:
		play_sfx("hull_hit", 1.0, 0.9)


func _jitter(amount: float = 0.04) -> float:
	return randf_range(1.0 - amount, 1.0 + amount)


func _music_db() -> float:
	return linear_to_db(maxf(0.0001, _master * _music_level))


func _free_voice() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	_next_voice = (_next_voice + 1) % POOL_SIZE
	return _pool[_next_voice]


func _load(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := AUDIO_DIR + name + ".ogg"
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	else:
		if not _warned.has(name):
			_warned[name] = true
			push_warning("Picket Line audio missing: %s (run scripts/gen_audio.py)" % path)
	_cache[name] = stream
	return stream
