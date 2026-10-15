class_name LevelMap
extends Node2D
## Dựng bản đồ từ LevelGenerator lên TileMapLayer (assets/tiles/world_tileset.tres).
##   Floor: lớp sàn (có lưới tìm đường cho quái)
##   Walls: lớp tường autotile (va chạm + bóng đổ), y-sort cùng nhân vật để có hiệu ứng che khuất 2.5D
## Biome (tileset), ánh sáng môi trường, đèn và đồ trang trí lấy từ data/levels.

const TILESET_PATH := "res://assets/tiles/world_tileset.tres"
const BIOMES := ["ship", "derelict", "debris", "comet", "moon"]
const FLOOR_VARIANTS := 4
const COLUMNS := 8

# Bit lân cận (phải khớp tools/import_assets.py): 1 = ô đó là tường
const N := 1
const E := 2
const S := 4
const W := 8
const NE := 16
const SE := 32
const SW := 64
const NW := 128

static var _mask_to_index: Dictionary = {}

var gen: LevelGenerator
var cell_size := 64.0
var accent := Color("#00E5FF")
var floor_layer: TileMapLayer
var wall_layer: TileMapLayer
## true = bản đồ ngoài trời (TerrainGenerator): vẽ bằng shader, ánh sáng ban ngày
var outdoor := false


## parent_ysort: node y-sort chứa nhân vật — lớp tường và đồ trang trí được thêm vào đó.
func build(generator: LevelGenerator, params: Dictionary, rng: RandomNumberGenerator, parent_ysort: Node2D) -> void:
	gen = generator
	var tileset: TileSet = load(TILESET_PATH)
	cell_size = float(tileset.tile_size.x)
	accent = Color(params.get("accent", "#00E5FF"))
	var source := maxi(0, BIOMES.find(params.get("tileset", "ship")))

	floor_layer = TileMapLayer.new()
	floor_layer.name = "Floor"
	floor_layer.tile_set = tileset
	floor_layer.z_index = -10
	add_child(floor_layer)

	wall_layer = TileMapLayer.new()
	wall_layer.name = "Walls"
	wall_layer.tile_set = tileset
	wall_layer.y_sort_enabled = true
	parent_ysort.add_child(wall_layer)

	for y in gen.size.y:
		for x in gen.size.x:
			var c := Vector2i(x, y)
			if gen.is_floor(c):
				floor_layer.set_cell(c, source, Vector2i(rng.randi() % FLOOR_VARIANTS, 0))
			elif _near_floor(c):
				wall_layer.set_cell(c, source, _wall_coords(_wall_mask(c)))

	var ambient := CanvasModulate.new()
	ambient.color = Color(params.get("ambient", "#A0A8B8"))
	add_child(ambient)
	if gen is TerrainGenerator:
		outdoor = true
		# Tile chỉ dùng cho va chạm + tìm đường; hình ảnh do shader địa hình vẽ
		floor_layer.visible = false
		wall_layer.visible = false
		_build_terrain(gen, params, rng, parent_ysort)
		return
	_add_decor(params, rng, parent_ysort)
	_add_lamps(params, rng)


func cell_to_world(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size


func world_size() -> Vector2:
	return Vector2(gen.size) * cell_size


# --- Autotile ------------------------------------------------------------------------

func _is_wall(c: Vector2i) -> bool:
	return not gen.is_floor(c)


func _near_floor(c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if gen.is_floor(c + Vector2i(dx, dy)):
				return true
	return false


func _wall_mask(c: Vector2i) -> int:
	var m := 0
	if _is_wall(c + Vector2i.UP): m |= N
	if _is_wall(c + Vector2i.RIGHT): m |= E
	if _is_wall(c + Vector2i.DOWN): m |= S
	if _is_wall(c + Vector2i.LEFT): m |= W
	if _is_wall(c + Vector2i(1, -1)): m |= NE
	if _is_wall(c + Vector2i(1, 1)): m |= SE
	if _is_wall(c + Vector2i(-1, 1)): m |= SW
	if _is_wall(c + Vector2i(-1, -1)): m |= NW
	return m


static func canonical(mask: int) -> int:
	for corner in [[NE, N, E], [SE, S, E], [SW, S, W], [NW, N, W]]:
		if mask & corner[0] and not (mask & corner[1] and mask & corner[2]):
			mask &= ~corner[0]
	return mask


static func _wall_coords(mask: int) -> Vector2i:
	if _mask_to_index.is_empty():
		var masks := {}
		for m in 256:
			masks[canonical(m)] = true
		var sorted := masks.keys()
		sorted.sort()
		for i in sorted.size():
			_mask_to_index[sorted[i]] = i
	var index: int = _mask_to_index[canonical(mask)]
	return Vector2i(index % COLUMNS, 1 + index / COLUMNS)


# --- Trang trí & ánh sáng -----------------------------------------------------------------

func _add_decor(params: Dictionary, rng: RandomNumberGenerator, parent: Node2D) -> void:
	var decor: Dictionary = params.get("decor", {})
	for prop in decor:
		var texture: Texture2D = load("res://assets/props/%s.png" % prop)
		for i in int(decor[prop]):
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.position = cell_to_world(gen.random_cell_in_room(rng, rng.randi_range(0, gen.rooms.size() - 1), 0)) \
				+ Vector2(rng.randf_range(-16, 16), rng.randf_range(-16, 16))
			sprite.rotation = rng.randf() * TAU if prop.contains("meteor") or prop.contains("debris") or prop.contains("glass") else 0.0
			sprite.scale = Vector2.ONE * rng.randf_range(0.7, 1.0)
			parent.add_child(sprite)


func _add_lamps(params: Dictionary, rng: RandomNumberGenerator) -> void:
	var color := Color(params.get("lamp_color", "#FFD0A0"))
	for i in int(params.get("lamps", 4)):
		var lamp := PointLight2D.new()
		lamp.texture = load("res://assets/fx/light.png")
		lamp.color = color
		lamp.energy = 0.8
		lamp.texture_scale = 3.5
		lamp.shadow_enabled = true
		# Không đặt đèn ở phòng xuất phát (đã có đèn tàu con thoi)
		lamp.position = cell_to_world(gen.room_center(rng.randi_range(1, maxi(1, gen.rooms.size() - 1))))
		add_child(lamp)


# --- Địa hình ngoài trời ----------------------------------------------------------------------

func _build_terrain(t: TerrainGenerator, params: Dictionary, rng: RandomNumberGenerator, parent: Node2D) -> void:
	var palette: Dictionary = params.get("palette", {})
	var colors := {
		TerrainGenerator.Type.GROUND: Color(palette.get("ground", "#8A6A52")),
		TerrainGenerator.Type.ROUGH: Color(palette.get("rough", "#7A5E4A")),
		TerrainGenerator.Type.FOREST: Color(palette.get("forest", "#5E6A40")),
		TerrainGenerator.Type.PATH: Color(palette.get("path", "#B09070")),
		TerrainGenerator.Type.WATER: Color(palette.get("water", "#3A6A9A")),
		TerrainGenerator.Type.CLIFF: Color(palette.get("cliff", "#4A3E3A")),
	}
	var color_img := Image.create(t.size.x, t.size.y, false, Image.FORMAT_RGBA8)
	var height_img := Image.create(t.size.x, t.size.y, false, Image.FORMAT_L8)
	var variation := FastNoiseLite.new()
	variation.seed = rng.randi()
	variation.frequency = 0.08
	for y in t.size.y:
		for x in t.size.x:
			var i := y * t.size.x + x
			var type: int = t.terrain[i]
			var c: Color = colors[type]
			c = c.lightened(variation.get_noise_2d(x, y) * 0.12) if variation.get_noise_2d(x, y) > 0 else c.darkened(-variation.get_noise_2d(x, y) * 0.12)
			c.a = 0.3 if type == TerrainGenerator.Type.WATER else 1.0
			color_img.set_pixel(x, y, c)
			height_img.set_pixel(x, y, Color(t.height[i], t.height[i], t.height[i]))
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(color_img)
	sprite.centered = false
	sprite.scale = Vector2.ONE * cell_size
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index = -10
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("height_map", ImageTexture.create_from_image(height_img))
	var detail_path := "res://assets/terrain/%s_detail.png" % params.get("tileset", "debris")
	if ResourceLoader.exists(detail_path):
		mat.set_shader_parameter("detail_tex", load(detail_path))
	mat.set_shader_parameter("noise_tex", load("res://assets/terrain/noise_0.png"))
	mat.set_shader_parameter("cells", Vector2(t.size))
	mat.set_shader_parameter("water_color", colors[TerrainGenerator.Type.WATER])
	sprite.material = mat
	add_child(sprite)
	_add_vegetation(t, params, rng, parent)


## Cây (ô rừng) và đá (chân vách) — có bóng đổ, y-sort cùng nhân vật để đi "khuất" sau cây.
func _add_vegetation(t: TerrainGenerator, params: Dictionary, rng: RandomNumberGenerator, parent: Node2D) -> void:
	var trees: Array = params.get("trees", ["deco_plant_a"]).map(func(p): return load("res://assets/props/%s.png" % p))
	var rocks: Array = params.get("rocks", ["deco_rock_a"]).map(func(p): return load("res://assets/props/%s.png" % p))
	var density := float(params.get("tree_density", 0.3))
	var max_props := int(params.get("max_props", 1400))
	var placed := 0
	for y in t.size.y:
		for x in t.size.x:
			if placed >= max_props:
				return
			var c := Vector2i(x, y)
			var type := t.type_at(c)
			var tex: Texture2D = null
			var scale := 1.0
			if type == TerrainGenerator.Type.FOREST and rng.randf() < density:
				tex = trees[rng.randi() % trees.size()]
				scale = rng.randf_range(1.1, 1.8)
			elif type == TerrainGenerator.Type.CLIFF and rng.randf() < 0.22 and _near_floor(c):
				tex = rocks[rng.randi() % rocks.size()]
				scale = rng.randf_range(1.2, 2.0)
			if tex == null:
				continue
			var pos := cell_to_world(c) + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
			var shadow := Sprite2D.new()
			shadow.texture = tex
			shadow.modulate = Color(0, 0, 0, 0.32)
			shadow.position = pos + Vector2(10, 8) * scale
			shadow.scale = Vector2(scale, scale * 0.8)
			shadow.z_index = -5
			add_child(shadow)
			var prop := Sprite2D.new()
			prop.texture = tex
			prop.position = pos
			prop.scale = Vector2.ONE * scale
			prop.offset = Vector2(0, -tex.get_height() * 0.3)
			parent.add_child(prop)
			placed += 1
