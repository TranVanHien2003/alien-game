class_name Abilities
extends RefCounted
## Kỹ năng chủ động của một thành viên trên bản đồ (phím Q / E / R cho thành viên đang chọn).
## Nguồn: vai trò (roles[].abilities), kỹ năng nhân vật đạt cấp yêu cầu (abilities[].requires), module (grants_abilities).

const MAX_ACTIVE := 3


static func for_unit(game: Node, char_id: String) -> Array:
	var result: Array = Roles.data_of(char_id).get("abilities", []).duplicate()
	for ability_id in Talents.abilities(game, char_id, Roles.role_of(char_id)):
		if not ability_id in result:
			result.append(ability_id)
	var module_id := Inventory.equipped(game, char_id, "module")
	for ability_id in Content.get_entry("items", module_id).get("grants_abilities", []):
		if not ability_id in result:
			result.append(ability_id)
	for ability in Content.all("abilities"):
		var req: Dictionary = ability.get("requires", {})
		if req.has("skill") and CrewSystem.skill(game, char_id, req.skill) >= int(req.get("level", 1)) and not ability.id in result:
			result.append(ability.id)
	return result.filter(func(id): return Content.has_entry("abilities", id)).slice(0, MAX_ACTIVE)
