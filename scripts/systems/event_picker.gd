class_name EventPicker
extends RefCounted
## Chọn sự kiện cho năm hiện tại.
## 1. Sự kiện "forced" đủ điều kiện -> chọn cái có priority cao nhất.
## 2. Ngược lại, với xác suất config.event_chance, bốc ngẫu nhiên theo "weight".


static func pick(game: Node) -> Dictionary:
	var forced := []
	var pool := []
	for event in Content.all("events"):
		if event.get("once", false) and game.seen_events.has(event.id):
			continue
		if not EventRules.check(game, event.get("conditions", {})):
			continue
		if event.get("forced", false):
			forced.append(event)
		else:
			pool.append(event)

	if not forced.is_empty():
		forced.sort_custom(func(a, b): return a.get("priority", 0) > b.get("priority", 0))
		return forced[0]

	if pool.is_empty() or game.rng.randf() > float(Content.config.get("event_chance", 0.5)):
		return {}

	var total := 0.0
	for event in pool:
		total += float(event.get("weight", 1))
	var roll: float = game.rng.randf() * total
	for event in pool:
		roll -= float(event.get("weight", 1))
		if roll <= 0.0:
			return event
	return pool.back()
