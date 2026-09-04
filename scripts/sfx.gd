extends Node

var _streams := {}
var _players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sfx_name in ["tick", "coins", "jackpot", "attack", "raid", "shield", "error", "pop", "build", "levelup"]:
		var path := "res://assets/sfx/%s.wav" % sfx_name
		if ResourceLoader.exists(path):
			_streams[sfx_name] = load(path)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

# `pitch` is the note the sample is played at; the jitter rides on top of it,
# so a caller that wants a rising run of the same sound sets the pitch per hit
# and still gets the small variation that stops repeats sounding mechanical.
func play(sfx_name: String, volume_db: float = 0.0, pitch_jitter: float = 0.06,
		pitch: float = 1.0) -> void:
	if not _streams.has(sfx_name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _streams[sfx_name]
			p.volume_db = volume_db
			p.pitch_scale = pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
			p.play()
			return
