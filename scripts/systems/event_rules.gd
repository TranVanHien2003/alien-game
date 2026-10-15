class_name EventRules
extends RefCounted
## "Ngôn ngữ nội dung" dùng chung cho sự kiện, lựa chọn, nhiệm vụ và công nghệ:
## đánh giá điều kiện và áp dụng hiệu ứng. Xem MODDING.md để biết đầy đủ các khóa.
##
## Điều kiện (tất cả đều tùy chọn):
##   year_min, year_max, generation, chance (0..1)
##   flags_all, flags_none, items_all, characters_alive, characters_missing,
##   tech_all, locations_known: [..]
##   stats_min / stats_max: {stat: n}
##
## Hiệu ứng (tất cả đều tùy chọn):
##   stats: {stat: delta}           flags_set / flags_clear: [..]
##   items_add / items_remove: {id: n}
##   characters_add / characters_remove: [..]
##   research_points: n             techs_unlock: [..]
##   locations_discover: [..]       discover_random_location: true
##   loot: "loot_table_id"
##   log: "..."                     next_event: "event_id" (chỉ dùng trong lựa chọn sự kiện)


static func check(game: Node, cond: Dictionary) -> bool:
	if cond.has("year_min") and game.year < int(cond.year_min):
		return false
	if cond.has("year_max") and game.year > int(cond.year_max):
		return false
	if cond.has("generation") and game.generation != int(cond.generation):
		return false
	for flag in cond.get("flags_all", []):
		if not game.has_flag(flag):
			return false
	for flag in cond.get("flags_none", []):
		if game.has_flag(flag):
			return false
	for stat in cond.get("stats_min", {}):
		if game.get_stat(stat) < float(cond.stats_min[stat]):
			return false
	for stat in cond.get("stats_max", {}):
		if game.get_stat(stat) > float(cond.stats_max[stat]):
			return false
	for item_id in cond.get("items_all", []):
		if game.item_count(item_id) <= 0:
			return false
	for char_id in cond.get("characters_alive", []):
		if not game.is_present(char_id):
			return false
	for char_id in cond.get("characters_missing", []):
		if game.crew_status(char_id) != CrewSystem.MISSING:
			return false
	for tech_id in cond.get("tech_all", []):
		if not tech_id in game.techs:
			return false
	for loc_id in cond.get("locations_known", []):
		if not loc_id in game.known_locations:
			return false
	if cond.has("chance") and game.rng.randf() > float(cond.chance):
		return false
	return true


static func apply(game: Node, eff: Dictionary) -> void:
	for stat in eff.get("stats", {}):
		game.change_stat(stat, float(eff.stats[stat]))
	for flag in eff.get("flags_set", []):
		game.flags[flag] = true
	for flag in eff.get("flags_clear", []):
		game.flags.erase(flag)
	for item_id in eff.get("items_add", {}):
		game.add_item(item_id, int(eff.items_add[item_id]))
	for item_id in eff.get("items_remove", {}):
		game.add_item(item_id, -int(eff.items_remove[item_id]))
	for char_id in eff.get("characters_add", []):
		CrewSystem.add_member(game, char_id)
	for char_id in eff.get("characters_remove", []):
		game.crew.erase(char_id)
	if eff.has("research_points"):
		ResearchSystem.add_points(game, float(eff.research_points))
	for tech_id in eff.get("techs_unlock", []):
		ResearchSystem.unlock(game, tech_id)
	for loc_id in eff.get("locations_discover", []):
		game.discover_location(loc_id)
	if eff.get("discover_random_location", false):
		var unknown: Array = Content.ids("locations").filter(func(id): return not id in game.known_locations)
		if unknown.is_empty():
			game.add_log("Máy quét không tìm thấy gì mới trong tầm hoạt động.")
		else:
			game.discover_location(unknown[game.rng.randi() % unknown.size()])
	if eff.has("loot"):
		Loot.give(game, Loot.roll(game.rng, eff.loot))
	if eff.has("log"):
		game.add_log(eff.log)
