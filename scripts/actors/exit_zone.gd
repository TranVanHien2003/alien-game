class_name ExitZone
extends Area2D
## Tàu con thoi: điểm đổ bộ và rút lui. Đèn chuyển xanh khi mục tiêu hoàn thành.

var unlocked := false:
	set(value):
		unlocked = value
		if is_node_ready():
			_light.color = Color("#B4FF39") if value else Color("#FF8A3D")
var _t := 0.0
var _ship: Sprite2D
var _light: PointLight2D
var radius := 120.0


func _ready() -> void:
	radius = float(Content.config.get("squad", {}).get("evac_radius", 120))
	var shape := CircleShape2D.new()
	shape.radius = radius
	$CollisionShape2D.shape = shape
	_ship = Sprite2D.new()
	_ship.texture = preload("res://assets/props/shuttle.png")
	_ship.scale = Vector2.ONE * 1.1
	add_child(_ship)
	_light = PointLight2D.new()
	_light.texture = preload("res://assets/fx/light.png")
	_light.texture_scale = 2.0
	_light.energy = 0.4
	_light.color = Color("#FF8A3D")
	add_child(_light)


func units_inside() -> Array:
	return get_overlapping_bodies().filter(func(b): return b is Unit and b.is_active())


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := Color("#B4FF39") if unlocked else Color("#8090A0")
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(c, 0.6), 2.0)
	draw_arc(Vector2.ZERO, radius - 8.0 + sin(_t * 3.0) * 3.0, 0.0, TAU, 64, Color(c, 0.25), 1.5)
	draw_string(UI.font(), Vector2(-70, radius + 18), "TÀU CON THOI", HORIZONTAL_ALIGNMENT_CENTER, 140, 13, c)
