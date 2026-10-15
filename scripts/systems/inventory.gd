class_name Inventory
extends RefCounted
## Kho đồ + trang bị (loadout) của đội đổ bộ.
## Mọi vật phẩm (nguyên liệu, tiêu hao, module, vũ khí, đồ cốt truyện) dùng chung game.items {id: số lượng}.
## loadout = {weapons: [id], modules: [id], consumables: [id]} — số ô ở config.player.loadout_slots.

const SLOT_CATEGORY := {"weapons": "weapon", "modules": "module", "consumables": "consumable"}


static func category(item_id: String) -> String:
	return Content.get_entry("items", item_id).get("category", "")


## Icon của vật phẩm: trường "icon" trong data, mặc định assets/items/<id>.png.
static func icon(item_id: String) -> Texture2D:
	var name: String = Content.get_entry("items", item_id).get("icon", item_id)
	var path := "res://assets/items/%s.png" % name
	return load(path) if ResourceLoader.exists(path) else null


static func items_in(game: Node, item_category: String) -> Array:
	return game.items.keys().filter(func(id): return category(id) == item_category)


static func slot_count(slot: String) -> int:
	return int(Content.config.get("player", {}).get("loadout_slots", {}).get(slot, 1))


static func equip(game: Node, slot: String, item_id: String) -> bool:
	if SLOT_CATEGORY.get(slot, "") != category(item_id) or game.item_count(item_id) <= 0:
		return false
	var list: Array = game.loadout.get(slot, [])
	# Module/vũ khí không trang bị trùng nhiều hơn số đang có
	if list.count(item_id) >= game.item_count(item_id) and slot != "consumables":
		return false
	if item_id in list and slot == "consumables":
		return false
	if list.size() >= slot_count(slot):
		return false
	list.append(item_id)
	game.loadout[slot] = list
	return true


static func unequip(game: Node, slot: String, item_id: String) -> void:
	var list: Array = game.loadout.get(slot, [])
	list.erase(item_id)
	# Luôn giữ ít nhất 1 vũ khí
	if slot == "weapons" and list.is_empty():
		list.append(item_id)
	game.loadout[slot] = list


## Gỡ khỏi loadout những thứ không còn trong kho (đã dùng hết, bị xóa ở bản cập nhật...).
static func sanitize_loadout(game: Node) -> void:
	for slot in SLOT_CATEGORY:
		var list: Array = game.loadout.get(slot, [])
		game.loadout[slot] = list.filter(func(id):
			return Content.has_entry("items", id) and game.item_count(id) > 0 and category(id) == SLOT_CATEGORY[slot])
	if game.loadout.weapons.is_empty():
		var weapons := items_in(game, "weapon")
		if not weapons.is_empty():
			game.loadout.weapons = [weapons[0]]


static func default_loadout() -> Dictionary:
	return {"weapons": [], "modules": [], "consumables": []}
