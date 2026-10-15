class_name Lifecycle
extends RefCounted
## Vòng đời phi hành đoàn:
##   - Sinh con: mỗi năm có xác suất một cặp thành viên trưởng thành có con (trẻ mới mang thuộc tính cơ bản).
##   - Trẻ em lớn dần: thuộc tính tăng mỗi năm, thiên về thế mạnh của cha mẹ.
##   - Lễ trưởng thành (coming_of_age tuổi): chọn vai. Đôi khi là KỲ NGỘ -> tài năng hiếm + thuộc tính tăng mạnh.
##   - Kỳ ngộ ngẫu nhiên cho người lớn.
## Các sự kiện cần người chơi quyết định được xếp vào game.special_queue để hub phát bằng StoryPlayer.


static func tick_year(game: Node) -> void:
	var cfg: Dictionary = Content.config.get("lifecycle", {})
	_grow_children(game, cfg)
	_maybe_birth(game, cfg)
	_maybe_adult_encounter(game, cfg)


static func children(game: Node) -> Array:
	return game.crew.keys().filter(func(id): return is_child(game, id))


static func is_child(game: Node, char_id: String) -> bool:
	return Content.get_entry("characters", char_id).get("child", false) and game.crew.get(char_id, {}).get("roles", []).is_empty()


static func _grow_children(game: Node, cfg: Dictionary) -> void:
	var growth: Array = cfg.get("child_growth", [2, 4])
	var adult_age := int(cfg.get("coming_of_age", 16))
	for char_id in children(game):
		var data := Content.get_entry("characters", char_id)
		# Thiên về thế mạnh của cha mẹ: thuộc tính cao nhất của họ tăng nhanh hơn
		var favored := {}
		for parent in data.get("parents", []):
			var best := ""
			for attr in AttributeSystem.ids():
				if best == "" or AttributeSystem.base(game, parent, attr) > AttributeSystem.base(game, parent, best):
					best = attr
			if best != "":
				favored[best] = true
		for attr in AttributeSystem.ids():
			var gain: float = game.rng.randf_range(float(growth[0]), float(growth[1])) * (1.5 if favored.has(attr) else 1.0)
			if NutritionSystem.is_hungry(game):
				gain *= 0.4
			AttributeSystem.grow(game, char_id, attr, gain)
		if game.character_age(char_id) >= adult_age and not game.special_queue.any(func(s): return s.get("char_id", "") == char_id):
			var encounter := ""
			if game.rng.randf() < float(cfg.get("encounter_chance", 0.3)):
				var options := Content.all("encounters").filter(func(e): return e.get("kind", "") == "coming_of_age")
				if not options.is_empty():
					encounter = options[game.rng.randi() % options.size()].id
			game.special_queue.append({"type": "coming_of_age", "char_id": char_id, "encounter": encounter})


static func _maybe_birth(game: Node, cfg: Dictionary) -> void:
	if children(game).size() >= int(cfg.get("max_children", 6)) or game.get_stat("food") < 30.0 or game.get_stat("morale") < 35.0:
		return
	if game.rng.randf() > float(cfg.get("birth_chance", 0.1)):
		return
	var adults: Array = game.crew.keys().filter(func(id):
		var d := Content.get_entry("characters", id)
		var age: int = game.character_age(id)
		return not d.get("ageless", false) and not d.get("child", false) and age >= 20 and age <= 45 and game.crew[id].status == CrewSystem.IDLE)
	var mothers: Array = adults.filter(func(id): return Content.get_entry("characters", id).get("gender", "") == "female")
	var fathers: Array = adults.filter(func(id): return Content.get_entry("characters", id).get("gender", "") == "male")
	if mothers.is_empty() or fathers.is_empty():
		return
	var parents := [mothers[game.rng.randi() % mothers.size()], fathers[game.rng.randi() % fathers.size()]]
	var child := CharacterFactory.newborn(game, game.rng, parents)
	CrewSystem.add_member(game, child.id)
	game.change_stat("morale", 4)
	game.add_log("👶 %s chào đời — con của %s và %s." % [child.name, CrewSystem.display_name(parents[0]), CrewSystem.display_name(parents[1])])


static func _maybe_adult_encounter(game: Node, cfg: Dictionary) -> void:
	if game.rng.randf() > float(cfg.get("adult_encounter_chance", 0.15)):
		return
	var options := Content.all("encounters").filter(func(e): return e.get("kind", "") == "adult")
	var pool := CrewSystem.available(game)
	if options.is_empty() or pool.is_empty():
		return
	var encounter: Dictionary = options[game.rng.randi() % options.size()]
	game.special_queue.append({"type": "encounter", "char_id": pool[game.rng.randi() % pool.size()], "encounter": encounter.id})


# --- Giải quyết các sự kiện đặc biệt (hub gọi sau khi người chơi chọn) ---------------------

## Lựa chọn cho lễ trưởng thành: 3 vai thành thạo nhất (+ vai của kỳ ngộ nếu có).
static func coming_of_age_options(game: Node, special: Dictionary) -> Array:
	var char_id: String = special.char_id
	var roles := AttributeSystem.best_roles_for(AttributeSystem.all_values(game, char_id), 3)
	var options := []
	var encounter := Content.get_entry("encounters", special.get("encounter", ""))
	if not encounter.is_empty():
		var role_id: String = encounter.get("role", roles[0])
		options.append({"role": role_id, "encounter": true, "text": "✦ %s — Kỳ ngộ «%s» (tài năng hiếm + thuộc tính tăng mạnh)" % [Roles.name_of(role_id), encounter.get("title", "")]})
		roles.erase(role_id)
	for role_id in roles:
		options.append({"role": role_id, "encounter": false, "text": "%s (thành thạo %d)" % [Roles.name_of(role_id), roundi(AttributeSystem.proficiency(game, char_id, role_id))]})
	return options


static func resolve_coming_of_age(game: Node, special: Dictionary, option: Dictionary) -> String:
	var char_id: String = special.char_id
	var member: Dictionary = game.crew[char_id]
	member.roles = [option.role]
	member.active_role = option.role
	var text := "%s trưởng thành và chọn con đường %s." % [CrewSystem.display_name(char_id), Roles.name_of(option.role)]
	var bonus_text := ""
	if option.get("encounter", false):
		var encounter := Content.get_entry("encounters", special.get("encounter", ""))
		bonus_text = AttributeSystem.apply_bonus(game, char_id, encounter.get("attributes", {}))
		if encounter.has("talent"):
			Talents.grant(game, char_id, encounter.talent)
		member.talent_points = Talents.points(game, char_id) + 2
	else:
		var weights: Dictionary = Content.get_entry("roles", option.role).get("attribute_weights", {})
		var bonus := {}
		for attr in weights:
			bonus[attr] = 4.0
		bonus_text = AttributeSystem.apply_bonus(game, char_id, bonus)
		member.talent_points = Talents.points(game, char_id) + 1
	Roles.auto_equip(game, char_id)
	game.add_log(text + (" (" + bonus_text + ")" if bonus_text != "" else ""))
	return text + ("\n" + bonus_text if bonus_text != "" else "")


static func resolve_encounter(game: Node, char_id: String, encounter_id: String) -> String:
	var encounter := Content.get_entry("encounters", encounter_id)
	var parts := PackedStringArray()
	var gained := AttributeSystem.apply_bonus(game, char_id, encounter.get("attributes", {}))
	if gained != "":
		parts.append(gained)
	if encounter.has("talent_points"):
		game.crew[char_id].talent_points = Talents.points(game, char_id) + int(encounter.talent_points)
		parts.append("+%d điểm tài năng" % int(encounter.talent_points))
	if encounter.has("talent") and game.rng.randf() < float(encounter.get("talent_chance", 1.0)):
		Talents.grant(game, char_id, encounter.talent)
		parts.append("tài năng " + Content.get_entry("talents", encounter.talent).get("name", ""))
	AttributeSystem.check_role_unlocks(game, char_id)
	var text := "%s — %s: %s" % [encounter.get("title", "Kỳ ngộ"), CrewSystem.display_name(char_id), ", ".join(parts)]
	game.add_log("✦ " + text)
	return text
