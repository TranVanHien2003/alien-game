class_name Loot
extends RefCounted
## Bảng loot (data/loot). Dùng chung cho quái, boss, thùng hàng, thưởng nhiệm vụ, sự kiện.
## Trả về {item_id: số lượng}; id rỗng "" trong bảng nghĩa là "không rơi gì".


static func roll(rng: RandomNumberGenerator, table_id: String) -> Dictionary:
	var table := Content.get_entry("loot", table_id)
	var result := {}
	for entry in table.get("guaranteed", []):
		_add(result, entry, rng)
	var entries: Array = table.get("entries", [])
	var total := 0.0
	for e in entries:
		total += float(e.get("weight", 1))
	for i in int(table.get("rolls", 1)):
		var pick := rng.randf() * total
		for e in entries:
			pick -= float(e.get("weight", 1))
			if pick <= 0.0:
				_add(result, e, rng)
				break
	return result


static func roll_drops(rng: RandomNumberGenerator, drops: Dictionary) -> Dictionary:
	var result := {}
	for item_id in drops:
		var range_: Array = drops[item_id]
		result[item_id] = rng.randi_range(int(range_[0]), int(range_[1]))
	return result


static func give(game: Node, loot: Dictionary) -> void:
	for item_id in loot:
		if loot[item_id] > 0:
			game.add_item(item_id, loot[item_id])
			game.add_log("Nhận %s x%d" % [Content.get_entry("items", item_id).get("name", item_id), loot[item_id]])


static func _add(result: Dictionary, entry: Dictionary, rng: RandomNumberGenerator) -> void:
	var item_id: String = entry.get("item", "")
	if item_id == "":
		return
	var count: Array = entry.get("count", [1, 1])
	result[item_id] = int(result.get(item_id, 0)) + rng.randi_range(int(count[0]), int(count[1]))
