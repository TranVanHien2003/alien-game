class_name TerrainGenerator
extends LevelGenerator
## Địa hình mở ngoài trời (sao chổi, mặt trăng, bãi mảnh vỡ...): đồi, vách đá, rừng, suối/khe băng,
## đường mòn nối các "điểm khám phá". Dùng chung giao diện với LevelGenerator:
##   rooms[] = các điểm khám phá (rooms[0] = bãi đáp tàu con thoi), is_floor() = đi được.
## terrain[] lưu loại ô để vẽ (TerrainView) và tô minimap.

enum Type { GROUND, ROUGH, FOREST, PATH, WATER, CLIFF }

var terrain: PackedByteArray
## Độ cao 0..1 theo ô — dùng để đổ bóng đồi khi vẽ
var height: PackedFloat32Array


static func generate(rng: RandomNumberGenerator, params: Dictionary) -> LevelGenerator:
	var gen := TerrainGenerator.new()
	gen._build(rng, params)
	return gen


func type_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return Type.CLIFF
	return terrain[cell.y * size.x + cell.x]


func _build(rng: RandomNumberGenerator, params: Dictionary) -> void:
	var grid: Array = params.get("grid", [140, 100])
	size = Vector2i(int(grid[0]), int(grid[1]))
	var n := size.x * size.y
	cells = PackedByteArray()
	cells.resize(n)
	terrain = PackedByteArray()
	terrain.resize(n)
	height = PackedFloat32Array()
	height.resize(n)

	var t: Dictionary = params.get("terrain", {})
	var h_noise := _noise(rng, float(t.get("height_freq", 0.035)), 4)
	var m_noise := _noise(rng, float(t.get("moisture_freq", 0.05)), 3)
	var r_noise := _noise(rng, float(t.get("river_freq", 0.018)), 2)
	var cliff_level := float(t.get("cliff", 0.62))
	var forest_level := float(t.get("forest", 0.2))
	var river_width := float(t.get("river", 0.03))

	for y in size.y:
		for x in size.x:
			var i := y * size.x + x
			var h := (h_noise.get_noise_2d(x, y) + 1.0) * 0.5
			# Viền bản đồ nâng cao thành vách đá tự nhiên
			var edge := minf(minf(x, size.x - 1 - x), minf(y, size.y - 1 - y))
			h = maxf(h, 1.0 - edge / 4.0)
			height[i] = h
			var m := m_noise.get_noise_2d(x, y)
			var type := Type.GROUND
			if h > cliff_level:
				type = Type.CLIFF
			elif absf(r_noise.get_noise_2d(x, y)) < river_width and h < cliff_level - 0.12:
				type = Type.WATER
			elif m > forest_level:
				type = Type.FOREST
			elif m < -0.32:
				type = Type.ROUGH
			terrain[i] = type

	_place_sites(rng, params)
	for r in rooms:
		_clear_rect(r, Type.GROUND)
	# Đường mòn nối các điểm theo cây khung nhỏ nhất -> luôn đi được tới mọi điểm
	var connected: Array[int] = [0]
	var remaining := range(1, rooms.size())
	while not remaining.is_empty():
		var best := [-1, -1, INF]
		for a in connected:
			for b in remaining:
				var d := Vector2(room_center(a)).distance_squared_to(Vector2(room_center(b)))
				if d < best[2]:
					best = [a, b, d]
		_carve_path(room_center(best[0]), room_center(best[1]))
		connected.append(best[1])
		remaining.erase(best[1])
	# Thêm vài đường vòng
	for i in mini(3, rooms.size() / 3):
		_carve_path(room_center(rng.randi_range(1, rooms.size() - 1)), room_center(rng.randi_range(1, rooms.size() - 1)))

	for i in n:
		cells[i] = FLOOR if terrain[i] != Type.WATER and terrain[i] != Type.CLIFF else WALL


func _noise(rng: RandomNumberGenerator, freq: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = freq
	noise.fractal_octaves = octaves
	return noise


## Rải điểm khám phá cách đều nhau (lấy mẫu kiểu Poisson), điểm 0 = bãi đáp ở gần một mép bản đồ.
func _place_sites(rng: RandomNumberGenerator, params: Dictionary) -> void:
	var count_range: Array = params.get("rooms", [10, 14])
	var target := rng.randi_range(int(count_range[0]), int(count_range[1]))
	var site_size: Array = params.get("room_size", [7, 11])
	var min_dist := sqrt(float(size.x * size.y) / float(target)) * 0.75
	var points: Array[Vector2i] = [Vector2i(rng.randi_range(10, 18), rng.randi_range(size.y / 3, size.y * 2 / 3))]
	var attempts := 0
	while points.size() < target and attempts < 3000:
		attempts += 1
		var p := Vector2i(rng.randi_range(8, size.x - 9), rng.randi_range(8, size.y - 9))
		if points.any(func(q: Vector2i): return Vector2(q).distance_to(Vector2(p)) < min_dist):
			continue
		points.append(p)
	rooms = []
	for p in points:
		var w := rng.randi_range(int(site_size[0]), int(site_size[1]))
		var h := rng.randi_range(int(site_size[0]), int(site_size[1]))
		rooms.append(Rect2i(p - Vector2i(w, h) / 2, Vector2i(w, h)).intersection(Rect2i(Vector2i(3, 3), size - Vector2i(6, 6))))


func _clear_rect(r: Rect2i, type: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := y * size.x + x
			if terrain[i] == Type.CLIFF or terrain[i] == Type.WATER or type == Type.PATH:
				terrain[i] = type
			height[i] = minf(height[i], 0.55)


## Đường mòn rộng 2 ô, đi hơi uốn lượn; băng qua nước/vách đá = cầu / lối mở.
func _carve_path(a: Vector2i, b: Vector2i) -> void:
	var steps := int(Vector2(a).distance_to(Vector2(b)))
	for s in steps + 1:
		var t := float(s) / maxf(1.0, float(steps))
		var p := Vector2(a).lerp(Vector2(b), t) + Vector2(sin(t * 6.0), cos(t * 5.0)) * 3.0 * sin(t * PI)
		var c := Vector2i(p.round())
		for dy in range(0, 2):
			for dx in range(0, 2):
				var q := c + Vector2i(dx, dy)
				if q.x > 1 and q.y > 1 and q.x < size.x - 2 and q.y < size.y - 2:
					var i := q.y * size.x + q.x
					terrain[i] = Type.PATH
					height[i] = minf(height[i], 0.55)
