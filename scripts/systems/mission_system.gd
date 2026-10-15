class_name MissionSystem
extends RefCounted
## Nhiệm vụ: liệt kê nhiệm vụ khả dụng, tính tỉ lệ thành công, giao đội (tự động hoặc màn action),
## và xử lý kết quả: thưởng, kinh nghiệm, thành viên mất tích -> sinh nhiệm vụ giải cứu.
##
## "Một lượt giao nhiệm vụ" (entry) có dạng:
##   {mission, team: [ids], leader, location, target (id người cần cứu, hoặc ""), years_left}


## Danh sách nhiệm vụ có thể giao lúc này: [{mission, location, target}]
static func available(game: Node) -> Array:
	var result := []
	var busy := {}
	for entry in game.active_missions:
		busy["%s/%s" % [entry.mission, entry.target]] = true
	for mission in Content.all("missions"):
		if mission.get("rescue", false):
			for char_id in CrewSystem.missing_members(game):
				if not busy.has("%s/%s" % [mission.id, char_id]):
					result.append({"mission": mission, "location": game.crew[char_id].missing_at, "target": char_id})
			continue
		if busy.has("%s/" % mission.id):
			continue
		if not mission.get("repeatable", false) and game.completed_missions.has(mission.id):
			continue
		if not mission.get("location", "") in game.known_locations:
			continue
		if not EventRules.check(game, mission.get("conditions", {})):
			continue
		result.append({"mission": mission, "location": mission.location, "target": ""})
	return result


static func is_protected(game: Node, hazard: String, team: Array) -> bool:
	if ResearchSystem.protects(game, hazard):
		return true
	var def: Dictionary = Content.config.get("hazards", {}).get(hazard, {})
	var counter: String = def.get("countered_by_skill", "")
	return counter != "" and CrewSystem.team_skill(game, team, counter) >= int(def.get("counter_level", 1))


static func unprotected_hazards(game: Node, location_id: String, team: Array) -> Array:
	return Content.get_entry("locations", location_id).get("hazards", []) \
		.filter(func(h): return not is_protected(game, h, team))


## Tỉ lệ thành công khi gửi đội tự động (0..1).
static func chance(game: Node, mission: Dictionary, team: Array, location_id: String) -> float:
	var cfg: Dictionary = Content.config.get("missions", {})
	var p := float(mission.get("base_chance", 0.5)) + ResearchSystem.mission_bonus(game)
	for skill_id in mission.get("skills", {}):
		var diff := CrewSystem.team_skill(game, team, skill_id) - int(mission.skills[skill_id])
		p += diff * float(cfg.get("skill_weight", 0.08))
	var best_command := 0
	for char_id in team:
		best_command = maxi(best_command, CrewSystem.skill(game, char_id, "command"))
	p += best_command * float(cfg.get("command_bonus_per_level", 0.02))
	for hazard in unprotected_hazards(game, location_id, team):
		p -= float(Content.config.hazards[hazard].get("penalty", 0.2))
	return clampf(p, float(cfg.get("min_chance", 0.05)), float(cfg.get("max_chance", 0.95)))


static func valid_team(game: Node, mission: Dictionary, team: Array) -> bool:
	var size: Array = mission.get("team_size", [1, 1])
	if team.size() < int(size[0]) or team.size() > int(size[1]):
		return false
	var free := CrewSystem.available(game)
	return team.all(func(id): return id in free)


static func launch_auto(game: Node, option: Dictionary, team: Array) -> bool:
	if not valid_team(game, option.mission, team):
		return false
	var entry := _make_entry(game, option, team, team[0])
	entry.years_left = int(option.mission.get("duration", 1))
	game.active_missions.append(entry)
	game.add_log("🚀 Đội %s lên đường: %s." % [_team_names(team), option.mission.name])
	return true


## Bắt đầu màn action. Màn chơi đọc game.action_mission và gọi finish_action() khi xong.
static func start_action(game: Node, option: Dictionary, team: Array, leader: String) -> bool:
	if option.mission.get("auto_only", false) or not valid_team(game, option.mission, team) or not leader in team:
		return false
	game.action_mission = _make_entry(game, option, team, leader)
	return true


static func finish_action(game: Node, success: bool, leader_down: bool) -> Dictionary:
	var entry: Dictionary = game.action_mission
	if entry.is_empty():
		return {}
	game.action_mission = {}
	var missing := []
	if leader_down and float(Content.get_entry("missions", entry.mission).get("missing_chance", 0.0)) > 0.0:
		missing.append(entry.leader)
	return resolve(game, entry, success, missing)


static func tick_year(game: Node) -> void:
	for entry in game.active_missions.duplicate():
		entry.years_left = int(entry.years_left) - 1
		if entry.years_left > 0:
			continue
		game.active_missions.erase(entry)
		var mission := Content.get_entry("missions", entry.mission)
		var success: bool = game.rng.randf() < chance(game, mission, entry.team, entry.location)
		var missing := []
		if not success:
			for char_id in entry.team:
				if game.rng.randf() < float(mission.get("missing_chance", 0.0)):
					missing.append(char_id)
		resolve(game, entry, success, missing)


static func resolve(game: Node, entry: Dictionary, success: bool, missing: Array) -> Dictionary:
	var mission := Content.get_entry("missions", entry.mission)
	for char_id in entry.team:
		if game.crew.has(char_id):
			game.crew[char_id].status = CrewSystem.IDLE
			CrewSystem.gain_xp(game, char_id, mission.get("skills", {}).keys(), 2 if success else 1)
	var title: String = mission.get("name", entry.mission)
	if entry.target != "":
		title += " " + CrewSystem.display_name(entry.target)
	game.add_log("%s %s: %s" % ["✔" if success else "✘", title, "THÀNH CÔNG" if success else "THẤT BẠI"])
	EventRules.apply(game, mission.get("success" if success else "failure", {}))
	if success:
		game.completed_missions[entry.mission] = int(game.completed_missions.get(entry.mission, 0)) + 1
		if entry.target != "":
			CrewSystem.rescue(game, entry.target)
	for char_id in missing:
		CrewSystem.set_missing(game, char_id, entry.location)
	var report := {"title": title, "success": success, "missing": missing}
	game.mission_resolved.emit(report)
	game.state_changed.emit()
	return report


static func _make_entry(game: Node, option: Dictionary, team: Array, leader: String) -> Dictionary:
	for char_id in team:
		game.crew[char_id].status = CrewSystem.MISSION
	return {
		"mission": option.mission.id,
		"team": team.duplicate(),
		"leader": leader,
		"location": option.location,
		"target": option.target,
		"years_left": 0,
	}


static func _team_names(team: Array) -> String:
	return ", ".join(team.map(func(id): return CrewSystem.display_name(id)))
