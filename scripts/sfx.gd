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

func play(sfx_name: String, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	if not _streams.has(sfx_name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _streams[sfx_name]
			p.volume_db = volume_db
			p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
			p.play()
			return
