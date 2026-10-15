class_name CrewSystem
extends RefCounted
## Phi hành đoàn: kỹ năng, kinh nghiệm, huấn luyện kỹ năng công nghệ cao, mất tích và tuổi thọ.
## Trạng thái runtime nằm trong game.crew[id] = {skills, xp, status, ...}; dữ liệu gốc ở data/characters.

const IDLE := "idle"
const MISSION := "mission"
const MISSING := "missing"
const TRAINING := "training"


static func add_member(game: Node, char_id: String) -> void:
	if game.crew.has(char_id):
		return
	var data := Content.get_entry("characters", char_id)
	var skills := {}
	for skill_id in data.get("skills", {}):
		skills[skill_id] = int(data.skills[skill_id])
	game.crew[char_id] = {
		"skills": skills,
		"xp": {},
		"status": IDLE,
		"equipment": {},
	}
	Roles.auto_equip(game, char_id)


static func skill(game: Node, char_id: String, skill_id: String) -> int:
	return int(game.crew.get(char_id, {}).get("skills", {}).get(skill_id, 0))


static func team_skill(game: Node, team: Array, skill_id: String) -> int:
	var total := 0
	for char_id in team:
		total += skill(game, char_id, skill_id)
	return total


## Thành viên có thể được giao việc (nhiệm vụ / huấn luyện) ngay lúc này.
static func available(game: Node) -> Array:
	var min_age := int(Content.config.get("crew", {}).get("min_mission_age", 16))
	return game.crew.keys().filter(func(id):
		var data := Content.get_entry("characters", id)
		return game.crew[id].status == IDLE \
			and data.get("assignable", true) \
			and (data.get("ageless", false) or game.character_age(id) >= min_age))


static func gain_xp(game: Node, char_id: String, skill_ids: Array, amount: int = 1) -> void:
	var cfg: Dictionary = Content.config.get("crew", {})
	var per_level := int(cfg.get("xp_per_level", 3))
	var max_level := int(cfg.get("max_skill_level", 10))
	var member: Dictionary = game.crew.get(char_id, {})
	if member.is_empty():
		return
	for skill_id in skill_ids:
		var xp := int(member.xp.get(skill_id, 0)) + amount
		var level := int(member.skills.get(skill_id, 0))
		while xp >= per_level and level < max_level:
			xp -= per_level
			level += 1
			game.add_log("%s đạt %s cấp %d." % [display_name(char_id), Content.get_entry("skills", skill_id).get("name", skill_id), level])
		member.xp[skill_id] = xp
		member.skills[skill_id] = level


## Kỹ năng công nghệ cao mà thành viên có thể học (đã mở khóa bằng nghiên cứu, chưa biết).
static func trainable_skills(game: Node, char_id: String) -> Array:
	return Content.all("skills").filter(func(s):
		return s.get("high_tech", false) \
			and s.get("requires_tech", "") in game.techs \
			and skill(game, char_id, s.id) == 0) \
		.map(func(s): return s.id)


static func start_training(game: Node, char_id: String, skill_id: String) -> bool:
	if not char_id in available(game) or not skill_id in trainable_skills(game, char_id):
		return false
	var member: Dictionary = game.crew[char_id]
	member.status = TRAINING
	member.training = skill_id
	member.training_left = int(Content.config.get("crew", {}).get("training_years", 1))
	game.add_log("%s bắt đầu huấn luyện %s." % [display_name(char_id), Content.get_entry("skills", skill_id).get("name", skill_id)])
	return true


static func set_missing(game: Node, char_id: String, location_id: String) -> void:
	var member: Dictionary = game.crew.get(char_id, {})
	if member.is_empty():
		return
	member.status = MISSING
	member.missing_at = location_id
	member.missing_since = game.year
	game.add_log("⚠ %s mất tích tại %s!" % [display_name(char_id), Content.get_entry("locations", location_id).get("name", location_id)])


static func rescue(game: Node, char_id: String) -> void:
	var member: Dictionary = game.crew.get(char_id, {})
	if member.get("status", "") != MISSING:
		return
	member.status = IDLE
	member.erase("missing_at")
	member.erase("missing_since")
	game.add_log("%s đã được đưa về tàu an toàn." % display_name(char_id))


static func missing_members(game: Node) -> Array:
	return game.crew.keys().filter(func(id): return game.crew[id].status == MISSING)


static func years_left_to_rescue(game: Node, char_id: String) -> int:
	var window := int(Content.config.get("crew", {}).get("missing_survival_years", 5))
	return window - (game.year - int(game.crew[char_id].get("missing_since", game.year)))


static func tick_year(game: Node) -> void:
	var lifespan: Dictionary = Content.config.get("lifespan", {})
	var min_age := int(lifespan.get("min_death_age", 70))
	var death_chance := float(lifespan.get("yearly_death_chance", 0.08))
	for char_id in game.crew.keys():
		var member: Dictionary = game.crew[char_id]
		var data := Content.get_entry("characters", char_id)
		match member.status:
			TRAINING:
				member.training_left = int(member.get("training_left", 1)) - 1
				if member.training_left <= 0:
					member.skills[member.training] = 1
					game.add_log("%s đã thành thạo %s." % [display_name(char_id), Content.get_entry("skills", member.training).get("name", "")])
					member.status = IDLE
					member.erase("training")
					member.erase("training_left")
			MISSING:
				if years_left_to_rescue(game, char_id) <= 0:
					game.crew.erase(char_id)
					game.add_log("✝ Không còn hy vọng tìm thấy %s." % data.get("name", char_id))
					continue
		if not data.get("ageless", false) and game.character_age(char_id) >= min_age and game.rng.randf() < death_chance:
			game.crew.erase(char_id)
			game.add_log("✝ %s (%s) đã qua đời ở tuổi %d." % [data.get("name", char_id), data.get("title", ""), game.character_age(char_id)])


static func display_name(char_id: String) -> String:
	return Content.get_entry("characters", char_id).get("name", char_id)
