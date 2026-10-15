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
		t.check(MissionSystem.start_action(Game, option, ["bao", "tuan"], "bao"), "bắt đầu màn " + mission_id)
		var level: Node = load("res://scenes/mission/mission_level.tscn").instantiate()
		add_child(level)
		for i in 30:
			await get_tree().physics_frame
		t.check(is_instance_valid(level.player), "có người chơi")
		t.check(get_tree().get_nodes_in_group("enemies").size() > 0, "có quái")
		t.check(get_tree().get_nodes_in_group("minable").size() > 0, "có mỏ tài nguyên")
		# Mô phỏng hoàn thành mục tiêu và về tàu
		level._add_progress(level.goal)
		level.run_loot = {"kim_loai": 5}
		level._on_exit_entered()
		t.check(Game.action_mission.is_empty(), "kết thúc nhiệm vụ")
		t.check(Game.item_count("kim_loai") >= 5, "mang đồ về kho")
		level.queue_free()
		await get_tree().process_frame
