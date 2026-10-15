extends Node
## Kho nội dung của game, nạp toàn bộ từ JSON (không hard-code trong script).
##
## Nguồn nạp theo thứ tự (nguồn sau ghi đè nguồn trước theo `id`):
##   1. res://data/<category>/*.json        (nội dung gốc)
##   2. user://mods/<tên mod>/<category>/*.json  (mod của người chơi)
##
## Mỗi file trong category là một mảng các object có trường "id".
## Riêng category "config" là các object được merge lại thành một Dictionary.

signal reloaded

const DATA_ROOT := "res://data"
const MODS_ROOT := "user://mods"
const CATEGORIES: Array[String] = [
	"chapters", "characters", "events", "dialogues", "items", "endings",
	"skills", "tech", "locations", "missions", "levels", "enemies",
	"abilities", "loot", "recipes", "resource_nodes",
]
const ITEM_CATEGORIES := ["material", "consumable", "module", "weapon", "key"]
const OBJECTIVE_TYPES := ["collect", "interact", "rescue", "mine", "boss"]

var config: Dictionary = {}
## category -> { id -> Dictionary }
var _db: Dictionary = {}
## Nguồn file của từng entry, giúp báo lỗi rõ ràng: "category/id" -> path
var _sources: Dictionary = {}
var errors: PackedStringArray = []
var loaded_mods: PackedStringArray = []


func _ready() -> void:
	reload()


func reload() -> void:
	config = {}
	_db = {}
	_sources = {}
	errors = []
	loaded_mods = []
	for category in CATEGORIES:
		_db[category] = {}

	_load_root(DATA_ROOT)
	if DirAccess.dir_exists_absolute(MODS_ROOT):
		for mod_name in DirAccess.get_directories_at(MODS_ROOT):
			_load_root(MODS_ROOT.path_join(mod_name))
			loaded_mods.append(mod_name)

	errors.append_array(validate())
	for err in errors:
		push_error("[Content] " + err)
	reloaded.emit()


func get_entry(category: String, id: String) -> Dictionary:
	return _db.get(category, {}).get(id, {})


func has_entry(category: String, id: String) -> bool:
	return _db.get(category, {}).has(id)


func all(category: String) -> Array:
	return _db.get(category, {}).values()


func ids(category: String) -> Array:
	return _db.get(category, {}).keys()


func stat_ids() -> Array:
	return config.get("stats", {}).keys()


func stat_label(stat: String) -> String:
	return config.get("stats", {}).get(stat, {}).get("label", stat)


# --- Nạp file -----------------------------------------------------------------

func _load_root(root: String) -> void:
	for path in _json_files(root.path_join("config")):
		var data = _read_json(path)
		if data is Dictionary:
			config.merge(data, true)
		elif data != null:
			errors.append("%s: config phải là object" % path)

	for category in CATEGORIES:
		for path in _json_files(root.path_join(category)):
			var data = _read_json(path)
			if data == null:
				continue
			if not data is Array:
				errors.append("%s: phải là mảng các object" % path)
				continue
			for entry in data:
				if not entry is Dictionary or not entry.has("id"):
					errors.append("%s: entry thiếu trường 'id'" % path)
					continue
				_db[category][entry.id] = entry
				_sources["%s/%s" % [category, entry.id]] = path


func _json_files(dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(dir):
		return result
	for file in DirAccess.get_files_at(dir):
		# Bản export có thể đổi tên file thành *.json.remap — bỏ qua phần đuôi đó
		file = file.trim_suffix(".remap")
		if file.get_extension() == "json":
			result.append(dir.path_join(file))
	result.sort()
	return result


func _read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("%s: không đọc được file" % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


# --- Kiểm tra tham chiếu ----------------------------------------------------------

## Trả về danh sách lỗi nội dung (tham chiếu sai id, thiếu trường...).
## Được gọi trong test và CI để nội dung hỏng không bao giờ lên production.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	var stats := stat_ids()
	if stats.is_empty():
		problems.append("config: thiếu 'stats'")
	if not has_entry("chapters", config.get("start_chapter", "")):
		problems.append("config: start_chapter '%s' không tồn tại" % config.get("start_chapter", ""))

	for chapter in all("chapters"):
		var where := _where("chapters", chapter.id)
		for char_id in chapter.get("starting_characters", []):
			_check_ref(problems, where, "characters", char_id)
		for item_id in chapter.get("starting_items", {}):
			_check_ref(problems, where, "items", item_id)

	for failure in config.get("failures", []):
		_check_ref(problems, "config.failures", "endings", failure.get("ending", ""))
		if not failure.get("stat", "") in stats:
			problems.append("config.failures: stat '%s' không tồn tại" % failure.get("stat", ""))

	var hazards: Array = config.get("hazards", {}).keys()
	for skill in all("skills"):
		if skill.has("requires_tech"):
			_check_ref(problems, _where("skills", skill.id), "tech", skill.requires_tech)
	for character in all("characters"):
		for skill_id in character.get("skills", {}):
			_check_ref(problems, _where("characters", character.id), "skills", skill_id)
	for tech in all("tech"):
		var where := _where("tech", tech.id)
		for req in tech.get("requires", []):
			_check_ref(problems, where, "tech", req)
		for skill_id in tech.get("unlocks_skills", []):
			_check_ref(problems, where, "skills", skill_id)
		for hazard in tech.get("protects", []):
			if not hazard in hazards:
				problems.append("%s: hazard '%s' không tồn tại" % [where, hazard])
		for stat in tech.get("yearly", {}):
			if not stat in stats:
				problems.append("%s: stat '%s' không tồn tại" % [where, stat])
		_check_effects(problems, where, tech.get("effects", {}), stats)
	for location in all("locations"):
		for hazard in location.get("hazards", []):
			if not hazard in hazards:
				problems.append("%s: hazard '%s' không tồn tại" % [_where("locations", location.id), hazard])
	for hazard in hazards:
		var counter: String = config.hazards[hazard].get("countered_by_skill", "")
		if counter != "":
			_check_ref(problems, "config.hazards." + hazard, "skills", counter)
	for enemy_ids in all("levels").map(func(l): return l.get("enemies", {}).keys()):
		for enemy_id in enemy_ids:
			_check_ref(problems, "levels", "enemies", enemy_id)
	var rescue_count := 0
	for mission in all("missions"):
		var where := _where("missions", mission.id)
		if mission.get("rescue", false):
			rescue_count += 1
		else:
			_check_ref(problems, where, "locations", mission.get("location", ""))
		for skill_id in mission.get("skills", {}):
			_check_ref(problems, where, "skills", skill_id)
		var size: Array = mission.get("team_size", [1, 1])
		if size.size() != 2 or size[0] < 1 or size[0] > size[1]:
			problems.append("%s: team_size phải là [min, max] hợp lệ" % where)
		if not mission.get("auto_only", false):
			var objective: Dictionary = mission.get("objective", {})
			if not objective.get("type", "") in OBJECTIVE_TYPES:
				problems.append("%s: objective.type phải là một trong %s" % [where, OBJECTIVE_TYPES])
			if objective.get("type", "") == "mine":
				_check_ref(problems, where, "items", objective.get("item", ""))
			if objective.get("type", "") == "boss":
				_check_ref(problems, where, "enemies", objective.get("boss", ""))
		_check_conditions(problems, where, mission.get("conditions", {}), stats)
		_check_effects(problems, where, mission.get("success", {}), stats)
		_check_effects(problems, where, mission.get("failure", {}), stats)
	if rescue_count != 1:
		problems.append("missions: cần đúng 1 nhiệm vụ mẫu có \"rescue\": true (hiện có %d)" % rescue_count)

	var combat_stats: Array = config.get("combat_stats", {}).keys()
	for skill_id in config.get("skill_bonuses", {}):
		_check_ref(problems, "config.skill_bonuses", "skills", skill_id)
		_check_stat_keys(problems, "config.skill_bonuses." + skill_id, config.skill_bonuses[skill_id], combat_stats)
	for item in all("items"):
		var where := _where("items", item.id)
		if not item.get("category", "") in ITEM_CATEGORIES:
			problems.append("%s: category phải là một trong %s" % [where, ITEM_CATEGORIES])
		_check_stat_keys(problems, where, item.get("modifiers", {}), combat_stats)
		_check_stat_keys(problems, where, item.get("use", {}).get("buff", {}), combat_stats)
		for ability_id in item.get("grants_abilities", []):
			_check_ref(problems, where, "abilities", ability_id)
		if item.get("category", "") == "weapon":
			for key in ["damage", "fire_interval", "projectile_speed"]:
				if not item.get("weapon", {}).has(key):
					problems.append("%s: weapon thiếu '%s'" % [where, key])
	for tech in all("tech"):
		_check_stat_keys(problems, _where("tech", tech.id), tech.get("combat_modifiers", {}), combat_stats)
	for ability in all("abilities"):
		var where := _where("abilities", ability.id)
		if ability.get("requires", {}).has("skill"):
			_check_ref(problems, where, "skills", ability.requires.skill)
		_check_stat_keys(problems, where, ability.get("buff", {}), combat_stats)
		if not ability.get("type", "") in ["heal", "slow_enemies", "time_slow", "aoe", "buff"]:
			problems.append("%s: type không hợp lệ" % where)
	for table in all("loot"):
		for entry in table.get("entries", []) + table.get("guaranteed", []):
			if entry.get("item", "") != "":
				_check_ref(problems, _where("loot", table.id), "items", entry.item)
	for recipe in all("recipes"):
		var where := _where("recipes", recipe.id)
		for item_id in recipe.get("materials", {}):
			_check_ref(problems, where, "items", item_id)
		if recipe.has("requires_tech"):
			_check_ref(problems, where, "tech", recipe.requires_tech)
		_check_effects(problems, where, recipe.get("result", {}), stats)
	for node in all("resource_nodes"):
		for item_id in node.get("drops", {}):
			_check_ref(problems, _where("resource_nodes", node.id), "items", item_id)
		if node.has("loot"):
			_check_ref(problems, _where("resource_nodes", node.id), "loot", node.loot)
	for enemy in all("enemies"):
		if enemy.has("loot"):
			_check_ref(problems, _where("enemies", enemy.id), "loot", enemy.loot)
		if enemy.has("summon"):
			_check_ref(problems, _where("enemies", enemy.id), "enemies", enemy.summon)
	for level in all("levels"):
		for node_id in level.get("resource_nodes", {}):
			_check_ref(problems, _where("levels", level.id), "resource_nodes", node_id)
	for chapter in all("chapters"):
		for slot in chapter.get("starting_loadout", {}):
			for item_id in chapter.starting_loadout[slot]:
				_check_ref(problems, _where("chapters", chapter.id), "items", item_id)

	for dialogue in all("dialogues"):
		for line in dialogue.get("lines", []):
			if line.has("speaker"):
				_check_ref(problems, _where("dialogues", dialogue.id), "characters", line.speaker)

	for event in all("events"):
		var where := _where("events", event.id)
		for key in ["title", "text", "choices"]:
			if not event.has(key):
				problems.append("%s: thiếu '%s'" % [where, key])
		if event.has("dialogue"):
			_check_ref(problems, where, "dialogues", event.dialogue)
		_check_conditions(problems, where, event.get("conditions", {}), stats)
		var choices: Array = event.get("choices", [])
		if choices.is_empty():
			problems.append("%s: cần ít nhất 1 lựa chọn" % where)
		for i in choices.size():
			var choice: Dictionary = choices[i]
			var cwhere := "%s.choices[%d]" % [where, i]
			if not choice.has("text"):
				problems.append("%s: thiếu 'text'" % cwhere)
			_check_conditions(problems, cwhere, choice.get("conditions", {}), stats)
			_check_effects(problems, cwhere, choice.get("effects", {}), stats)
	return problems


func _check_conditions(problems: PackedStringArray, where: String, cond: Dictionary, stats: Array) -> void:
	for key in ["stats_min", "stats_max"]:
		for stat in cond.get(key, {}):
			if not stat in stats:
				problems.append("%s: stat '%s' không tồn tại" % [where, stat])
	for item_id in cond.get("items_all", []):
		_check_ref(problems, where, "items", item_id)
	for char_id in cond.get("characters_alive", []):
		_check_ref(problems, where, "characters", char_id)
	for tech_id in cond.get("tech_all", []):
		_check_ref(problems, where, "tech", tech_id)
	for loc_id in cond.get("locations_known", []):
		_check_ref(problems, where, "locations", loc_id)


func _check_effects(problems: PackedStringArray, where: String, eff: Dictionary, stats: Array) -> void:
	for stat in eff.get("stats", {}):
		if not stat in stats:
			problems.append("%s: stat '%s' không tồn tại" % [where, stat])
	for key in ["items_add", "items_remove"]:
		for item_id in eff.get(key, {}):
			_check_ref(problems, where, "items", item_id)
	for key in ["characters_add", "characters_remove"]:
		for char_id in eff.get(key, []):
			_check_ref(problems, where, "characters", char_id)
	for tech_id in eff.get("techs_unlock", []):
		_check_ref(problems, where, "tech", tech_id)
	for loc_id in eff.get("locations_discover", []):
		_check_ref(problems, where, "locations", loc_id)
	if eff.has("loot"):
		_check_ref(problems, where, "loot", eff.loot)
	if eff.has("next_event"):
		_check_ref(problems, where, "events", eff.next_event)


func _check_stat_keys(problems: PackedStringArray, where: String, mods: Dictionary, combat_stats: Array) -> void:
	for stat in mods:
		if not stat in combat_stats:
			problems.append("%s: chỉ số chiến đấu '%s' không tồn tại" % [where, stat])


func _check_ref(problems: PackedStringArray, where: String, category: String, id: String) -> void:
	if not has_entry(category, id):
		problems.append("%s: tham chiếu %s '%s' không tồn tại" % [where, category, id])


func _where(category: String, id: String) -> String:
	return _sources.get("%s/%s" % [category, id], category) + " (" + id + ")"
