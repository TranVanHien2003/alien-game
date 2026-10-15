class_name ExitZone
extends Area2D
## Điểm rút lui: tàu con thoi. Đèn chuyển xanh khi mục tiêu hoàn thành.

signal player_entered

var unlocked := false:
	set(value):
		unlocked = value
		if is_node_ready():
			_light.color = Color("#B4FF39") if value else Color("#FF8A3D")
var _t := 0.0
var _ship: Sprite2D
var _light: PointLight2D


func _ready() -> void:
	body_entered.connect(func(b): if b is Player: player_entered.emit())
	_ship = Sprite2D.new()
	_ship.texture = preload("res://assets/props/shuttle.png")
	_ship.position = Vector2(0, -96)
	_ship.scale = Vector2.ONE * 0.9
	add_child(_ship)
	_light = PointLight2D.new()
	_light.texture = preload("res://assets/fx/light.png")
	_light.texture_scale = 2.5
	_light.energy = 0.7
	_light.color = Color("#FF8A3D")
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := Color("#B4FF39") if unlocked else Color("#8090A0")
	draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 32, c, 3.0)
	draw_arc(Vector2.ZERO, 26.0 + sin(_t * 3.0) * 3.0, 0.0, TAU, 32, Color(c, 0.5), 1.5)
	draw_string(UI.font(), Vector2(-70, 56), "TÀU CON THOI", HORIZONTAL_ALIGNMENT_CENTER, 140, 13, c)
