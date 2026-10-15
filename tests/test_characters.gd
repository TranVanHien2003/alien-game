extends Node
## Hệ nhân vật: dinh dưỡng, thuộc tính, nhiều vai trò, tài năng, vòng đời, kỳ ngộ, thu nhận người lạ.


func _answer_events() -> void:
	while Game.pending_event != "":
		Game.choose(Game.available_choices(Game.get_pending_event())[0].index)


func test_nutrition_by_age_gender_role(t) -> void:
	Game.new_game(1)
	var miner := NutritionSystem.consumption(Game, "hai")
	var scientist := NutritionSystem.consumption(Game, "mai")
	t.check(miner > scientist, "thợ mỏ (nam) ăn nhiều hơn nhà khoa học (nữ)")
	var child := CharacterFactory.newborn(Game, Game.rng, ["thu_ha", "khang"])
	CrewSystem.add_member(Game, child.id)
	t.check(NutritionSystem.consumption(Game, child.id) < scientist, "trẻ em ăn ít hơn người lớn")
	t.equal(NutritionSystem.consumption(Game, "lac"), 0.0, "AI không ăn")
	var food_before := Game.get_stat("food")
	NutritionSystem.tick_year(Game)
	t.check(Game.get_stat("food") < food_before, "phi hành đoàn tiêu thụ lương thực mỗi năm")


func test_proficiency_and_efficiency(t) -> void:
	Game.new_game(1)
	t.check(AttributeSystem.proficiency(Game, "hai", "miner") > AttributeSystem.proficiency(Game, "hai", "scout"), "Hải hợp vai thợ mỏ hơn trinh sát")
	var before: float = CombatStats.compute(Game, "hai").mining_power
	Game.crew.hai.attributes.strength = 95.0
	Game.crew.hai.attributes.endurance = 95.0
	t.check(CombatStats.compute(Game, "hai").mining_power > before, "thuộc tính cao -> vai hiệu quả hơn")


func test_multiple_roles(t) -> void:
	Game.new_game(1)
	t.check(not AttributeSystem.can_assign(Game, "mai", "miner") or AttributeSystem.proficiency(Game, "mai", "miner") >= 25.0, "giao vai cần đủ thành thạo")
	t.check(AttributeSystem.assign_role(Game, "quang", "miner"), "giao thêm vai cho Quang")
	t.check("miner" in Game.crew.quang.roles and "soldier" in Game.crew.quang.roles, "sở hữu nhiều vai")
	Game.items["t_mining_drill"] = Game.item_count("t_mining_drill") + 1
	t.check(AttributeSystem.set_active_role(Game, "quang", "miner"), "đổi vai chính")
	t.equal(Roles.role_of("quang"), "miner", "vai chính mới")
	t.check(Inventory.equipped(Game, "quang", "weapon") == "" or Roles.can_use("quang", Inventory.equipped(Game, "quang", "weapon")), "trang bị hợp vai mới")


func test_training_and_role_unlock(t) -> void:
	Game.new_game(2)
	_answer_events()
	Game.crew.huy.training_focus = "perception"
	var before := AttributeSystem.base(Game, "huy", "perception")
	AttributeSystem.yearly_training(Game)
	t.check(AttributeSystem.base(Game, "huy", "perception") > before, "huấn luyện tăng thuộc tính")
	Game.crew.huy.attributes.intellect = 99.0
	Game.crew.huy.attributes.perception = 99.0
	var unlocked := AttributeSystem.check_role_unlocks(Game, "huy")
	t.check("scientist" in unlocked or "scientist" in Game.crew.huy.roles, "tự mở vai khi thuộc tính đủ cao")


func test_talent_tree(t) -> void:
	Game.new_game(1)
	Talents.add_xp(Game, "quang", 500)
	t.check(Talents.points(Game, "quang") >= 3, "lên cấp có điểm tài năng")
	t.check(not Talents.can_learn(Game, "quang", "sol_bulwark"), "cần tài năng tiền đề")
	var hp_before: float = CombatStats.compute(Game, "quang").max_hp
	t.check(Talents.learn(Game, "quang", "sol_drill"), "học tài năng bậc 1")
	t.check(CombatStats.compute(Game, "quang").max_hp > hp_before, "tài năng cộng chỉ số")
	t.check(Talents.learn(Game, "quang", "sol_bulwark"), "mở bậc 2 sau khi có tiền đề")
	t.check(not Talents.can_learn(Game, "quang", "med_triage"), "không học tài năng của vai không sở hữu")


func test_child_grows_and_comes_of_age_with_encounter(t) -> void:
	Game.new_game(3)
	_answer_events()
	var child := CharacterFactory.newborn(Game, Game.rng, ["thu_ha", "khang"])
	CrewSystem.add_member(Game, child.id)
	t.check(Lifecycle.is_child(Game, child.id), "trẻ em chưa có vai")
	t.check(not child.id in CrewSystem.available(Game), "trẻ em không đi nhiệm vụ")
	var before := AttributeSystem.base(Game, child.id, "intellect")
	child.birth_year = Game.year - 16
	Lifecycle._grow_children(Game, Content.config.lifecycle)
	t.check(AttributeSystem.base(Game, child.id, "intellect") > before, "trẻ lớn lên, thuộc tính tăng")
	var special: Array = Game.special_queue.filter(func(s): return s.char_id == child.id)
	t.equal(special.size(), 1, "đến tuổi -> lễ trưởng thành")
	special[0].encounter = "enc_lac_dream"
	var options := Lifecycle.coming_of_age_options(Game, special[0])
	t.check(options[0].encounter, "lựa chọn kỳ ngộ đứng đầu")
	var intel := AttributeSystem.base(Game, child.id, "intellect")
	Lifecycle.resolve_coming_of_age(Game, special[0], options[0])
	t.equal(Roles.role_of(child.id), "scientist", "chọn vai trong kỳ ngộ")
	t.check("rare_lac_echo" in Talents.owned(Game, child.id), "nhận tài năng hiếm")
	t.check(AttributeSystem.base(Game, child.id, "intellect") >= intel + 10.0, "thuộc tính tăng mạnh")
	t.check(child.id in CrewSystem.available(Game) or Game.character_age(child.id) < 16, "trưởng thành thì đi nhiệm vụ được")


func test_custom_characters_survive_save(t) -> void:
	Game.new_game(4)
	var child := CharacterFactory.newborn(Game, Game.rng, ["bich", "hai"])
	CrewSystem.add_member(Game, child.id)
	SaveManager.save_game("chars_test")
	Game.new_game(5)
	t.check(not Content.has_entry("characters", child.id), "ván mới xóa nhân vật cũ")
	SaveManager.load_game("chars_test")
	t.check(Content.has_entry("characters", child.id) and Game.crew.has(child.id), "nạp lại nhân vật sinh lúc chạy")
	SaveManager.delete_save("chars_test")


func test_rescue_joins_and_stranger_recruit(t) -> void:
	Game.new_game(6)
	Game.pending_event = ""
	CrewSystem.set_missing(Game, "huy", "loc_comet")
	var option: Dictionary = MissionSystem.available(Game).filter(func(o): return o.target == "huy")[0]
	MissionSystem.start_action(Game, option, ["thu_ha", "quang", "thanh"])
	var level: Node = load("res://scenes/mission/mission_level.tscn").instantiate()
	add_child(level)
	await get_tree().physics_frame
	level._join_unit("huy", level.exit_zone.global_position, false)
	t.equal(level.units.size(), 4, "người được cứu gia nhập đội trên bản đồ")
	var obj := Objective.new()
	obj.global_position = level.exit_zone.global_position
	level._on_stranger(obj)
	t.equal(level.guests.size(), 1, "gặp người lạ")
	var stranger_id: String = level.guests[0]
	for u in level.units:
		u.state = Unit.State.EVACUATED
	level._finish(false, true)
	t.equal(Game.crew_status("huy"), CrewSystem.IDLE, "người mất tích về tàu được cứu")
	level.decide_recruit(stranger_id, true)
	t.check(Game.crew.has(stranger_id) and not Game.crew[stranger_id].get("guest", false), "thu nhận người lạ")
	t.check(stranger_id in CrewSystem.available(Game), "người mới sẵn sàng làm nhiệm vụ")
	obj.free()
	level.queue_free()
	await get_tree().process_frame


func test_mission_growth(t) -> void:
	Game.new_game(7)
	var before := AttributeSystem.base(Game, "quang", "strength")
	var text := AttributeSystem.apply_mission_growth(Game, "quang", {"kills": 20, "mined": 0, "worked": 0, "revived": 0, "healed": 0, "distance": 4000}, true)
	t.check(AttributeSystem.base(Game, "quang", "strength") > before, "khám phá/chiến đấu tăng thuộc tính")
	t.check(text != "", "có mô tả tăng trưởng")
