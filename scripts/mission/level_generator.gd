class_name LevelGenerator
extends RefCounted
## Sinh bản đồ dạng phòng + hành lang trên lưới ô vuông.
## Kết quả thuần dữ liệu (không tạo node) để test được và để mod chỉ cần chỉnh tham số trong data/levels.

const WALL := 0
const FLOOR := 1

var size: Vector2i
var cells: PackedByteArray
## Rect2i theo đơn vị ô. rooms[0] luôn là phòng xuất phát (có lối thoát).
var rooms: Array[Rect2i] = []


static func generate(rng: RandomNumberGenerator, params: Dictionary) -> LevelGenerator:
	var gen := LevelGenerator.new()
	gen._build(rng, params)
	return gen


func is_floor(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return false
	return cells[cell.y * size.x + cell.x] == FLOOR


func room_center(index: int) -> Vector2i:
	return rooms[index].get_center()


func random_cell_in_room(rng: RandomNumberGenerator, index: int, margin: int = 1) -> Vector2i:
	var r := rooms[index].grow(-margin)
	if r.size.x <= 0 or r.size.y <= 0:
		return rooms[index].get_center()
	return Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))


## Khoảng cách đi bộ (BFS, số ô) từ `from` tới mọi ô sàn. -1 = không tới được.
func distances_from(from: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(size.x * size.y)
	dist.fill(-1)
	if not is_floor(from):
		return dist
	var queue: Array[Vector2i] = [from]
	dist[from.y * size.x + from.x] = 0
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if is_floor(n) and dist[n.y * size.x + n.x] == -1:
				dist[n.y * size.x + n.x] = dist[c.y * size.x + c.x] + 1
				queue.append(n)
	return dist


## Chỉ số các phòng (trừ phòng xuất phát) xếp từ xa đến gần.
func rooms_by_distance_desc() -> Array:
	var dist := distances_from(room_center(0))
	var order := range(1, rooms.size())
	order.sort_custom(func(a, b):
		var ca := room_center(a)
		var cb := room_center(b)
		return dist[ca.y * size.x + ca.x] > dist[cb.y * size.x + cb.x])
	return order


func _build(rng: RandomNumberGenerator, params: Dictionary) -> void:
	var grid: Array = params.get("grid", [48, 36])
	size = Vector2i(int(grid[0]), int(grid[1]))
	cells = PackedByteArray()
	cells.resize(size.x * size.y)
	cells.fill(WALL)

	var room_range: Array = params.get("rooms", [6, 9])
	var size_range: Array = params.get("room_size", [5, 10])
	var target := rng.randi_range(int(room_range[0]), int(room_range[1]))
	var attempts := 0
	while rooms.size() < target and attempts < 400:
		attempts += 1
		var w := rng.randi_range(int(size_range[0]), int(size_range[1]))
		var h := rng.randi_range(int(size_range[0]), int(size_range[1]))
		var r := Rect2i(rng.randi_range(1, size.x - w - 2), rng.randi_range(1, size.y - h - 2), w, h)
		if rooms.any(func(o: Rect2i): return o.grow(2).intersects(r)):
			continue
		rooms.append(r)
	if rooms.is_empty():
		rooms.append(Rect2i(1, 1, size.x - 2, size.y - 2))

	for r in rooms:
		_carve_rect(r)
	# Nối các phòng theo thứ tự gần nhau nhất (cây khung) -> luôn liên thông
	var connected: Array[int] = [0]
	var remaining := range(1, rooms.size())
	while not remaining.is_empty():
		var best := [-1, -1, INF]
		for a in connected:
			for b in remaining:
				var d := Vector2(room_center(a)).distance_squared_to(Vector2(room_center(b)))
				if d < best[2]:
					best = [a, b, d]
		_carve_corridor(rng, room_center(best[0]), room_center(best[1]))
		connected.append(best[1])
		remaining.erase(best[1])
	# Thêm một vòng lặp để bản đồ bớt tuyến tính
	if rooms.size() > 3:
		_carve_corridor(rng, room_center(rng.randi_range(1, rooms.size() - 1)), room_center(rng.randi_range(1, rooms.size() - 1)))


func _carve_rect(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x > 0 and y > 0 and x < size.x - 1 and y < size.y - 1:
				cells[y * size.x + x] = FLOOR


## Hành lang chữ L rộng 2 ô.
func _carve_corridor(rng: RandomNumberGenerator, a: Vector2i, b: Vector2i) -> void:
	var corner := Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	for seg in [[a, corner], [corner, b]]:
		var p: Vector2i = seg[0]
		var q: Vector2i = seg[1]
		var r := Rect2i(Vector2i(mini(p.x, q.x), mini(p.y, q.y)), Vector2i(absi(p.x - q.x) + 2, absi(p.y - q.y) + 2))
		_carve_rect(r)
