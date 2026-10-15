class_name Crafting
extends RefCounted
## Chế tạo ở xưởng trên tàu: tiêu nguyên liệu -> áp dụng "result" (cùng định dạng hiệu ứng với sự kiện).


static func unlocked(game: Node) -> Array:
	return Content.all("recipes").filter(func(r): return r.get("requires_tech", "") == "" or r.requires_tech in game.techs)


static func can_craft(game: Node, recipe: Dictionary) -> bool:
	if not recipe in unlocked(game):
		return false
	for item_id in recipe.get("materials", {}):
		if game.item_count(item_id) < int(recipe.materials[item_id]):
			return false
	return true


static func craft(game: Node, recipe_id: String) -> bool:
	var recipe := Content.get_entry("recipes", recipe_id)
	if recipe.is_empty() or not can_craft(game, recipe):
		return false
	for item_id in recipe.materials:
		game.add_item(item_id, -int(recipe.materials[item_id]))
	EventRules.apply(game, recipe.get("result", {}))
	game.add_log("🛠 Chế tạo: " + recipe.get("name", recipe_id))
	game.state_changed.emit()
	return true
