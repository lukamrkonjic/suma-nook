class_name GameAudio
extends Node
## Named-event audio API: play("chop_impact") picks a variant, adds subtle
## pitch/volume variation, and routes to the right bus. Gameplay scripts never
## touch AudioStreamPlayer nodes or NodePaths — they emit event names.

signal event_played(event_name: String)

const DIR := "res://audio/generated/"
const POOL_SIZE := 10

## event -> {files, bus, volume_db, pitch_var}. Events with numbered files
## ("chop_impact_0..2") are declared by prefix.
const EVENTS := {
	"ui_hover": {"bus": "UI"}, "ui_confirm": {"bus": "UI"}, "ui_cancel": {"bus": "UI"},
	"panel_open": {"bus": "UI"}, "panel_close": {"bus": "UI"}, "craft": {"bus": "UI"},
	"discovery": {"bus": "UI", "volume_db": 1.0},
	"footstep_grass": {"variants": 3, "bus": "SFX", "volume_db": -9.0, "pitch_var": 0.12},
	"footstep_stone": {"variants": 3, "bus": "SFX", "volume_db": -9.0, "pitch_var": 0.12},
	"tool_equip": {"bus": "SFX"}, "hurt": {"bus": "SFX"}, "dodge": {"bus": "SFX"},
	"levelup": {"bus": "UI", "volume_db": 2.0},
	"fish_cast": {"bus": "SFX"}, "fish_splash": {"bus": "SFX"}, "fish_bite": {"bus": "SFX", "volume_db": 2.0},
	"fish_catch": {"bus": "SFX"}, "reward_common": {"bus": "UI"}, "reward_rare": {"bus": "UI", "volume_db": 2.0},
	"chop_windup": {"bus": "SFX", "volume_db": -4.0}, "chop_impact": {"variants": 3, "bus": "SFX", "pitch_var": 0.1},
	"leaf_rustle": {"bus": "SFX", "volume_db": -4.0}, "pickup": {"bus": "SFX"}, "grove_rest": {"bus": "SFX"},
	"build_preview": {"bus": "UI", "volume_db": -6.0}, "build_rotate": {"bus": "UI", "volume_db": -3.0},
	"place_grass": {"bus": "SFX"}, "place_stone": {"bus": "SFX"}, "place_wood": {"bus": "SFX"},
	"place_water": {"bus": "SFX"}, "build_invalid": {"bus": "UI", "volume_db": -3.0},
	"undo": {"bus": "UI"}, "redo": {"bus": "UI"}, "store": {"bus": "UI"},
	"parcel_appear": {"bus": "UI"}, "parcel_open": {"bus": "UI"}, "parcel_reveal": {"bus": "UI"},
	"parcel_select": {"bus": "UI"}, "reroll": {"bus": "UI"},
	"attack_swing": {"bus": "SFX"}, "enemy_telegraph": {"bus": "Creatures"},
	"enemy_hit": {"bus": "Creatures"}, "enemy_defeat": {"bus": "Creatures"},
	"guardian_defeat": {"bus": "Creatures", "volume_db": 2.0},
	"landmark_reclaimed": {"bus": "UI", "volume_db": 2.0},
	"bird": {"variants": 2, "files": ["bird_1", "bird_2"], "bus": "Ambience", "pitch_var": 0.15},
	"water_lap": {"bus": "Ambience"}, "fire_crackle": {"bus": "Ambience", "pitch_var": 0.2},
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _wind: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _bird_timer: Timer


func _ready() -> void:
	add_to_group("audio_bridge")
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_wind = _make_loop("ambience_wind")
	_rain = _make_loop("ambience_rain")
	# The headless acceptance runner has no audible output and Godot's dummy
	# audio driver otherwise retains a looping WAV playback through shutdown.
	if DisplayServer.get_name() != "headless":
		_wind.play()
	_bird_timer = Timer.new()
	_bird_timer.wait_time = 7.0
	_bird_timer.autostart = true
	_bird_timer.timeout.connect(_on_bird_timer)
	add_child(_bird_timer)


func _exit_tree() -> void:
	# Explicitly release active playback objects before a session is rebuilt or
	# the scene tree shuts down. Leaving the looping wind attached until final
	# engine teardown keeps its stream and playback resource alive.
	for player: AudioStreamPlayer in _players:
		player.stop()
		player.stream = null
	if _wind != null:
		_wind.stop()
		_wind.stream = null
	if _rain != null:
		_rain.stop()
		_rain.stream = null
	_streams.clear()


func _make_loop(event: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var stream := _load_stream(event)
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	player.stream = stream
	player.bus = "Ambience"
	player.volume_db = -6.0
	add_child(player)
	return player


func set_rain(enabled: bool) -> void:
	if enabled and not _rain.playing:
		_rain.play()
	elif not enabled and _rain.playing:
		_rain.stop()
	_bird_timer.paused = enabled


func _on_bird_timer() -> void:
	_bird_timer.wait_time = randf_range(5.0, 12.0)
	play_event("bird")


func play_event(
	event: String,
	volume_offset_db := 0.0,
	pitch_multiplier := 1.0
) -> void:
	var config: Dictionary = EVENTS.get(event, {})
	var file := event
	if config.has("variants"):
		if config.has("files"):
			file = config["files"][randi() % int(config["variants"])]
		else:
			file = "%s_%d" % [event, randi() % int(config["variants"])]
	var stream := _load_stream(file)
	if stream == null:
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	player.stream = stream
	player.bus = config.get("bus", "SFX")
	player.volume_db = (
		float(config.get("volume_db", 0.0))
		+ volume_offset_db
	)
	var pitch_var := float(config.get("pitch_var", 0.05))
	player.pitch_scale = pitch_multiplier * (
		1.0 + randf_range(-pitch_var, pitch_var)
	)
	player.play()
	event_played.emit(event)


func _load_stream(file: String) -> AudioStream:
	if _streams.has(file):
		return _streams[file]
	var path := DIR + file + ".wav"
	var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if stream == null:
		push_warning("GameAudio: missing stream " + path)
	_streams[file] = stream
	return stream
