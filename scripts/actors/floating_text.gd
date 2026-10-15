class_name FloatingText
extends Node2D
## Số sát thương / thông báo bay lên rồi biến mất.

var text := ""
var color := Color.WHITE
var size := 16
var _t := 0.0


static func create(pos: Vector2, t: String, c: Color, font_size: int = 16) -> FloatingText:
	var f := FloatingText.new()
	f.position = pos + Vector2(randf_range(-8, 8), -10)
	f.text = t
	f.color = c
	f.size = font_size
	f.z_index = 10
	f.material = Projectile.glow_material()
	return f


func _process(delta: float) -> void:
	_t += delta
	position.y -= 40.0 * delta
	if _t > 0.8:
		queue_free()
	queue_redraw()


func _draw() -> void:
	draw_string(UI.font(), Vector2(-30, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 60, size, Color(color, 1.0 - _t / 0.8))
