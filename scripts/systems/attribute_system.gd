class_name AttributeSystem
extends RefCounted
## Thuộc tính (sức mạnh, nhanh nhẹn, trí tuệ, bền bỉ, tinh mắt, ý chí) và độ thành thạo vai trò.
##   thành thạo(vai) = Σ thuộc_tính × trọng_số_vai   (0..100)
##   hiệu quả(vai)   = 0.6 + thành_thạo / 100 × 0.8  (×0.6 .. ×1.4) — nhân vào chỉ số & kỹ năng của vai
## Thuộc tính tăng nhờ: huấn luyện theo năm, khám phá (hành động trong màn), tài năng, trang bị, kỳ ngộ.


static func ids() -> Array:
	return Content.config.get("attributes", {}).keys()


static func label(attr: String) -> String:
	return Content.config.get("attributes", {}).get(attr, {}).get("label", attr)


## Thuộc tính gốc (đã huấn luyện) — chưa tính trang bị/tài năng.
static func base(game: Node, char_id: String, attr: String) -> float:
	return float(game.crew.get(char_id, {}).get("attributes", {}).get(attr, 30))


## Thuộc tính hiệu lực = gốc + module + tài năng.
static func value(game: Node, char_id: String, attr: String) -> float:
	var v := base(game, char_id, attr)
	v += float(Content.get_entry("items", Inventory.equipped(game, char_id, "module")).get("attributes", {}).get(attr, 0))
	for talent_id in game.crew.get(char_id, {}).get("talents", []):
		v += float(Content.get_entry("talents", talent_id).get("attributes", {}).get(attr, 0))
	return minf(v, float(Content.config.get("lifecycle", {}).get("hard_cap", 100)) + 30.0)


static func all_values(game: Node, char_id: String) -> Dictionary:
	var result := {}
	for attr in ids():
		result[attr] = value(game, char_id, attr)
	return result


static func proficiency_from(attrs: Dictionary, role_id: String) -> float:
	var weights: Dictionary = Content.get_entry("roles", role_id).get("attribute_weights", {})
	var total := 0.0
	for attr in weights:
		total += float(attrs.get(attr, 30)) * float(weights[attr])
	return clampf(total, 0.0, 120.0)


static func proficiency(game: Node, char_id: String, role_id: String) -> float:
	return proficiency_from(all_values(game, char_id), role_id)


static func efficiency(game: Node, char_id: String, role_id: String) -> float:
	return 0.6 + proficiency(game, char_id, role_id) / 100.0 * 0.8


static func best_roles_for(attrs: Dictionary, count: int) -> Array:
	var roles: Array = Content.ids("roles")
	roles.sort_custom(func(a, b): return proficiency_from(attrs, a) > proficiency_from(attrs, b))
	return roles.slice(0, count)


## Tăng thuộc tính có "trần mềm": trên soft_cap thì tăng chậm lại một nửa.
static func grow(game: Node, char_id: String, attr: String, amount: float) -> float:
	var member: Dictionary = game.crew.get(char_id, {})
	if member.is_empty() or not attr in ids():
		return 0.0
	var cfg: Dictionary = Content.config.get("lifecycle", {})
	var current := float(member.get("attributes", {}).get(attr, 30))
	if current >= float(cfg.get("soft_cap", 70)):
		amount *= 0.5
	var next := minf(current + amount, float(cfg.get("hard_cap", 100)))
	member.attributes[attr] = snappedf(next, 0.1)
	return next - current


## Áp dụng {thuộc_tính: +n} cho một thành viên, trả về chuỗi mô tả ("+5 Trí tuệ, +3 Ý chí").
static func apply_bonus(game: Node, char_id: String, bonus: Dictionary, multiplier: float = 1.0) -> String:
	var parts := PackedStringArray()
	for attr in bonus:
		var gained := grow(game, char_id, attr, float(bonus[attr]) * multiplier)
		if gained > 0.05:
			parts.append("+%s %s" % [str(snappedf(gained, 0.1)), label(attr)])
	return ", ".join(parts)


## Thành viên tự mở vai mới khi thành thạo vượt ngưỡng auto_unlock.
static func check_role_unlocks(game: Node, char_id: String) -> Array:
	var member: Dictionary = game.crew.get(char_id, {})
	if member.is_empty() or Content.get_entry("characters", char_id).get("child", false) and member.get("roles", []).is_empty():
		return []
	var unlocked := []
	for role in Content.all("roles"):
		if role.id in member.get("roles", []):
			continue
		if proficiency(game, char_id, role.id) >= float(role.get("auto_unlock", 55)):
			member.roles.append(role.id)
			unlocked.append(role.id)
			game.add_log("⭐ %s đủ năng lực để đảm nhận vai %s." % [CrewSystem.display_name(char_id), role.name])
	return unlocked


## Chỉ huy gán vai: cần thành thạo tối thiểu assign_min.
static func can_assign(game: Node, char_id: String, role_id: String) -> bool:
	var member: Dictionary = game.crew.get(char_id, {})
	return not member.is_empty() and not role_id in member.get("roles", []) \
		and proficiency(game, char_id, role_id) >= float(Content.get_entry("roles", role_id).get("assign_min", 25))


static func assign_role(game: Node, char_id: String, role_id: String) -> bool:
	if not can_assign(game, char_id, role_id):
		return false
	game.crew[char_id].roles.append(role_id)
	game.add_log("%s được giao thêm vai %s." % [CrewSystem.display_name(char_id), Roles.name_of(role_id)])
	return true


static func set_active_role(game: Node, char_id: String, role_id: String) -> bool:
	var member: Dictionary = game.crew.get(char_id, {})
	if member.is_empty() or not role_id in member.get("roles", []):
		return false
	member.active_role = role_id
	# Trang bị không hợp vai mới thì gỡ, rồi tự trang bị lại
	Inventory.sanitize(game)
	Roles.auto_equip(game, char_id)
	return true


## Huấn luyện mỗi năm (thành viên rảnh): tăng thuộc tính đang tập trung.
static func yearly_training(game: Node) -> void:
	var cfg: Dictionary = Content.config.get("lifecycle", {})
	var gain: Array = cfg.get("training_gain", [2, 4])
	var hungry := NutritionSystem.is_hungry(game)
	for char_id in game.crew:
		var member: Dictionary = game.crew[char_id]
		var focus: String = member.get("training_focus", "")
		if focus == "" or member.status != CrewSystem.IDLE or hungry:
			continue
		grow(game, char_id, focus, game.rng.randf_range(float(gain[0]), float(gain[1])))
		check_role_unlocks(game, char_id)


## Khám phá: chuyển các hành động trong màn (hạ quái, đào mỏ, làm việc, cứu người...) thành thuộc tính + XP.
static func apply_mission_growth(game: Node, char_id: String, counters: Dictionary, success: bool) -> String:
	var cfg: Dictionary = Content.config.get("growth", {})
	var cap := float(cfg.get("max_per_mission", 4))
	var gains := {}
	for key in counters:
		for attr in cfg.get(key, {}):
			gains[attr] = float(gains.get(attr, 0.0)) + float(counters[key]) * float(cfg[key][attr])
	for attr in gains:
		gains[attr] = minf(gains[attr], cap)
	var text := apply_bonus(game, char_id, gains)
	var tp: Dictionary = Content.config.get("talent_points", {})
	var xp := float(tp.get("mission_xp", 40)) + (float(tp.get("success_xp", 40)) if success else 0.0) + float(counters.get("kills", 0)) * float(tp.get("kill_xp", 3))
	Talents.add_xp(game, char_id, xp)
	check_role_unlocks(game, char_id)
	return text
