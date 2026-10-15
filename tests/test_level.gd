extends Node
## Bộ sinh bản đồ + chạy thử màn action thật trong vài giây (không cần người chơi).


func test_generated_levels_are_connected(t) -> void:
	for params in Content.all("levels"):
		for seed_value in 5:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var gen := LevelGenerator.generate(rng, params)
			var dist := gen.distances_from(gen.room_center(0))
			for i in gen.rooms.size():
				var c := gen.room_center(i)
				t.check(dist[c.y * gen.size.x + c.x] >= 0, "%s seed %d: phòng %d không tới được" % [params.id, seed_value, i])


func test_mission_level_runs(t) -> void:
	for mission_id in ["msn_salvage_debris", "msn_derelict"]:
		Game.new_game(2)
		Game.pending_event = ""
		Game.known_locations.append("loc_derelict")
		var option: Dictionary = MissionSystem.available(Game).filter(func(o): return o.mission.id == mission_id)[0]
		var team := ["khang", "tuan", "bao", "thu_ha"]
		t.check(MissionSystem.start_action(Game, option, team), "bắt đầu màn " + mission_id)
		var level: Node = load("res://scenes/mission/mission_level.tscn").instantiate()
		add_child(level)
		for i in 20:
			await get_tree().physics_frame
		t.equal(level.units.size(), 4, "đủ 4 thành viên trên bản đồ")
		t.check(get_tree().get_nodes_in_group("enemies").size() >= 8, "bản đồ có nhiều quái")
		t.check(get_tree().get_nodes_in_group("minable").size() >= 10, "bản đồ có nhiều mỏ")
		t.check(level.gen.rooms.size() >= 9, "bản đồ lớn nhiều phòng")
		var walls: TileMapLayer = level.map.wall_layer
		var floor: TileMapLayer = level.map.floor_layer
		t.check(floor.get_used_cells().size() > 200, "TileMap có ô sàn")
		var wall_cell: Vector2i = walls.get_used_cells()[0]
		t.check(walls.get_cell_tile_data(wall_cell).get_collision_polygons_count(0) > 0, "tường có va chạm")
		t.check(floor.get_cell_tile_data(floor.get_used_cells()[0]).get_navigation_polygon(0) != null, "sàn có lưới tìm đường")

		# Ra lệnh: thợ mỏ khoan mỏ gần nhất -> mỏ mất máu
		var miner: Unit = level.units[1]
		var node: ResourceNode = get_tree().get_nodes_in_group("minable")[0]
		miner.global_position = node.global_position + Vector2(40, 0)
		var hp_before := node.hp
		miner.command({"type": "mine", "target": node})
		for i in 20:
			await get_tree().physics_frame
		t.check(not is_instance_valid(node) or node.hp < hp_before, "máy khoan khai thác được mỏ")

		# Một người gục -> y sĩ cứu dậy
		var victim: Unit = level.units[0]
		victim.take_damage(99999)
		t.equal(victim.state, Unit.State.DOWNED, "bị hạ gục")
		victim.revive_progress = 1.0
		await get_tree().physics_frame
		t.equal(victim.state, Unit.State.ACTIVE, "được cứu dậy")

		# Hoàn thành mục tiêu, đưa cả đội lên tàu, kết thúc
		level._add_progress(level.goal)
		level.run_loot = {"kim_loai": 5}
		for u in level.units:
			u.state = Unit.State.EVACUATED
		level._finish(true, true)
		t.check(Game.action_mission.is_empty(), "kết thúc nhiệm vụ")
		t.check(Game.item_count("kim_loai") >= 5, "mang đồ về kho")
		t.check(Game.crew.values().all(func(m): return m.status != CrewSystem.MISSING), "không ai mất tích khi đã lên tàu")
		level.queue_free()
		await get_tree().process_frame


func test_left_behind_goes_missing(t) -> void:
	Game.new_game(3)
	Game.pending_event = ""
	var option: Dictionary = MissionSystem.available(Game).filter(func(o): return o.mission.id == "msn_comet_ice")[0]
	MissionSystem.start_action(Game, option, ["tuan", "hai", "khang"])
	var level: Node = load("res://scenes/mission/mission_level.tscn").instantiate()
	add_child(level)
	await get_tree().physics_frame
	level.units[0].state = Unit.State.EVACUATED
	level.units[1].state = Unit.State.EVACUATED
	level.units[2].global_position += Vector2(5000, 0)  # kẹt lại xa tàu
	level._finish(false, true)
	t.equal(Game.crew_status("khang"), CrewSystem.MISSING, "người không kịp về tàu bị mất tích")
	t.equal(Game.crew_status("tuan"), CrewSystem.IDLE, "người đã lên tàu an toàn")
	level.queue_free()
	await get_tree().process_frame


func test_autotile_covers_all_masks(t) -> void:
	var seen := {}
	for mask in 256:
		var coords := LevelMap._wall_coords(mask)
		seen[coords] = true
		t.check(coords.y >= 1 and coords.x < LevelMap.COLUMNS, "mask %d -> %s ngoài atlas" % [mask, coords])
	t.equal(seen.size(), 47, "đúng 47 biến thể tường")


func test_squad_auto_engages_enemies(t) -> void:
	Game.new_game(4)
	Game.pending_event = ""
	var option: Dictionary = MissionSystem.available(Game).filter(func(o): return o.mission.id == "msn_hull_repair")[0]
	MissionSystem.start_action(Game, option, ["khang", "quang", "bao"])
	var level: Node = load("res://scenes/mission/mission_level.tscn").instantiate()
	add_child(level)
	await get_tree().physics_frame
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().physics_frame
	# Giữa phòng xuất phát (sàn chắc chắn), các thành viên đứng vòng quanh
	var enemy: Enemy = level.spawn_enemy("crawler", level.map.cell_to_world(level.gen.room_center(0)))
	var start_hp := enemy.hp
	for i in 180:
		await get_tree().physics_frame
	t.check(not is_instance_valid(enemy) or enemy.hp < start_hp, "đội tự bắn quái trong tầm")
	level._finish(false, false)
	level.queue_free()
	await get_tree().process_frame


func test_autopilot_plays_by_role_and_respects_manual(t) -> void:
	seed(12345)
	Game.new_game(8)
	Game.pending_event = ""
	var option: Dictionary = MissionSystem.available(Game).filter(func(o): return o.mission.id == "msn_salvage_debris")[0]
	MissionSystem.start_action(Game, option, ["tuan", "khang", "thu_ha", "huy"])
	var level: Node = load("res://scenes/mission/mission_level.tscn").instantiate()
	add_child(level)
	await get_tree().physics_frame
	var miner: Unit = level.units[0]
	var scout: Unit = level.units[3]
	# Thợ mỏ thấy một mỏ ngay cạnh -> tự đi khai thác
	var node: ResourceNode = get_tree().get_nodes_in_group("minable")[0]
	node.global_position = miner.global_position + Vector2(90, 0)
	# Người chỉ huy ra lệnh tay cho trinh sát đi một điểm
	var target: Vector2 = level.exit_zone.global_position + Vector2(0, 40)
	scout.command({"type": "move", "pos": target})
	# Dọn quái để kiểm tra đúng hành vi khai thác (quái gần sẽ khiến AI ưu tiên chiến đấu)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	var mined_or_mining := false
	var took_auto_task := false
	for i in 300:
		await get_tree().physics_frame
		took_auto_task = took_auto_task or miner.order.get("auto", false)
		mined_or_mining = mined_or_mining or miner.order.type == "mine" or miner.counters.mined > 0.0
	t.check(took_auto_task, "thợ mỏ tự nhận việc")
	t.check(mined_or_mining, "thợ mỏ ưu tiên khai thác")
	t.check(level.units.any(func(u): return u != scout and u.order.get("auto", false)), "các thành viên khác vẫn tự động")
	# Sau khi xong lệnh tay, trinh sát quay lại tự động
	t.check(not scout.order.get("manual", false), "xong việc được giao -> quay lại tự động")
	t.check(level.autopilot.efficiency(miner) > 0.15 and level.autopilot.efficiency(miner) <= 1.0, "hiệu quả AI trong khoảng hợp lệ")
	level._finish(false, false)
	level.queue_free()
	await get_tree().process_frame


func test_autopilot_efficiency_depends_on_stats_and_difficulty(t) -> void:
	Game.new_game(9)
	Game.pending_event = ""
	var option: Dictionary = MissionSystem.available(Game).filter(func(o): return o.mission.id == "msn_hull_repair")[0]
	MissionSystem.start_action(Game, option, ["mai", "hai"])
	var level: Node = load("res://scenes/mission/mission_level.tscn").instantiate()
	add_child(level)
	await get_tree().physics_frame
	var smart: Unit = level.units[0]
	var e1: float = level.autopilot.efficiency(smart)
	Game.crew.mai.attributes.intellect = 20.0
	Game.crew.mai.attributes.perception = 20.0
	t.check(level.autopilot.efficiency(smart) < e1, "chỉ số thấp -> AI kém hơn")
	var e2: float = level.autopilot.efficiency(smart)
	level.difficulty = 8.0
	t.check(level.autopilot.efficiency(smart) < e2 or e2 <= 0.15, "màn khó -> AI kém hơn")
	t.check(level.autopilot.think_interval(smart) > float(Content.config.auto.think_min), "AI kém suy nghĩ chậm hơn")
	level._finish(false, false)
	level.queue_free()
	await get_tree().process_frame
