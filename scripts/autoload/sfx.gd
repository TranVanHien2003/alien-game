extends Node
## Phát hiệu ứng âm thanh từ assets/audio/<tên>.ogg.
## Dùng một pool AudioStreamPlayer và giới hạn mỗi âm thanh tối đa vài lần/khung để không bị vỡ tiếng.
## Trình duyệt chỉ cho phát âm thanh sau lần tương tác đầu tiên (nút ở màn hình tiêu đề).

const POOL_SIZE := 12
const MIN_INTERVAL := 0.045

var volume_db := -6.0
var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _last_played: Dictionary = {}
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound: String, pitch_jitter: float = 0.08, volume_offset: float = 0.0) -> void:
	if sound == "" or DisplayServer.get_name() == "headless":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound, -1.0)) < MIN_INTERVAL:
		return
	_last_played[sound] = now
	var stream := _stream(sound)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db + volume_offset
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := "res://assets/audio/%s.ogg" % sound
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound]
