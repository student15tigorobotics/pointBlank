# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name Audio
extends Node
## All game sound: a pooled SFX layer, background music with crossfade, and a battle ambience
## loop. The streams come from assets/audio (fetched by scripts/fetch_assets.py, credited in
## CREDITS.md). Static entry points route through the single instance Boot owns, so call sites
## stay one-liners and are safe no-ops when audio is absent (headless smoke).

const SFX_POOL: int = 10
const MUSIC_DB: float = -16.0    # background, not foreground (owner: music level too high)
const AMBIENT_DB: float = -19.0
const FADE_S: float = 0.8
const THROTTLE_MS: int = 70     # same-sound minimum spacing, keeps mass deaths from clipping

static var inst: Audio = null

const SFX: Dictionary = {
	"shot.blaster": "res://assets/audio/sfx.shot.blaster.ogg",
	"shot.scatter": "res://assets/audio/sfx.shot.scatter.ogg",
	"shot.rail": "res://assets/audio/sfx.shot.rail.ogg",
	"shot.arc": "res://assets/audio/sfx.shot.arc.wav",
	"explosion": "res://assets/audio/sfx.explosion.nova.ogg",
	"tower.place": "res://assets/audio/sfx.tower.place.ogg",
	"tower.sell": "res://assets/audio/sfx.tower.sell.ogg",
	"tower.upgrade": "res://assets/audio/sfx.tower.upgrade.ogg",
	"wave.start": "res://assets/audio/sfx.wave.start.wav",
	"wave.clear": "res://assets/audio/sfx.wave.clear.wav",
	"early_call": "res://assets/audio/sfx.early_call.wav",
	"core.damage": "res://assets/audio/sfx.core.damage.ogg",
	"overkill": "res://assets/audio/sfx.credits.overkill.ogg",
	"ui.click": "res://assets/audio/sfx.ui.click.wav",
	"ui.hover": "res://assets/audio/sfx.ui.hover.wav",
	"blip": "res://assets/audio/sfx.dialogue.blip.wav",
	"victory": "res://assets/audio/sfx.victory.ogg",
	"defeat": "res://assets/audio/sfx.defeat.wav",
}
const MUSIC: Dictionary = {
	"menu": "res://assets/audio/amb.menu.wav",   # plain sea & wind: the pregame calm
	"hub": "res://assets/audio/music.hub.mp3",
	"battle": "res://assets/audio/music.battle.mp3",
}
const AMBIENT_PATH: String = "res://assets/audio/amb.battlefield.wav"

var _streams: Dictionary = {}
var _pool: Array = []
var _next: int = 0
var _music: AudioStreamPlayer = null
var _ambient: AudioStreamPlayer = null
var _track: String = ""
var _last_ms: Dictionary = {}
var _fade: Tween = null


func _ready() -> void:
	inst = self
	for key in SFX:
		var s: AudioStream = load(SFX[key])
		if s != null:
			_streams[key] = s
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = MUSIC_DB
	add_child(_music)
	_ambient = AudioStreamPlayer.new()
	_ambient.volume_db = AMBIENT_DB
	var amb: AudioStream = load(AMBIENT_PATH)
	if amb != null:
		if amb is AudioStreamWAV:
			amb.loop_mode = AudioStreamWAV.LOOP_FORWARD
			var bytes_per_frame: int = (2 if amb.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if amb.stereo else 1)
			amb.loop_end = amb.data.size() / bytes_per_frame
		_ambient.stream = amb
	add_child(_ambient)


func _exit_tree() -> void:
	if inst == self:
		inst = null


## Plays a one-shot by key, with optional pitch jitter so repeats don't sound stamped out.
static func play(key: String, volume_db: float = 0.0, jitter: float = 0.0) -> void:
	if inst != null:
		inst._play(key, volume_db, jitter)


## Starts (or crossfades to) a music track: "hub", "battle" or "" for silence.
static func music(track: String) -> void:
	if inst != null:
		inst._set_music(track)


## Battle ambience loop on or off.
static func ambient(on: bool) -> void:
	if inst == null:
		return
	if on and not inst._ambient.playing and inst._ambient.stream != null:
		inst._ambient.play()
	elif not on and inst._ambient.playing:
		inst._ambient.stop()


func _play(key: String, volume_db: float, jitter: float) -> void:
	if not _streams.has(key):
		return
	var now: int = Time.get_ticks_msec()
	if _last_ms.has(key) and now - int(_last_ms[key]) < THROTTLE_MS:
		return
	_last_ms[key] = now
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % SFX_POOL
	p.stop()
	p.stream = _streams[key]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + ((randf() * 2.0 - 1.0) * jitter if jitter > 0.0 else 0.0)
	p.play()


func _set_music(track: String) -> void:
	if track == _track:
		return
	_track = track
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if track == "" or not MUSIC.has(track):
		_fade = create_tween()
		_fade.tween_property(_music, "volume_db", -40.0, FADE_S)
		_fade.tween_callback(_music.stop)
		return
	var s: AudioStream = load(MUSIC[track])
	if s == null:
		return
	if s is AudioStreamMP3:
		s.loop = true
	elif s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		var frame_bytes: int = (2 if s.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if s.stereo else 1)
		s.loop_end = s.data.size() / frame_bytes
	_music.stream = s
	_music.volume_db = -40.0
	_music.play()
	_fade = create_tween()
	_fade.tween_property(_music, "volume_db", MUSIC_DB, FADE_S)
