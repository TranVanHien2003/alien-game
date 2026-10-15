class_name ResourceNode
extends StaticBody2D
## Mỏ tài nguyên / thùng hàng: bắn (hoặc dùng máy cắt plasma) để khai thác, vỡ ra rơi nguyên liệu.

signal depleted(node: ResourceNode)

var node_id := ""
var data: Dictionary = {}
var max_hp := 40.0
var hp := 40.0
var _color := Color.WHITE
var _flash := 0.0
var _shape_points := PackedVector2Array()


func setup(id: String) -> void:
	node_id = id
	data = Content.get_entry("resource_nodes", id)
	max_hp = float(data.get("hp", 40))
	hp = max_hp
	_color = Color(data.get("color", "#C9D3E0"))
	for i in 7:
		_shape_points.append(Vector2.from_angle(TAU * i / 7.0) * randf_range(13.0, 19.0))


func mine(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash = 0.06
	queue_redraw()
	if hp <= 0.0:
		depleted.emit(self)
		queue_free()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()


func _draw() -> void:
	var c := Color.WHITE if _flash > 0.0 else _color
	draw_colored_polygon(_shape_points, Color(c, 0.35))
	var outline := _shape_points.duplicate()
	outline.append(outline[0])
	draw_polyline(outline, c, 2.0)
	if hp < max_hp:
		draw_rect(Rect2(-16, -26, 32 * hp / max_hp, 3), c)
