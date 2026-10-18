extends Node
## Sound effects for the whole game (autoload "Sfx").
##
## Every sound has a short name ("hit_heavy", "card_draw"...) mapped in SOUNDS to a few Kenney CC0
## files (assets/sfx/, see LICENSE.txt there). When a name has several files, one is picked at random
## each time and the pitch is nudged a little, so repeated hits never sound like a machine gun.
##
## The rest of the game never touches audio players: it calls Sfx.play("name"), Sfx.play_in("name",
## seconds) to line a sound up with an animation, or Sfx.play_event(event, seconds, in_combat) to let
## `sound_for_event` pick the sound that fits an engine event.
##
## Web note: browsers keep audio locked until the first tap or click. Godot unlocks it by itself on
## that first input, so sounds asked for before it are simply silent (nothing to handle here).

const SFX_FOLDER := "res://assets/sfx/"
const SETTINGS_PATH := "user://settings.cfg"
const PLAYER_COUNT := 12
## Same sound asked for twice inside this many milliseconds plays once (an area attack hitting five
## units would otherwise stack five identical sounds into one loud blast).
const SAME_SOUND_MIN_GAP_MS := 45
## Taken off every sound on top of its own level: the whole set a little quieter. The player's volume
## slider (0 to 100%) goes on top of this.
const MASTER_TRIM_DB := -3.0

## name -> files (".ogg" is added unless the name already has an extension, like "damage.wav"), volume in dB, random pitch spread (0.06 = from -6% to +6%),
## and optionally "speed" (1.0 = as recorded, 2.25 = more than twice as fast).
const SOUNDS := {
	# --- cards moving around
	"card_draw":      {"files": ["card-slide-1", "card-slide-2", "card-slide-3", "card-slide-4"], "db": -4.0, "pitch": 0.05},
	"card_place":     {"files": ["card-place-1", "card-place-2", "card-place-3", "card-place-4"], "db": -1.0, "pitch": 0.05},
	"card_shuffle":   {"files": ["card-shuffle"], "db": -3.0, "pitch": 0.0, "speed": 2.25},
	"card_fan":       {"files": ["card-fan-1"], "db": -3.0, "pitch": 0.0},
	"card_discard":   {"files": ["card-shove-1", "card-shove-2"], "db": -3.0, "pitch": 0.05},
	# --- casting
	"spell_cast":     {"files": ["phaserUp1", "phaserUp2", "phaserUp3"], "db": -7.0, "pitch": 0.04},
	"legendary":      {"files": ["impactBell_heavy_000", "impactBell_heavy_001"], "db": -3.0, "pitch": 0.0},
	"trigger":        {"files": ["pluck_001"], "db": -8.0, "pitch": 0.08},
	"relic":          {"files": ["metalLatch"], "db": -3.0, "pitch": 0.0},
	# --- damage and healing
	# combat blows use damage.wav from the old CSA; its peak sits right under 0 dBFS, so it is turned well down
	"hit_light":      {"files": ["damage.wav"], "db": -13.0, "pitch": 0.05},
	"hit_heavy":      {"files": ["damage.wav"], "db": -10.0, "pitch": 0.04},
	"direct_damage":  {"files": ["zap1", "zap2"], "db": -7.0, "pitch": 0.06},
	"shield_break":   {"files": ["impactMetal_light_000", "impactMetal_light_001"], "db": -2.0, "pitch": 0.05},
	"heal":           {"files": ["heal.wav"], "db": -6.0, "pitch": 0.03}, # from the old CSA (peak -5.5 dBFS)
	"buff":           {"files": ["pepSound1", "pepSound2"], "db": -8.0, "pitch": 0.04},
	"poison_tick":    {"files": ["drop_002", "drop_003"], "db": -5.0, "pitch": 0.08},
	"crit":           {"files": ["impactMetal_heavy_000"], "db": -3.0, "pitch": 0.0},
	"reflect":        {"files": ["impactPlate_light_000", "impactPlate_light_001"], "db": -3.0, "pitch": 0.04},
	"dodge":          {"files": ["cloth1", "cloth2"], "db": -3.0, "pitch": 0.06},
	# --- units leaving, coming back, statuses
	"death":          {"files": ["impactSoft_heavy_000", "impactSoft_heavy_001", "impactSoft_heavy_002"], "db": -1.0, "pitch": 0.05},
	"banish":         {"files": ["phaserDown1", "phaserDown2"], "db": -5.0, "pitch": 0.0},
	"sacrifice":      {"files": ["knifeSlice"], "db": -4.0, "pitch": 0.04},
	"revive":         {"files": ["powerUp12"], "db": -6.0, "pitch": 0.0},
	"freeze":         {"files": ["impactGlass_medium_000", "impactGlass_medium_001"], "db": -4.0, "pitch": 0.04},
	"thaw":           {"files": ["glass_003"], "db": -5.0, "pitch": 0.0},
	"execute":        {"files": ["impactBell_heavy_001"], "db": 0.0, "pitch": -0.2},
	"fatigue":        {"files": ["lowDown"], "db": -6.0, "pitch": 0.0},
	"countered":      {"files": ["glitch_001"], "db": -5.0, "pitch": 0.0},
	"fizzle":         {"files": ["back_002"], "db": -5.0, "pitch": 0.0},
	# --- turns and the end of the match
	"turn_start":     {"files": ["confirmation_001"], "db": -4.0, "pitch": 0.0},
	"victory":        {"files": ["jingles_STEEL00"], "db": -2.0, "pitch": 0.0},
	"defeat":         {"files": ["lowThreeTone"], "db": -2.0, "pitch": 0.0},
	# --- interface
	"ui_click":       {"files": ["click_003"], "db": -5.0, "pitch": 0.03},
	"ui_select":      {"files": ["select_006"], "db": -6.0, "pitch": 0.0},
	"ui_toggle":      {"files": ["toggle_001"], "db": -5.0, "pitch": 0.0},
	"ui_error":       {"files": ["error_003"], "db": -6.0, "pitch": 0.0},
}

var _streams := {} ## name -> Array[AudioStream], loaded once
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_played_ms := {} ## name -> Time.get_ticks_msec() of its last play
var _enabled := true
var _volume := 1.0 ## 0.0 to 1.0, on top of each sound's own level


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sound_name in SOUNDS:
		var loaded: Array[AudioStream] = []
		for file_name in SOUNDS[sound_name]["files"]:
			var stream := load(sound_path(file_name)) as AudioStream
			if stream != null:
				loaded.append(stream)
		_streams[sound_name] = loaded
	for i in PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		_enabled = bool(settings.get_value("audio", "sfx_on", true))
		_volume = clampf(float(settings.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)


static func sound_path(file_name: String) -> String:
	return SFX_FOLDER + (file_name if file_name.get_extension() != "" else file_name + ".ogg")


func is_enabled() -> bool:
	return _enabled


func get_volume() -> float:
	return _volume


## Master volume from 0.0 (silent) to 1.0 (as tuned in SOUNDS minus MASTER_TRIM_DB), saved in settings.
func set_volume(volume: float) -> void:
	_volume = clampf(volume, 0.0, 1.0)
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("audio", "sfx_volume", _volume)
	settings.save(SETTINGS_PATH)


func set_enabled(on: bool) -> void:
	_enabled = on
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("audio", "sfx_on", on)
	settings.save(SETTINGS_PATH)
	if not on:
		for player in _players:
			player.stop()


## Plays a sound now. Unknown names and a muted game are silently ignored.
func play(sound_name: String) -> void:
	if not _enabled or _volume <= 0.0 or not _streams.has(sound_name):
		return
	var options: Array = _streams[sound_name]
	if options.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played_ms.get(sound_name, -1000)) < SAME_SOUND_MIN_GAP_MS:
		return
	_last_played_ms[sound_name] = now
	var settings: Dictionary = SOUNDS[sound_name]
	var player := _free_player()
	player.stream = options[randi() % options.size()]
	player.volume_db = float(settings["db"]) + MASTER_TRIM_DB + linear_to_db(_volume)
	var spread := float(settings["pitch"])
	player.pitch_scale = 1.0 + randf_range(-spread, spread) if spread > 0.0 else 1.0 + spread
	# "speed" plays the file faster (or slower) than recorded; the pitch rises with it, which suits noisy sounds
	player.pitch_scale *= float(settings.get("speed", 1.0))
	player.play()


## Plays a sound after `seconds`, to land on the beat of an animation.
func play_in(sound_name: String, seconds: float) -> void:
	if sound_name == "":
		return
	if seconds <= 0.02:
		play(sound_name)
		return
	get_tree().create_timer(seconds).timeout.connect(play.bind(sound_name))


## The sound that fits an engine event, `seconds` from now ("" means the event is silent).
func play_event(event: Dictionary, seconds: float, in_combat: bool) -> void:
	play_in(sound_for_event(event, in_combat), seconds)


## Which sound an engine event makes. `in_combat` is true while a fight is being played out, which
## tells a blow of the fight (a punch) from damage dealt by a card effect (a magic zap).
static func sound_for_event(event: Dictionary, in_combat: bool) -> String:
	match String(event.get("type", "")):
		"play":
			if event.get("legendary", false):
				return "legendary"
			var card_type := String(CardDB.card(String(event.get("card_id", ""))).get("type", ""))
			if card_type == "unit":
				return "card_place"
			if card_type == "artifact":
				return "relic"
			return "spell_cast"
		"summon", "deck_summon", "hand_summon":
			return "card_place"
		"relic_enter":
			return "relic"
		"revive":
			return "revive"
		"draw", "search_take", "return_to_hand", "tide_draw":
			return "card_draw"
		"mulligan":
			return "card_fan"
		"discard", "mill":
			return "card_discard"
		# Leader powers have no sound: the one tried was grating. Passives (like Voltexz's Sobrecarga) fire
		# by themselves at the start of every turn, so they would only add noise on top of the turn-start sound.
		"ability", "passive":
			return ""
		"trigger":
			return "trigger"
		"damage":
			if int(event.get("amount", 0)) <= 0:
				return ""
			if in_combat and int(event.get("src", 0)) > 0:
				return "hit_heavy" if int(event["amount"]) >= 6 else "hit_light"
			return "direct_damage"
		"shield_break", "spell_shield_break":
			return "shield_break"
		"heal":
			return "heal"
		"buff":
			return "buff" if int(event.get("atk", 0)) > 0 or int(event.get("hp", 0)) > 0 or not event.get("keywords", []).is_empty() else ""
		"dot":
			return "poison_tick"
		"death":
			return "death"
		"banish":
			return "banish"
		"sacrifice":
			return "sacrifice"
		"freeze", "exhaust":
			return "freeze"
		"thaw":
			return "thaw"
		"crit":
			return "crit"
		"reflect":
			return "reflect"
		"dodge":
			return "dodge"
		"leader_executed":
			return "execute"
		"fatigue":
			return "fatigue"
		"countered":
			return "countered"
		"fizzle":
			return "fizzle"
		"start_turn":
			return "turn_start"
	return ""


func _free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	# every player busy: take over the one that has been going the longest (round robin)
	var taken := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	return taken
