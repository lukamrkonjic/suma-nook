extends Node
# legacy-disabled class_name TilegardenAudioManager

var events: Dictionary = {}
var rng := RandomNumberGenerator.new()
var ambience_player: AudioStreamPlayer


func setup() -> void:
	rng.seed = 91273
	var file := FileAccess.open("res://data/audio_events.json", FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			events = parsed
	_start_ambience()


func play(event_id: StringName, pitch_variation := 0.035, volume_db := 0.0) -> void:
	var paths: Array = events.get(String(event_id), [])
	if paths.is_empty():
		return
	var path := str(paths[rng.randi_range(0, paths.size() - 1)])
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = _bus_for(event_id)
	player.volume_db = volume_db
	player.pitch_scale = rng.randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _start_ambience() -> void:
	var paths: Array = events.get("ambience", [])
	if paths.is_empty():
		return
	var stream := load(str(paths[0])) as AudioStreamWAV
	if stream == null:
		return
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	ambience_player = AudioStreamPlayer.new()
	ambience_player.name = "ForestAmbience"
	ambience_player.stream = stream
	ambience_player.bus = &"Ambience"
	ambience_player.volume_db = -2.0
	add_child(ambience_player)
	ambience_player.play()


static func _bus_for(event_id: StringName) -> StringName:
	var id := String(event_id)
	if id.begins_with("ui_") or id in ["collection_open"]:
		return &"UI"
	if id.begins_with("mote_"):
		return &"Creatures"
	return &"SFX"

