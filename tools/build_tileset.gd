extends SceneTree
## Dựng res://assets/tiles/world_tileset.tres từ các atlas do tools/import_assets.py sinh ra.
## godot --headless --script res://tools/build_tileset.gd
##
## Mỗi biome = một TileSetAtlasSource (source id theo thứ tự trong atlas.json "biomes").
## Hàng 0: sàn (có lưới tìm đường). Các hàng sau: 47 biến thể tường (va chạm + bóng đổ).

const OUT := "res://assets/tiles/world_tileset.tres"


func _initialize() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles/atlas.json"))
	var size := int(meta.tile_size)
	var half := size / 2.0
	var square := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])

	var ts := TileSet.new()
	ts.tile_size = Vector2i(size, size)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_occlusion_layer()
	ts.add_navigation_layer()
	ts.set_navigation_layer_layers(0, 1)

	var nav := NavigationPolygon.new()
	nav.vertices = square
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var occluder := OccluderPolygon2D.new()
	occluder.polygon = square

	var columns := int(meta.columns)
	for i in meta.biomes.size():
		var source := TileSetAtlasSource.new()
		source.texture = load("res://assets/tiles/%s.png" % meta.biomes[i])
		source.texture_region_size = Vector2i(size, size)
		ts.add_source(source, i)
		for x in int(meta.floor_variants):
			source.create_tile(Vector2i(x, 0))
			source.get_tile_data(Vector2i(x, 0), 0).set_navigation_polygon(0, nav)
		for w in meta.wall_masks.size():
			var coords := Vector2i(w % columns, 1 + w / columns)
			source.create_tile(coords)
			var data := source.get_tile_data(coords, 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, square)
			if data.has_method("add_occluder_polygon"):
				data.add_occluder_polygon(0)
				data.set_occluder_polygon(0, 0, occluder)
			else:
				data.set_occluder(0, occluder)

	var err := ResourceSaver.save(ts, OUT)
	print("✓ %s (%d biome)" % [OUT, meta.biomes.size()] if err == OK else "✘ Lỗi lưu tileset: %d" % err)
	quit(0 if err == OK else 1)
