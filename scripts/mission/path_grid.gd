class_name PathGrid
extends RefCounted
## Tìm đường A* trên lưới ô của bản đồ (dùng chung cho thành viên và quái).
##   - Đường đi qua TÂM ô (cách tường >= nửa ô) và không cắt góc chéo -> thân nhân vật không quệt góc tường.
##   - Ô sát tường có chi phí cao hơn -> ưu tiên đi giữa hành lang.
##   - Mỏ tài nguyên (vật cản) làm ô đó đắt hơn -> đi vòng.
##   - Đường được làm mượt bằng kiểm tra "đi thẳng được" có tính bán kính thân.

const WALL_WEIGHT := 3.0
const OBSTACLE_WEIGHT := 8.0
const CLEARANCE := 20.0

var astar := AStarGrid2D.new()
var gen: LevelGenerator
var cell := 64.0


func setup(generator: LevelGenerator, cell_size: float) -> void:
	gen = generator
	cell = cell_size
	astar.region = Rect2i(Vector2i.ZERO, gen.size)
	astar.cell_size = Vector2(cell, cell)
	astar.offset = Vector2(cell, cell) / 2.0
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in gen.size.y:
		for x in gen.size.x:
			var c := Vector2i(x, y)
			if not gen.is_floor(c):
				astar.set_point_solid(c, true)
			elif _near_wall(c):
				astar.set_point_weight_scale(c, WALL_WEIGHT)


func _near_wall(c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not gen.is_floor(c + Vector2i(dx, dy)):
				return true
	return false


func to_cell(world: Vector2) -> Vector2i:
	return Vector2i((world / cell).floor())


func walkable(c: Vector2i) -> bool:
	return astar.is_in_boundsv(c) and not astar.is_point_solid(c)


## Ô đi được gần nhất (khi đích nằm trong tường / vật cản).
func nearest_walkable(c: Vector2i, radius: int = 4) -> Vector2i:
	if walkable(c):
		return c
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r or absi(dy) == r:
					var n := c + Vector2i(dx, dy)
					if walkable(n):
						return n
	return c


## Đánh dấu / bỏ đánh dấu vật cản (mỏ tài nguyên) để đường đi tránh ra.
func set_obstacle(world: Vector2, on: bool) -> void:
	var c := to_cell(world)
	if walkable(c):
		astar.set_point_weight_scale(c, OBSTACLE_WEIGHT if on else (WALL_WEIGHT if _near_wall(c) else 1.0))


## Đường đi (toạ độ thế giới) từ from tới to, đã làm mượt. Điểm cuối là chính `to` nếu đi tới được.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := nearest_walkable(to_cell(from))
	var b := nearest_walkable(to_cell(to))
	if not walkable(a) or not walkable(b):
		return PackedVector2Array([to])
	var raw := astar.get_point_path(a, b, true)
	if raw.is_empty():
		return PackedVector2Array([to])
	if walkable(to_cell(to)) and has_clearance(raw[raw.size() - 1], to):
		raw[raw.size() - 1] = to
	return _smooth(from, raw)


## Kéo căng đường: bỏ các điểm trung gian khi có thể đi thẳng (giữ khoảng cách CLEARANCE với tường).
func _smooth(from: Vector2, path: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	var anchor := from
	var i := 0
	while i < path.size():
		var far := i
		for j in range(path.size() - 1, i, -1):
			if has_clearance(anchor, path[j]):
				far = j
				break
		result.append(path[far])
		anchor = path[far]
		i = far + 1
	return result


## Đoạn thẳng a->b có đi được với thân rộng CLEARANCE không (lấy mẫu dọc đoạn + hai bên).
func has_clearance(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var length := d.length()
	if length < 1.0:
		return walkable(to_cell(a))
	var dir := d / length
	var side := dir.orthogonal() * CLEARANCE
	var steps := int(ceil(length / (cell * 0.25)))
	for s in steps + 1:
		var p := a + d * (float(s) / steps)
		for offset in [Vector2.ZERO, side, -side]:
			if not walkable(to_cell(p + offset)):
				return false
	return true
