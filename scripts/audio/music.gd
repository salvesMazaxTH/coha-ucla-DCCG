extends Node
## Background music for matches (autoload "Music").
##
## The music follows a fixed "roteiro" (script): each track plays a set number of times, then the next one
## starts, and after the last one the roteiro begins again. It runs from the start of a match until the
## player goes back to the main menu. Every match starts at the top of the roteiro.
## It has its own on/off switch and volume (saved next to the sound effects settings) so the music can
## be turned down or off without touching the effects. The main screen only calls play_match(),
## fade_out() and stop(); nothing else needs to know about audio players.
##
## Web note: like Sfx, the first tap unlocks browser audio; a match always starts from a tap.

## The roteiro, in order: which file, and how many times it plays before the next one. The files are
## already at the same loudness (-18.4 LUFS), so changing tracks does not jump in volume.
const ROTEIRO := [
	{"path": "res://assets/music/a_brand_new_wisdom.ogg", "plays": 3},
	{"path": "res://assets/music/winter_dust.ogg", "plays": 2},
	{"path": "res://assets/music/epic_boss_battle.ogg", "plays": 1},
]
const SETTINGS_PATH := "user://settings.cfg"
## Level of the track when the volume slider is at 100%. The default slider position (50%) is about
## 6 dB under this, so the music sits behind the sound effects.
const TRACK_DB := -12.0
const DEFAULT_VOLUME := 0.5
## Under this slider value the music is treated as silent (no player running for nothing).
const SILENT_VOLUME := 0.001

var _player: AudioStreamPlayer
var _enabled := true
var _volume := DEFAULT_VOLUME ## 0.0 to 1.0, on top of TRACK_DB
var _wanted := false ## true between play_match() and stop()/fade_out(): the music should be heard if allowed
var _fade_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.stream = _build_roteiro()
	add_child(_player)
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		_enabled = bool(settings.get_value("audio", "music_on", true))
		_volume = clampf(float(settings.get_value("audio", "music_volume", DEFAULT_VOLUME)), 0.0, 1.0)


func is_enabled() -> bool:
	return _enabled


func get_volume() -> float:
	return _volume


func is_playing() -> bool:
	return _player != null and _player.playing


## Volume from 0.0 (silent) to 1.0 (TRACK_DB), saved in settings. Takes effect on the music already playing.
func set_volume(volume: float) -> void:
	_volume = clampf(volume, 0.0, 1.0)
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("audio", "music_volume", _volume)
	settings.save(SETTINGS_PATH)
	_apply()


func set_enabled(on: bool) -> void:
	_enabled = on
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("audio", "music_on", on)
	settings.save(SETTINGS_PATH)
	_apply()


## Starts the match music. Asked again while it is already playing (an online reconnect), it keeps going
## instead of restarting from the top.
func play_match() -> void:
	_wanted = true
	_apply()


## Stops at once (back to the main menu).
func stop() -> void:
	_wanted = false
	_kill_fade()
	if _player != null:
		_player.stop()


## Lets the music die away over `seconds`, for the Victory/Defeat jingle to be heard on its own.
func fade_out(seconds: float) -> void:
	_wanted = false
	if _player == null or not _player.playing:
		return
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", -60.0, seconds)
	_fade_tween.tween_callback(_player.stop)


## Lays the roteiro out as one playlist stream: a track that plays 3 times is listed 3 times. The playlist
## joins the tracks with no gap between them (a seamless loop stays seamless) and starts over at the end.
func _build_roteiro() -> AudioStreamPlaylist:
	var tracks: Array[AudioStream] = []
	for step in ROTEIRO:
		var track := load(step["path"]) as AudioStreamOggVorbis
		if track == null:
			continue
		track.loop = false # the playlist does the repeating
		for _play in int(step["plays"]):
			tracks.append(track)
	if tracks.is_empty():
		return null
	var playlist := AudioStreamPlaylist.new()
	playlist.stream_count = tracks.size()
	for index in tracks.size():
		playlist.set_list_stream(index, tracks[index])
	playlist.loop = true
	return playlist


func _apply() -> void:
	if _player == null or _player.stream == null:
		return
	if not _wanted or not _enabled or _volume <= SILENT_VOLUME:
		_kill_fade()
		_player.stop()
		return
	_kill_fade()
	_player.volume_db = TRACK_DB + linear_to_db(_volume)
	if not _player.playing:
		_player.play()


func _kill_fade() -> void:
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
