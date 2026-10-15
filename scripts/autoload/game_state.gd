extends Node
## Trạng thái một ván chơi + vòng lặp "qua một năm" trên tàu (hub).
## Logic chi tiết nằm trong scripts/systems/*; file này giữ dữ liệu và điều phối.
## Mọi dữ liệu cần lưu đều nằm trong to_dict()/from_dict() để SaveManager xử lý.

signal state_changed
signal log_added(entry: Dictionary)
signal event_started(event: Dictionary)
signal mission_resolved(report: Dictionary)
signal game_ended(ending: Dictionary)
signal chapter_completed(chapter: Dictionary)

const MAX_LOG := 200

var year: int = 0
var generation: int = 1
var chapter_id: String = ""
var stats: Dictionary = {}
var flags: Dictionary = {}
var items: Dictionary = {}
## id -> {skills, xp, status, ...} (xem CrewSystem)
var crew: Dictionary = {}
var techs: Array = []
var research_current: String = ""
var research_progress: Dictionary = {}
var research_bank: float = 0.0
var known_locations: Array = []
var active_missions: Array = []
var completed_missions: Dictionary = {}
## Trang bị mang theo khi đổ bộ (xem Inventory)
var loadout: Dictionary = Inventory.default_loadout()
## Nhiệm vụ đang chơi ở màn action (rỗng nếu đang ở hub)
var action_mission: Dictionary = {}
var seen_events: Dictionary = {}
var log_entries: Array = []
var pending_event: String = ""
var ending_id: String = ""
var chapter_done: bool = false
var rng := RandomNumberGenerator.new()


# --- Khởi tạo -----------------------------------------------------------------

func new_game(seed_value: int = -1) -> void:
	var cfg := Content.config
	chapter_id = cfg.get("start_chapter", "")
	var chapter := current_chapter()
	year = int(chapter.get("start_year", 0))
	generation = int(chapter.get("generation", 1))
	stats = {}
	for stat in Content.stat_ids():
		stats[stat] = float(cfg.stats[stat].get("start", 0))
	flags = {}
	for flag in chapter.get("starting_flags", []):
		flags[flag] = true
	items = {}
	for item_id in chapter.get("starting_items", {}):
		items[item_id] = int(chapter.starting_items[item_id])
	loadout = Inventory.default_loadout()
	loadout.merge(chapter.get("starting_loadout", {}).duplicate(true), true)
	crew = {}
	for char_id in chapter.get("starting_characters", []):
		CrewSystem.add_member(self, char_id)
	Inventory.sanitize(self)
	techs = []
	research_current = ""
	research_progress = {}
	research_bank = 0.0
	known_locations = Content.all("locations").filter(func(l): return l.get("known", false)).map(func(l): return l.id)
	active_missions = []
	completed_missions = {}
	action_mission = {}
	seen_events = {}
	log_entries = []
	pending_event = ""
	ending_id = ""
	chapter_done = false
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	add_log(chapter.get("title", ""))
	state_changed.emit()
	_try_start_event()


func current_chapter() -> Dictionary:
	return Content.get_entry("chapters", chapter_id)


func is_over() -> bool:
	return ending_id != "" or chapter_done


# --- Truy vấn / thay đổi đơn giản ----------------------------------------------

func get_stat(stat: String) -> float:
	return stats.get(stat, 0.0)


func change_stat(stat: String, delta: float) -> void:
	var def: Dictionary = Content.config.get("stats", {}).get(stat, {})
	stats[stat] = clampf(get_stat(stat) + delta, def.get("min", 0.0), def.get("max", 100.0))


func has_flag(flag: String) -> bool:
	return flags.get(flag, false)


func item_count(item_id: String) -> int:
	return int(items.get(item_id, 0))


func add_item(item_id: String, amount: int) -> void:
	var n := item_count(item_id) + amount
	if n > 0:
		items[item_id] = n
	else:
		items.erase(item_id)


func crew_status(char_id: String) -> String:
	return crew.get(char_id, {}).get("status", "")


## Còn sống và đang ở trên tàu hoặc đang làm nhiệm vụ (không mất tích).
func is_present(char_id: String) -> bool:
	return crew.has(char_id) and crew[char_id].status != CrewSystem.MISSING


func character_age(char_id: String) -> int:
	return year - int(Content.get_entry("characters", char_id).get("birth_year", year))


func discover_location(loc_id: String) -> void:
	if loc_id in known_locations or not Content.has_entry("locations", loc_id):
		return
	known_locations.append(loc_id)
	add_log("🛰 Khám phá địa điểm mới: " + Content.get_entry("locations", loc_id).get("name", loc_id))


func add_log(text: String) -> void:
	if text.is_empty():
		return
	var entry := {"year": year, "text": text}
	log_entries.append(entry)
	if log_entries.size() > MAX_LOG:
		log_entries.pop_front()
	log_added.emit(entry)


# --- Vòng lặp năm -------------------------------------------------------------

func can_advance() -> bool:
	return pending_event == "" and action_mission.is_empty() and not is_over()


## Trả về false nếu không thể qua năm (đang chờ lựa chọn, đang ở màn action, hoặc ván đã kết thúc).
func advance_year() -> bool:
	if not can_advance():
		return false
	year += int(Content.config.get("years_per_turn", 1))
	var chapter := current_chapter()
	var gen_len := int(Content.config.get("generation_length_years", 25))
	generation = int(chapter.get("generation", 1)) + (year - int(chapter.get("start_year", 0))) / gen_len

	Simulation.run_year(self)
	ResearchSystem.tick_year(self)
	MissionSystem.tick_year(self)
	CrewSystem.tick_year(self)
	if check_failures():
		return true
	if year >= int(chapter.get("end_year", 1 << 30)):
		chapter_done = true
		state_changed.emit()
		chapter_completed.emit(chapter)
		return true
	state_changed.emit()
	_try_start_event()
	return true


func get_pending_event() -> Dictionary:
	return Content.get_entry("events", pending_event)


## Danh sách lựa chọn hiện có của sự kiện: [{index, choice}]
func available_choices(event: Dictionary) -> Array:
	var result := []
	var choices: Array = event.get("choices", [])
	for i in choices.size():
		if EventRules.check(self, choices[i].get("conditions", {})):
			result.append({"index": i, "choice": choices[i]})
	return result


func choose(index: int) -> void:
	var event := get_pending_event()
	var choices: Array = event.get("choices", [])
	if event.is_empty() or index < 0 or index >= choices.size():
		return
	var effects: Dictionary = choices[index].get("effects", {})
	pending_event = ""
	EventRules.apply(self, effects)
	state_changed.emit()
	if check_failures():
		return
	if effects.has("next_event"):
		_start_event(effects.next_event)


func _try_start_event() -> void:
	var event := EventPicker.pick(self)
	if not event.is_empty():
		_start_event(event.id)


func _start_event(event_id: String) -> void:
	var event := Content.get_entry("events", event_id)
	if event.is_empty():
		return
	pending_event = event_id
	seen_events[event_id] = int(seen_events.get(event_id, 0)) + 1
	add_log("Sự kiện: " + event.get("title", event_id))
	event_started.emit(event)


func check_failures() -> bool:
	if ending_id != "":
		return true
	for failure in Content.config.get("failures", []):
		if get_stat(failure.stat) <= float(failure.at_or_below):
			ending_id = failure.ending
			pending_event = ""
			var ending := Content.get_entry("endings", ending_id)
			add_log("KẾT THÚC: " + ending.get("title", ending_id))
			state_changed.emit()
			game_ended.emit(ending)
			return true
	return false


# --- Lưu / nạp ----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"year": year,
		"generation": generation,
		"chapter_id": chapter_id,
		"stats": stats.duplicate(),
		"flags": flags.duplicate(),
		"items": items.duplicate(),
		"crew": crew.duplicate(true),
		"loadout": loadout.duplicate(true),
		"techs": techs.duplicate(),
		"research_current": research_current,
		"research_progress": research_progress.duplicate(),
		"research_bank": research_bank,
		"known_locations": known_locations.duplicate(),
		"active_missions": active_missions.duplicate(true),
		"completed_missions": completed_missions.duplicate(),
		"seen_events": seen_events.duplicate(),
		"log": log_entries.duplicate(true),
		"pending_event": pending_event,
		"ending_id": ending_id,
		"chapter_done": chapter_done,
		# Lưu dạng chuỗi vì JSON làm mất độ chính xác của số nguyên 64-bit
		"rng_seed": str(rng.seed),
		"rng_state": str(rng.state),
	}


func from_dict(data: Dictionary) -> void:
	year = int(data.get("year", 0))
	generation = int(data.get("generation", 1))
	chapter_id = data.get("chapter_id", Content.config.get("start_chapter", ""))
	stats = {}
	for stat in Content.stat_ids():
		stats[stat] = float(data.get("stats", {}).get(stat, Content.config.stats[stat].get("start", 0)))
	flags = data.get("flags", {})
	items = {}
	for item_id in data.get("items", {}):
		items[item_id] = int(data.items[item_id])
	crew = data.get("crew", {})
	loadout = Inventory.default_loadout()
	loadout.merge(data.get("loadout", {}), true)
	techs = data.get("techs", [])
	research_current = data.get("research_current", "")
	research_progress = data.get("research_progress", {})
	research_bank = float(data.get("research_bank", 0.0))
	known_locations = data.get("known_locations", [])
	active_missions = data.get("active_missions", [])
	completed_missions = data.get("completed_missions", {})
	action_mission = {}
	seen_events = data.get("seen_events", {})
	log_entries = data.get("log", [])
	pending_event = data.get("pending_event", "")
	ending_id = data.get("ending_id", "")
	chapter_done = data.get("chapter_done", false)
	rng.seed = int(data.get("rng_seed", "0"))
	rng.state = int(data.get("rng_state", "0"))
	_sanitize()
	state_changed.emit()


## Bản cập nhật mới có thể xóa/đổi nội dung — bỏ các tham chiếu không còn tồn tại
## để save cũ vẫn chơi tiếp được.
func _sanitize() -> void:
	for char_id in crew.keys():
		if not Content.has_entry("characters", char_id):
			crew.erase(char_id)
		elif crew[char_id].get("status", "") == CrewSystem.MISSION \
				and not active_missions.any(func(m): return char_id in m.team):
			# Save giữa màn action: coi như đội đã quay về
			crew[char_id].status = CrewSystem.IDLE
	for key in ["skills", "xp"]:
		for char_id in crew:
			crew[char_id][key] = crew[char_id].get(key, {})
			for skill_id in crew[char_id][key]:
				crew[char_id][key][skill_id] = int(crew[char_id][key][skill_id])
	items = items.duplicate()
	for item_id in items.keys():
		if not Content.has_entry("items", item_id):
			items.erase(item_id)
	Inventory.sanitize(self)
	for char_id in crew:
		Roles.auto_equip(self, char_id)
	techs = techs.filter(func(id): return Content.has_entry("tech", id))
	known_locations = known_locations.filter(func(id): return Content.has_entry("locations", id))
	active_missions = active_missions.filter(func(m): return Content.has_entry("missions", m.get("mission", "")))
	if research_current != "" and not Content.has_entry("tech", research_current):
		research_current = ""
	if pending_event != "" and not Content.has_entry("events", pending_event):
		pending_event = ""
