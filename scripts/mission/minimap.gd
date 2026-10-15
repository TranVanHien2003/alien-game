class_name Minimap
extends Control
## Bản đồ nhỏ: địa hình (vẽ sẵn thành texture), đội, quái/mỏ trong tầm nhìn của đội
## (hoặc toàn bộ khi kỹ năng Quét đang hoạt động), mục tiêu, tàu con thoi và khung camera.
## Bấm / kéo trên minimap để di chuyển camera.

var level: Node
var _texture: ImageTexture
var _scale := 1.0
var _dragging := false


func setup(lvl: Node) -> void:
	level = lvl
	var gen: LevelGenerator = lvl.gen
	var img := Image.create(gen.size.x, gen.size.y, false, Image.FORMAT_RGBA8)
	var floor_color := Color(lvl.map.accent, 0.35).blend(Color(0.12, 0.14, 0.2, 0.9))
	for y in gen.size.y:
		for x in gen.size.x:
			img.set_pixel(x, y, floor_color if gen.is_floor(Vector2i(x, y)) else Color(0, 0, 0, 0.55))
	_texture = ImageTexture.create_from_image(img)
	_scale = minf(size.x / gen.size.x, size.y / gen.size.y)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_move_camera(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_move_camera(event.position)
		accept_event()


func _move_camera(local: Vector2) -> void:
	level.camera.global_position = local / _scale * level.map.cell_size


func _process(_delta: float) -> void:
	queue_redraw()


func _to_map(world: Vector2) -> Vector2:
	return world / level.map.cell_size * _scale


func _draw() -> void:
	if level == null or _texture == null:
		return
	var gen: LevelGenerator = level.gen
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, Vector2(gen.size) * _scale), false)
	var revealed: bool = level.is_revealed()
	var squad: Array = level.units.filter(func(u): return u.is_active())
	var seen := func(pos: Vector2) -> bool:
		if revealed:
			return true
		for u in squad:
			if u.global_position.distance_to(pos) <= float(u.stats.sight_radius):
				return true
		return false
	for node in get_tree().get_nodes_in_group("minable"):
		if seen.call(node.global_position):
			draw_circle(_to_map(node.global_position), 1.6, Color("#FFC94D"))
	for obj in get_tree().get_nodes_in_group("interactables"):
		if not obj.done:
			draw_circle(_to_map(obj.global_position), 2.5, Color("#00E5FF") if obj.kind != "cache" else Color("#FFE0A0"))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if seen.call(enemy.global_position):
			draw_circle(_to_map(enemy.global_position), 3.5 if enemy.is_boss else 2.0, Color("#FF5A5A"))
	draw_arc(_to_map(level.exit_zone.global_position), 4.0, 0.0, TAU, 12, Color("#B4FF39"), 1.5)
	for u in level.units:
		if u.state == Unit.State.ACTIVE or u.state == Unit.State.DOWNED:
			draw_circle(_to_map(u.global_position), 2.6, Color("#7CFFB2") if u.is_active() else Color("#FF2BD6"))
	# Khung camera
	var view: Vector2 = level.get_viewport_rect().size / level.camera.zoom
	draw_rect(Rect2(_to_map(level.camera.global_position - view / 2.0), view / level.map.cell_size * _scale), Color(1, 1, 1, 0.7), false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(level.map.accent, 0.6), false, 1.0)
