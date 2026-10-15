class_name CombatStats
extends RefCounted
## Tính bộ chỉ số chiến đấu cho đội trưởng trong màn action.
## Công thức: base (config.combat_stats)
##          + kỹ năng đội trưởng × config.skill_bonuses
##          + kỹ năng các thành viên khác × skill_bonuses × team_bonus_share
##          + module đang trang bị (items[].modifiers)
##          + công nghệ đã nghiên cứu (tech[].combat_modifiers)
## Buff tạm thời (thuốc, kỹ năng) được Player cộng thêm khi đang chơi.


static func compute(game: Node, leader: String, team: Array) -> Dictionary:
	var cfg: Dictionary = Content.config
	var result := {}
	for stat in cfg.get("combat_stats", {}):
		result[stat] = float(cfg.combat_stats[stat].get("base", 0.0))

	var share := float(cfg.get("player", {}).get("team_bonus_share", 0.25))
	for char_id in team:
		var weight := 1.0 if char_id == leader else share
		for skill_id in cfg.get("skill_bonuses", {}):
			var level := CrewSystem.skill(game, char_id, skill_id)
			if level > 0:
				_add(result, cfg.skill_bonuses[skill_id], level * weight)

	for item_id in game.loadout.get("modules", []):
		_add(result, Content.get_entry("items", item_id).get("modifiers", {}), 1.0)
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
