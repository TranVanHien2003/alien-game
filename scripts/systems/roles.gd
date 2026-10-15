class_name Roles
extends RefCounted
## Vai trò của thành viên (data/roles): quyết định loại vũ khí/công cụ được dùng, chỉ số cộng thêm và kỹ năng chủ động.


## Vai đang dùng (vai chính) — một thành viên có thể sở hữu nhiều vai (crew[id].roles).
static func role_of(char_id: String) -> String:
	var active: String = Game.crew.get(char_id, {}).get("active_role", "")
	if active != "":
		return active
	return Content.get_entry("characters", char_id).get("role", "soldier")


static func data_of(char_id: String) -> Dictionary:
	return Content.get_entry("roles", role_of(char_id))


static func name_of(role_id: String) -> String:
	return Content.get_entry("roles", role_id).get("name", role_id)


static func color_of(role_id: String) -> Color:
	return Color(Content.get_entry("roles", role_id).get("color", "#FFFFFF"))


## Thành viên có được phép dùng vật phẩm này không (theo loại vũ khí/công cụ của vai trò).
static func can_use(char_id: String, item_id: String) -> bool:
	var item := Content.get_entry("items", item_id)
	var role := data_of(char_id)
	match item.get("category", ""):
		"weapon":
			return item.get("weapon", {}).get("type", "") in role.get("weapon_types", [])
		"tool":
			return item.get("tool", {}).get("type", "") in role.get("tool_types", [])
		"module":
			return true
	return false


## [{role, need, have}] — so sánh đội đang chọn với vai trò đề cử của nhiệm vụ.
static func recommendation(mission: Dictionary, team: Array) -> Array:
	var counts := {}
	for char_id in team:
		counts[role_of(char_id)] = int(counts.get(role_of(char_id), 0)) + 1
	var result := []
	var rec: Dictionary = mission.get("recommended_roles", {})
	for role_id in rec:
		result.append({"role": role_id, "need": int(rec[role_id]), "have": int(counts.get(role_id, 0))})
	return result


static func recommendation_met(mission: Dictionary, team: Array) -> bool:
	return recommendation(mission, team).all(func(r): return r.have >= r.need)


## Trang bị mặc định theo vai trò, chỉ lấy những gì còn trong kho.
static func auto_equip(game: Node, char_id: String) -> void:
	if not Content.get_entry("characters", char_id).get("assignable", true) or Game.crew.get(char_id, {}).get("roles", [null]).is_empty():
		return
	var role := data_of(char_id)
	for pair in [["weapon", role.get("default_weapon", "")], ["tool", role.get("default_tool", "")]]:
		var slot: String = pair[0]
		if Inventory.equipped(game, char_id, slot) != "":
			continue
		var wanted: String = pair[1]
		if wanted != "" and Inventory.available(game, wanted) > 0:
			Inventory.equip_member(game, char_id, slot, wanted)
			continue
		# Không có đồ mặc định: lấy món đầu tiên còn trong kho mà vai trò dùng được
		for item_id in Inventory.items_in(game, slot):
			if can_use(char_id, item_id) and Inventory.available(game, item_id) > 0:
				Inventory.equip_member(game, char_id, slot, item_id)
				break
