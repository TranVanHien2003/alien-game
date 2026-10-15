class_name ExitZone
extends Area2D
## Điểm rút lui về tàu con thoi. Chỉ mở khi hoàn thành mục tiêu (hoặc khi người chơi chọn bỏ cuộc).

signal player_entered

var unlocked := false
var _t := 0.0


func _ready() -> void:
	body_entered.connect(func(b): if b is Player: player_entered.emit())


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := Color("#B4FF39") if unlocked else Color("#5C6B80")
	draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 32, c, 3.0)
	draw_arc(Vector2.ZERO, 26.0 + sin(_t * 3.0) * 3.0, 0.0, TAU, 32, Color(c, 0.5), 1.5)
	draw_string(UI.font(), Vector2(-70, 56), "TÀU CON THOI", HORIZONTAL_ALIGNMENT_CENTER, 140, 13, c)
