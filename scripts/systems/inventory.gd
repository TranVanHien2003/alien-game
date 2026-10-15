class_name Inventory
extends RefCounted
## Kho đồ + trang bị.
## Mọi vật phẩm (nguyên liệu, tiêu hao, module, vũ khí, công cụ, đồ cốt truyện) dùng chung game.items {id: số lượng}.
## Mỗi thành viên có game.crew[id].equipment = {weapon, tool, module} (theo vai trò, xem Roles.can_use).
## Vật phẩm tiêu hao mang theo cả đội: game.loadout.consumables (config.player.consumable_slots ô).

const MEMBER_SLOTS := ["weapon", "tool", "module"]


static func category(item_id: String) -> String:
	return Content.get_entry("items", item_id).get("category", "")


## Icon của vật phẩm: trường "icon" trong data, mặc định assets/items/<id>.png.
static func icon(item_id: String) -> Texture2D:
	var name: String = Content.get_entry("items", item_id).get("icon", item_id)
	var path := "res://assets/items/%s.png" % name
	return load(path) if ResourceLoader.exists(path) else null


static func items_in(game: Node, item_category: String) -> Array:
	return game.items.keys().filter(func(id): return category(id) == item_category)


# --- Trang bị từng thành viên ------------------------------------------------------

static func equipped(game: Node, char_id: String, slot: String) -> String:
	return game.crew.get(char_id, {}).get("equipment", {}).get(slot, "")


## Số lượng còn lại trong kho chưa bị ai trang bị.
static func available(game: Node, item_id: String) -> int:
	var used := 0
	for char_id in game.crew:
		for slot in MEMBER_SLOTS:
			if equipped(game, char_id, slot) == item_id:
				used += 1
	return game.item_count(item_id) - used


static func equip_member(game: Node, char_id: String, slot: String, item_id: String) -> bool:
	if not game.crew.has(char_id) or not slot in MEMBER_SLOTS or category(item_id) != slot:
		return false
	if not Roles.can_use(char_id, item_id) or available(game, item_id) <= 0:
		return false
	var equipment: Dictionary = game.crew[char_id].get("equipment", {})
	equipment[slot] = item_id
	game.crew[char_id].equipment = equipment
	return true


static func unequip_member(game: Node, char_id: String, slot: String) -> void:
	if game.crew.has(char_id):
		game.crew[char_id].get("equipment", {}).erase(slot)


# --- Vật phẩm tiêu hao của đội ----------------------------------------------------------

static func consumable_slots() -> int:
	return int(Content.config.get("player", {}).get("consumable_slots", 2))


static func equip_consumable(game: Node, item_id: String) -> bool:
	var list: Array = game.loadout.get("consumables", [])
	if category(item_id) != "consumable" or item_id in list or list.size() >= consumable_slots():
		return false
	list.append(item_id)
	game.loadout.consumables = list
	return true


static func unequip_consumable(game: Node, item_id: String) -> void:
	game.loadout.get("consumables", []).erase(item_id)


## Gỡ những thứ không hợp lệ (đã dùng hết, bị xóa ở bản cập nhật, sai vai trò...).
static func sanitize(game: Node) -> void:
	game.loadout.consumables = game.loadout.get("consumables", []).filter(func(id):
		return Content.has_entry("items", id) and category(id) == "consumable")
	for char_id in game.crew:
		var equipment: Dictionary = game.crew[char_id].get("equipment", {})
		for slot in equipment.keys():
			var item_id: String = equipment[slot]
			if not Content.has_entry("items", item_id) or category(item_id) != slot or not Roles.can_use(char_id, item_id):
				equipment.erase(slot)
		game.crew[char_id].equipment = equipment
	# Trang bị vượt quá số lượng trong kho -> gỡ bớt
	for item_id in game.items.keys() + []:
		while available(game, item_id) < 0:
			for char_id in game.crew:
				for slot in MEMBER_SLOTS:
					if available(game, item_id) < 0 and equipped(game, char_id, slot) == item_id:
						unequip_member(game, char_id, slot)
	for char_id in game.crew:
		for slot in MEMBER_SLOTS:
			var item_id := equipped(game, char_id, slot)
			if item_id != "" and game.item_count(item_id) <= 0:
				unequip_member(game, char_id, slot)


static func default_loadout() -> Dictionary:
	return {"consumables": []}
