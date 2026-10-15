class_name CombatStats
extends RefCounted
## Bộ chỉ số chiến đấu của MỘT thành viên trên bản đồ.
## Công thức: base (config.combat_stats)
##          + vai trò (roles[].modifiers)
##          + kỹ năng × config.skill_bonuses
##          + module / công cụ đang trang bị (items[].modifiers)
##          + công nghệ đã nghiên cứu (tech[].combat_modifiers)
## Buff tạm thời (thuốc, kỹ năng) được Unit cộng thêm khi đang chơi.


static func compute(game: Node, char_id: String) -> Dictionary:
	var cfg: Dictionary = Content.config
	var result := {}
	for stat in cfg.get("combat_stats", {}):
		result[stat] = float(cfg.combat_stats[stat].get("base", 0.0))
	_add(result, Roles.data_of(char_id).get("modifiers", {}), 1.0)
	for skill_id in cfg.get("skill_bonuses", {}):
		var level := CrewSystem.skill(game, char_id, skill_id)
		if level > 0:
			_add(result, cfg.skill_bonuses[skill_id], level)
	for slot in ["tool", "module"]:
		_add(result, Content.get_entry("items", Inventory.equipped(game, char_id, slot)).get("modifiers", {}), 1.0)
	for tech_id in game.techs:
		_add(result, Content.get_entry("tech", tech_id).get("combat_modifiers", {}), 1.0)
	return clamp_stats(result)


static func clamp_stats(stats: Dictionary) -> Dictionary:
	for stat in Content.config.get("combat_stats", {}):
		var def: Dictionary = Content.config.combat_stats[stat]
		if def.has("min"):
			stats[stat] = maxf(float(stats.get(stat, 0.0)), float(def.min))
	stats["crit_chance"] = clampf(float(stats.get("crit_chance", 0.0)), 0.0, 1.0)
	return stats


static func format(stat: String, value: float) -> String:
	var def: Dictionary = Content.config.get("combat_stats", {}).get(stat, {})
	if def.get("format", "") == "pct":
		return "%d%%" % roundi(value * 100.0)
	return str(snappedf(value, 0.1))


static func _add(target: Dictionary, mods: Dictionary, scale: float) -> void:
	for stat in mods:
		target[stat] = float(target.get(stat, 0.0)) + float(mods[stat]) * scale
