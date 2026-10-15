class_name Explosion
extends Node2D
## Hiệu ứng nổ đơn giản (vòng tròn lan rộng rồi mờ dần).

var radius := 100.0
var color := Color.WHITE
var _t := 0.0


static func create(pos: Vector2, r: float, c: Color) -> Explosion:
	var e := Explosion.new()
	e.position = pos
	e.radius = r
	e.color = c
	return e


func _process(delta: float) -> void:
	_t += delta * 3.0
	if _t >= 1.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius * _t, Color(color, 0.25 * (1.0 - _t)))
	draw_arc(Vector2.ZERO, radius * _t, 0.0, TAU, 32, Color(color, 1.0 - _t), 3.0)
