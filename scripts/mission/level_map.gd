class_name LevelMap
extends Node2D
## Vẽ bản đồ từ LevelGenerator và tạo va chạm tường (gộp các ô tường liền nhau theo hàng).

var gen: LevelGenerator
var cell_size := 40.0
var floor_color := Color("#141A2A")
var wall_color := Color("#2B3A5C")
var accent := Color("#00E5FF")


func build(generator: LevelGenerator, params: Dictionary, cell: float) -> void:
	gen = generator
	cell_size = cell
	floor_color = Color(params.get("floor_color", "#141A2A"))
	wall_color = Color(params.get("wall_color", "#2B3A5C"))
	accent = Color(params.get("accent", "#00E5FF"))
	z_index = -2

	var body := StaticBody2D.new()
	body.add_to_group("walls")
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for y in gen.size.y:
		var x := 0
		while x < gen.size.x:
			if gen.is_floor(Vector2i(x, y)):
				x += 1
				continue
			var start := x
			while x < gen.size.x and not gen.is_floor(Vector2i(x, y)):
				x += 1
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2((x - start) * cell_size, cell_size)
			shape.shape = rect
			shape.position = Vector2((start + x) * 0.5 * cell_size, (y + 0.5) * cell_size)
			body.add_child(shape)
	queue_redraw()


func cell_to_world(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size


func _draw() -> void:
	if gen == null:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(gen.size) * cell_size), Color(0.02, 0.025, 0.05))
	for y in gen.size.y:
		for x in gen.size.x:
			var c := Vector2i(x, y)
			var r := Rect2(Vector2(c) * cell_size, Vector2(cell_size, cell_size))
			if gen.is_floor(c):
				draw_rect(r, floor_color)
				draw_rect(r, Color(accent, 0.035), false, 1.0)
			elif _touches_floor(c):
				draw_rect(r, wall_color)
				draw_rect(r.grow(-3), Color(accent, 0.25), false, 1.0)


func _touches_floor(c: Vector2i) -> bool:
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		if gen.is_floor(c + d):
			return true
	return false
