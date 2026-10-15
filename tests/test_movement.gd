extends Node
## Di chuyển: thành viên phải tới được đích xa trên bản đồ nhiều góc tường mà không bị kẹt.

func _run_trips(t, mission_id: String, trips: int, frames_per_trip: int) -> float:
	seed(777)
	Game.new_game(21)
	Game.pending_event = ""
	Game.known_locations = Content.ids("locations")
	var option: Dictionary = MissionSystem.available(Game).filter(func(o): return o.mission.id == mission_id)[0]
	MissionSystem.start_action(Game, option, ["khang", "tuan", "bao"])
	var level: Node = load("res://scenes/mission/mission_level.tscn").instantiate()
	add_child(level)
	await get_tree().physics_frame
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for u in level.units:
		u.auto = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var arrived := 0
	for trip in trips:
		var room := rng.randi_range(1, level.gen.rooms.size() - 1)
		var goal: Vector2 = level.map.cell_to_world(level.gen.room_center(room))
		for u in level.units:
			u.command({"type": "move", "pos": goal})
		for i in frames_per_trip:
			await get_tree().physics_frame
			if level.units.all(func(u): return u.global_position.distance_to(goal) < 140.0):
				break
		for u in level.units:
			if u.global_position.distance_to(goal) < 140.0:
				arrived += 1
	level._finish(false, false)
	level.queue_free()
	await get_tree().process_frame
	return float(arrived) / float(trips * 3)


func test_units_reach_far_rooms_interior(t) -> void:
	var rate: float = await _run_trips(t, "msn_hull_repair", 6, 1500)
	t.check(rate >= 0.95, "tới đích trong tàu: %d%%" % roundi(rate * 100))


func test_units_reach_far_points_outdoor(t) -> void:
	var rate: float = await _run_trips(t, "msn_salvage_debris", 4, 2400)
	t.check(rate >= 0.9, "tới đích ngoài trời: %d%%" % roundi(rate * 100))
