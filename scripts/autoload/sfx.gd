extends Node
## Tiny procedural sound effects (no audio assets needed).

var _streams := {}
var _players: Array = []
var _idx := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams = {
		"bite": _blip(200.0, 0.10, 0.85, -0.3),
		"eat": _blip(420.0, 0.16, 0.12, 0.8),
		"hurt": _blip(130.0, 0.28, 0.45, -0.5),
		"levelup": _blip(600.0, 0.40, 0.0, 1.2),
		"splash": _blip(300.0, 0.35, 0.95, -0.5),
		"ui": _blip(660.0, 0.05, 0.0, 0.2),
		"frenzy": _blip(260.0, 0.55, 0.1, 2.0),
	}
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound: String, pitch: float = 1.0) -> void:
	if not _streams.has(sound):
		return
	var p: AudioStreamPlayer = _players[_idx]
	_idx = (_idx + 1) % _players.size()
	p.stream = _streams[sound]
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.volume_db = -8.0
	p.play()


func _blip(freq: float, dur: float, noise: float, sweep: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var ph := 0.0
	for i in n:
		var k := float(i) / float(n)
		var env := pow(1.0 - k, 2.0)
		ph += TAU * freq * (1.0 + sweep * k) / float(rate)
		var s := sin(ph) * (1.0 - noise) + (randf() * 2.0 - 1.0) * noise
		bytes.encode_s16(i * 2, int(clampf(s * env, -1.0, 1.0) * 12000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	return w
