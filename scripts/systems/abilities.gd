class_name Abilities
extends RefCounted
## Kỹ năng chủ động trong màn action (phím Q / R).
## Nguồn: kỹ năng nhân vật đạt cấp yêu cầu (abilities[].requires) hoặc module trang bị (grants_abilities).

const MAX_ACTIVE := 2


static func for_leader(game: Node, leader: String) -> Array:
	var result := []
	for item_id in game.loadout.get("modules", []):
		for ability_id in Content.get_entry("items", item_id).get("grants_abilities", []):
			if not ability_id in result:
				result.append(ability_id)
	for ability in Content.all("abilities"):
		var req: Dictionary = ability.get("requires", {})
		if req.has("skill") and CrewSystem.skill(game, leader, req.skill) >= int(req.get("level", 1)) and not ability.id in result:
			result.append(ability.id)
	return result.slice(0, MAX_ACTIVE)
