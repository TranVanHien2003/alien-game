class_name ResearchSystem
extends RefCounted
## Cây công nghệ: tích điểm nghiên cứu mỗi năm, mở khóa công nghệ và tổng hợp các bonus thụ động.


static func points_per_year(game: Node) -> float:
	var cfg: Dictionary = Content.config.get("research", {})
	var skill_id: String = cfg.get("skill", "science")
	var points := float(cfg.get("base_points", 2))
	for char_id in game.crew:
		if game.crew[char_id].status == CrewSystem.IDLE:
			points += CrewSystem.skill(game, char_id, skill_id) * float(cfg.get("points_per_level", 0.5))
	for tech_id in game.techs:
		points += float(Content.get_entry("tech", tech_id).get("research_bonus", 0))
	return points


static func can_research(game: Node, tech_id: String) -> bool:
	if tech_id in game.techs:
		return false
	for req in Content.get_entry("tech", tech_id).get("requires", []):
		if not req in game.techs:
			return false
	return true


static func available(game: Node) -> Array:
	return Content.ids("tech").filter(func(id): return can_research(game, id))


static func set_project(game: Node, tech_id: String) -> void:
	if tech_id == "" or can_research(game, tech_id):
		game.research_current = tech_id
		if game.research_bank > 0.0 and tech_id != "":
			var banked: float = game.research_bank
			game.research_bank = 0.0
			add_points(game, banked)


static func progress(game: Node, tech_id: String) -> float:
	return float(game.research_progress.get(tech_id, 0.0))


static func add_points(game: Node, points: float) -> void:
	if game.research_current == "":
		game.research_bank += points
		return
	var tech_id: String = game.research_current
	var total := progress(game, tech_id) + points
	var cost := float(Content.get_entry("tech", tech_id).get("cost", 10))
	if total >= cost:
		game.research_progress.erase(tech_id)
		game.research_current = ""
		unlock(game, tech_id)
		# Điểm dư được giữ lại cho dự án tiếp theo
		game.research_bank += total - cost
	else:
		game.research_progress[tech_id] = total


static func unlock(game: Node, tech_id: String) -> void:
	if tech_id in game.techs:
		return
	var tech := Content.get_entry("tech", tech_id)
	game.techs.append(tech_id)
	game.add_log("🔬 Nghiên cứu hoàn tất: " + tech.get("name", tech_id))
	EventRules.apply(game, tech.get("effects", {}))


static func tick_year(game: Node) -> void:
	add_points(game, points_per_year(game))


# --- Bonus thụ động từ công nghệ đã mở -----------------------------------------

static func yearly_bonus(game: Node, stat: String) -> float:
	var total := 0.0
	for tech_id in game.techs:
		total += float(Content.get_entry("tech", tech_id).get("yearly", {}).get(stat, 0.0))
	return total


static func mission_bonus(game: Node) -> float:
	var total := 0.0
	for tech_id in game.techs:
		total += float(Content.get_entry("tech", tech_id).get("mission_bonus", 0.0))
	return total


static func protects(game: Node, hazard: String) -> bool:
	for tech_id in game.techs:
		if hazard in Content.get_entry("tech", tech_id).get("protects", []):
			return true
	return false
