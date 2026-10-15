class_name Talents
extends RefCounted
## Cây tài năng theo vai trò (data/talents). XP từ nhiệm vụ -> lên cấp -> điểm tài năng.
## Tài năng cộng chỉ số chiến đấu (modifiers), thuộc tính (attributes) và có thể mở kỹ năng (grants_ability).
## Tài năng "rare" chỉ nhận được qua kỳ ngộ.


static func for_role(role_id: String) -> Array:
	var list := Content.all("talents").filter(func(t): return t.get("role", "") == role_id and not t.get("rare", false))
	list.sort_custom(func(a, b): return int(a.get("tier", 1)) < int(b.get("tier", 1)))
	return list


static func owned(game: Node, char_id: String) -> Array:
	return game.crew.get(char_id, {}).get("talents", [])


static func points(game: Node, char_id: String) -> int:
	return int(game.crew.get(char_id, {}).get("talent_points", 0))


static func level(game: Node, char_id: String) -> int:
	return 1 + int(float(game.crew.get(char_id, {}).get("xp_total", 0)) / float(Content.config.get("talent_points", {}).get("xp_per_level", 120)))


static func add_xp(game: Node, char_id: String, xp: float) -> void:
	var member: Dictionary = game.crew.get(char_id, {})
	if member.is_empty():
		return
	var before := level(game, char_id)
	member.xp_total = float(member.get("xp_total", 0)) + xp
	var gained := level(game, char_id) - before
	if gained > 0:
		member.talent_points = points(game, char_id) + gained
		game.add_log("⬆ %s lên cấp %d (+%d điểm tài năng)." % [CrewSystem.display_name(char_id), level(game, char_id), gained])


static func can_learn(game: Node, char_id: String, talent_id: String) -> bool:
	var t := Content.get_entry("talents", talent_id)
	if t.is_empty() or t.get("rare", false) or talent_id in owned(game, char_id):
		return false
	if not t.get("role", "") in game.crew.get(char_id, {}).get("roles", []):
		return false
	if points(game, char_id) < int(t.get("cost", 1)):
		return false
	return t.get("requires", []).all(func(r): return r in owned(game, char_id))


static func learn(game: Node, char_id: String, talent_id: String) -> bool:
	if not can_learn(game, char_id, talent_id):
		return false
	var member: Dictionary = game.crew[char_id]
	member.talent_points = points(game, char_id) - int(Content.get_entry("talents", talent_id).get("cost", 1))
	grant(game, char_id, talent_id)
	return true


## Trao tài năng trực tiếp (kỳ ngộ, tài năng hiếm) — không tốn điểm.
static func grant(game: Node, char_id: String, talent_id: String) -> void:
	var member: Dictionary = game.crew.get(char_id, {})
	if member.is_empty() or talent_id in member.get("talents", []):
		return
	var list: Array = member.get("talents", [])
	list.append(talent_id)
	member.talents = list
	game.add_log("✦ %s đạt tài năng: %s" % [CrewSystem.display_name(char_id), Content.get_entry("talents", talent_id).get("name", talent_id)])


## Tổng modifier từ tài năng của vai đang dùng (+ mọi tài năng hiếm).
static func modifiers(game: Node, char_id: String, role_id: String) -> Dictionary:
	var result := {}
	for talent_id in owned(game, char_id):
		var t := Content.get_entry("talents", talent_id)
		if t.get("rare", false) or t.get("role", "") == role_id:
			for stat in t.get("modifiers", {}):
				result[stat] = float(result.get(stat, 0.0)) + float(t.modifiers[stat])
	return result


static func abilities(game: Node, char_id: String, role_id: String) -> Array:
	var result := []
	for talent_id in owned(game, char_id):
		var t := Content.get_entry("talents", talent_id)
		if (t.get("rare", false) or t.get("role", "") == role_id) and t.get("grants_ability", "") != "":
			result.append(t.grants_ability)
	return result
