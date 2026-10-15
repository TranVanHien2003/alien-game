extends RefCounted
## Vòng lặp năm, sự kiện, nghiên cứu, nhiệm vụ, giải cứu, chế tạo.


func _answer_events() -> void:
	while Game.pending_event != "":
		var choices := Game.available_choices(Game.get_pending_event())
		Game.choose(choices[0].index)


func test_new_game_initial_state(t) -> void:
	Game.new_game(42)
	t.equal(Game.year, 0, "bắt đầu từ năm 0")
	t.equal(Game.pending_event, "ev_departure", "sự kiện mở đầu bắt buộc")
	t.check(Game.crew.has("khang"), "thuyền trưởng có trong đoàn")
	t.check(Game.loadout.weapons.size() == 1, "có vũ khí khởi đầu")
	t.check(not Game.advance_year(), "không qua năm khi đang chờ lựa chọn")


func test_play_full_chapter(t) -> void:
	Game.new_game(7)
	var guard := 0
	while not Game.is_over() and guard < 200:
		_answer_events()
		Game.advance_year()
		guard += 1
	t.check(Game.is_over(), "chương kết thúc (hoàn thành hoặc thua)")
	t.check(Game.chapter_done or Game.ending_id != "", "có trạng thái kết thúc")


func test_research_unlocks_tech(t) -> void:
	Game.new_game(1)
	_answer_events()
	ResearchSystem.set_project(Game, "hydroponics_2")
	ResearchSystem.add_points(Game, 100)
	t.check("hydroponics_2" in Game.techs, "mở được công nghệ")
	t.check(Game.research_bank > 0.0, "điểm dư được giữ lại")
	t.check(ResearchSystem.can_research(Game, "neural_interface") == false, "chưa đủ tiền đề")


func test_auto_mission_and_rescue(t) -> void:
	Game.new_game(3)
	_answer_events()
	var option: Dictionary = MissionSystem.available(Game).filter(func(o): return o.mission.id == "msn_salvage_debris")[0]
	t.check(MissionSystem.launch_auto(Game, option, ["huy", "tuan"]), "giao được nhiệm vụ")
	t.equal(Game.crew.huy.status, CrewSystem.MISSION, "thành viên đang làm nhiệm vụ")
	# Ép thất bại có người mất tích
	var entry: Dictionary = Game.active_missions.pop_back()
	MissionSystem.resolve(Game, entry, false, ["huy"])
	t.equal(Game.crew.huy.status, CrewSystem.MISSING, "huy mất tích")
	var rescue := MissionSystem.available(Game).filter(func(o): return o.target == "huy")
	t.equal(rescue.size(), 1, "sinh nhiệm vụ giải cứu")
	MissionSystem.resolve(Game, MissionSystem._make_entry(Game, rescue[0], ["khang", "tuan"], "khang"), true, [])
	t.equal(Game.crew.huy.status, CrewSystem.IDLE, "huy được cứu")


func test_missing_crew_dies_after_window(t) -> void:
	Game.new_game(5)
	_answer_events()
	CrewSystem.set_missing(Game, "mai", "loc_debris")
	for i in 10:
		Game.year += 1
		CrewSystem.tick_year(Game)
	t.check(not Game.crew.has("mai"), "quá hạn giải cứu thì mất")


func test_crafting_consumes_materials(t) -> void:
	Game.new_game(1)
	Game.items["bang"] = 3
	var water := Game.get_stat("water")
	t.check(Crafting.craft(Game, "r_water"), "chế tạo được")
	t.equal(Game.item_count("bang"), 0, "tiêu hao nguyên liệu")
	t.check(Game.get_stat("water") > water or water >= 100.0, "tăng nước")
	t.check(not Crafting.craft(Game, "r_scatter"), "công thức khóa cần công nghệ")


func test_combat_stats_from_skills_and_modules(t) -> void:
	Game.new_game(1)
	var base := CombatStats.compute(Game, "bao", ["bao"])
	Game.items["armor_plate"] = 1
	t.check(Inventory.equip(Game, "modules", "armor_plate"), "trang bị module")
	var geared := CombatStats.compute(Game, "bao", ["bao"])
	t.equal(geared.armor, base.armor + 15.0, "module cộng giáp")
	t.check(base.damage_mult > 1.0, "kỹ thuật tăng sát thương")


func test_loot_tables(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var loot := Loot.roll(rng, "lt_boss_warden")
	t.check(loot.has("w_rail_rifle"), "boss luôn rơi đồ đảm bảo")
