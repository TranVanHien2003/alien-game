class_name NutritionSystem
extends RefCounted
## Lương thực tiêu thụ theo từng thành viên phi hành đoàn: khác nhau theo độ tuổi, giới tính và vai trò.
## (Dân số chung của tàu vẫn tiêu thụ theo config.yearly.food.per_person.)
## Thiếu lương thực (dưới hungry_below) -> cả đội "đói": giảm chỉ số chiến đấu, ngừng huấn luyện.


static func age_group(game: Node, char_id: String) -> Dictionary:
	var age: int = game.character_age(char_id)
	for g in Content.config.get("nutrition", {}).get("age", []):
		if age <= int(g.get("max", 999)):
			return g
	return {"mult": 1.0, "label": ""}


## Lượng lương thực (đơn vị chỉ số Lương thực) một thành viên ăn mỗi năm.
static func consumption(game: Node, char_id: String) -> float:
	var cfg: Dictionary = Content.config.get("nutrition", {})
	var data := Content.get_entry("characters", char_id)
	if data.get("ageless", false):
		return 0.0
	var mult := float(age_group(game, char_id).get("mult", 1.0))
	mult *= float(cfg.get("gender", {}).get(data.get("gender", ""), 1.0))
	mult *= float(cfg.get("role", {}).get(Roles.role_of(char_id), 1.0)) if not data.get("child", false) or game.crew.get(char_id, {}).get("roles", []).size() > 0 else 1.0
	return float(cfg.get("base", 0.06)) * mult


static func crew_consumption(game: Node) -> float:
	var total := 0.0
	for char_id in game.crew:
		if game.crew[char_id].status != CrewSystem.MISSING:
			total += consumption(game, char_id)
	return total


static func is_hungry(game: Node) -> bool:
	return game.get_stat("food") < float(Content.config.get("nutrition", {}).get("hungry_below", 12))


static func tick_year(game: Node) -> void:
	game.change_stat("food", -crew_consumption(game))
	if is_hungry(game):
		game.add_log("⚠ Lương thực cạn kiệt — phi hành đoàn đang đói, sức chiến đấu giảm.")
