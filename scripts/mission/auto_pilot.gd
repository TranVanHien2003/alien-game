class_name AutoPilot
extends Node
## Engine tự động chơi màn cho các thành viên đang bật AUTO.
##
## Mỗi thành viên định kỳ "suy nghĩ" (khoảng thời gian phụ thuộc Trí tuệ + Tinh mắt + thành thạo vai và độ khó),
## liệt kê các việc có thể làm từ những gì cả đội ĐÃ NHÌN THẤY, chấm điểm theo ưu tiên vai trò
## (roles[].auto_priorities), khoảng cách, mức có ích cho mục tiêu nhiệm vụ, cộng nhiễu (người kém chọn kém hơn),
## rồi nhận việc tốt nhất. Lệnh thủ công của chỉ huy (order.manual) không bao giờ bị ghi đè: thành viên làm xong
## việc được giao rồi mới quay lại tự động.

var level: Node
## Cả đội tự rút lui khi xong mục tiêu / sắp hết giờ
var auto_evac := true
var _known: Dictionary = {}          # instance_id -> true
var _visited_rooms: Dictionary = {}  # chỉ số phòng/điểm khám phá -> true
var _reserved: Dictionary = {}       # instance_id mục tiêu -> Unit đang nhận
var _think: Dictionary = {}          # Unit -> giây còn lại tới lần suy nghĩ tiếp
var _knowledge_timer := 0.0
var _objective_done_at := -1.0
var _cfg: Dictionary = {}


func setup(lvl: Node) -> void:
	level = lvl
	_cfg = Content.config.get("auto", {})
	_visited_rooms[0] = true


# --- Độ hiệu quả của AI theo chỉ số + độ khó ------------------------------------------------

## 0.15..1.0 — người giỏi suy nghĩ nhanh, chọn việc chuẩn; màn khó làm AI kém đi.
func efficiency(u: Unit) -> float:
	var smart := (AttributeSystem.value(Game, u.char_id, "intellect") + AttributeSystem.value(Game, u.char_id, "perception")) / 200.0
	var prof := AttributeSystem.proficiency(Game, u.char_id, Roles.role_of(u.char_id)) / 100.0
	var e := smart * 0.6 + prof * 0.4
	return clampf(e / Difficulty.scale("auto_penalty", level.difficulty), 0.15, 1.0)


func think_interval(u: Unit) -> float:
	return lerpf(float(_cfg.get("think_max", 2.5)), float(_cfg.get("think_min", 0.5)), efficiency(u))


# --- Vòng lặp -----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if level == null or level._finished:
		return
	_knowledge_timer -= delta
	if _knowledge_timer <= 0.0:
		_knowledge_timer = float(_cfg.get("knowledge_interval", 0.4))
		_update_knowledge()
	for u in level.units:
		if u.is_active() and u.auto:
			_tick_unit(u, delta)
	_auto_evac()


func _update_knowledge() -> void:
	var gen: LevelGenerator = level.gen
	for u in level.units:
		if not u.is_active():
			continue
		var sight: float = u.stats.sight_radius
		for group in ["minable", "interactables", "enemies", "pickups"]:
			for node in get_tree().get_nodes_in_group(group):
				if u.global_position.distance_to(node.global_position) <= sight:
					_known[node.get_instance_id()] = true
		var cell := Vector2i(u.global_position / level.map.cell_size)
		for i in gen.rooms.size():
			if gen.rooms[i].grow(1).has_point(cell):
				_visited_rooms[i] = true
	# Giải phóng đặt chỗ của mục tiêu đã mất / thành viên không còn làm
	for id in _reserved.keys():
		var holder = _reserved[id]
		if not is_instance_valid(instance_from_id(id)) or not is_instance_valid(holder) or not holder.is_active() \
				or not is_instance_valid(holder.order.get("target")) or holder.order.get("target").get_instance_id() != id:
			_reserved.erase(id)


func is_known(node: Node) -> bool:
	return _known.has(node.get_instance_id())


func _tick_unit(u: Unit, delta: float) -> void:
	# Ưu tiên tuyệt đối việc chỉ huy giao (lệnh "Dừng" chỉ giữ trong một lúc)
	if u.order.get("manual", false):
		if u.order.type == "idle" and Time.get_ticks_msec() > int(u.order.get("until", 0)):
			u.order = {"type": "idle"}
		else:
			return
	var left: float = float(_think.get(u, randf() * 0.5)) - delta
	_think[u] = left
	if left > 0.0:
		return
	_think[u] = think_interval(u)
	_use_abilities(u)
	var best := _best_task(u)
	if best.is_empty():
		return
	var current_score := float(u.order.get("score", -1.0)) if u.order.get("auto", false) else -1.0
	# Giữ việc đang làm nếu không có việc nào tốt hơn rõ rệt (tránh đổi việc liên tục)
	if u.order.type != "idle" and current_score > 0.0 and best.score < current_score * 1.25:
		return
	if u.order.get("auto", false) and _same_task(u.order, best.order):
		return
	var order: Dictionary = best.order
	order.auto = true
	order.score = best.score
	order.task = best.label
	u.command(order, false)
	if order.has("target") and is_instance_valid(order.target):
		_reserved[order.target.get_instance_id()] = u


func _same_task(a: Dictionary, b: Dictionary) -> bool:
	if a.type != b.type:
		return false
	if a.has("target") or b.has("target"):
		return a.get("target") == b.get("target")
	return Vector2(a.get("pos", Vector2.ZERO)).distance_to(b.get("pos", Vector2.ZERO)) < 80.0


# --- Chấm điểm việc ------------------------------------------------------------------------------

func _score(u: Unit, kind: String, pos: Vector2, bonus: float = 1.0) -> float:
	var pri: Dictionary = Roles.data_of(u.char_id).get("auto_priorities", {})
	var w := float(pri.get(kind, 0.3))
	var dist := u.global_position.distance_to(pos)
	var s := w * bonus / (1.0 + dist / float(_cfg.get("distance_falloff", 700)))
	var noise := float(_cfg.get("noise", 0.7)) * (1.0 - efficiency(u))
	return s * (1.0 + randf_range(-noise, noise))


## Việc đã có người nhận chỉ bị chặn nếu người đó ưu tiên việc này không kém mình
## (thợ mỏ luôn giành được việc khai thác từ chiến binh, y sĩ giành việc cứu người...).
func _reserved_by_other(node: Node, u: Unit, kind: String = "") -> bool:
	var holder = _reserved.get(node.get_instance_id())
	if holder == null or not is_instance_valid(holder) or holder == u or not holder.is_active():
		return false
	if kind == "":
		return true
	var mine_w := float(Roles.data_of(u.char_id).get("auto_priorities", {}).get(kind, 0.3))
	var their_w := float(Roles.data_of(holder.char_id).get("auto_priorities", {}).get(kind, 0.3))
	return their_w >= mine_w


func _best_task(u: Unit) -> Dictionary:
	var tasks: Array = []
	var objective: Dictionary = level.objective
	var obj_type: String = objective.get("type", "")
	var obj_bonus := float(_cfg.get("objective_bonus", 2.2))
	var hp_ratio: float = u.hp / maxf(1.0, u.stats.max_hp)

	# Tự bảo toàn: gần hết máu thì lùi về y sĩ / tàu con thoi
	if hp_ratio < float(_cfg.get("retreat_hp", 0.25)):
		var medic := _nearest_ally(u, func(a): return a.tool_data().get("type", "") == "med")
		var safe: Vector2 = medic.global_position if medic else level.exit_zone.global_position
		return {"score": 99.0, "label": "Rút về chữa trị", "order": {"type": "move", "pos": safe + Vector2(randf_range(-40, 40), randf_range(-40, 40))}}

	# Cứu người gục
	for ally in level.units:
		if ally.state == Unit.State.DOWNED and not _reserved_by_other(ally, u, "revive"):
			var urgency: float = 2.0 + (1.0 - ally.bleed_left / float(Content.config.squad.get("bleed_out_time", 35)))
			tasks.append({"score": _score(u, "revive", ally.global_position, urgency), "label": "Cứu " + ally.display_name(), "order": {"type": "revive", "target": ally}})

	# Đánh quái đã thấy (ưu tiên quái đang đe dọa đồng đội)
	var engage := float(u.stats.sight_radius) * float(_cfg.get("engage_range", 1.4))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_known(enemy):
			continue
		var d := u.global_position.distance_to(enemy.global_position)
		var threat := 1.0
		for ally in level.units:
			if ally.is_active() and ally != u and ally.global_position.distance_to(enemy.global_position) < 300.0:
				threat += 0.6
		if enemy.is_boss:
			threat *= obj_bonus if obj_type == "boss" else 1.5
		if d <= engage or threat > 1.0:
			tasks.append({"score": _score(u, "attack", enemy.global_position, threat), "label": "Tấn công " + enemy.data.get("name", ""), "order": {"type": "attack", "target": enemy}})

	# Bảo vệ người đang làm việc
	for ally in level.units:
		if ally == u or not ally.is_active() or not ally.order.type in ["mine", "interact", "revive"]:
			continue
		if ally.global_position.distance_to(u.global_position) > float(_cfg.get("guard_radius", 260)):
			tasks.append({"score": _score(u, "guard", ally.global_position, 0.8), "label": "Hộ tống " + ally.display_name(), "order": {"type": "advance", "pos": ally.global_position + Vector2(randf_range(-70, 70), randf_range(-70, 70))}})

	# Y sĩ: đi theo người bị thương
	if u.tool_data().get("type", "") == "med":
		var hurt := _nearest_ally(u, func(a): return a != u and a.hp < a.stats.max_hp * 0.7)
		if hurt:
			tasks.append({"score": _score(u, "heal", hurt.global_position, 1.5), "label": "Chữa cho " + hurt.display_name(), "order": {"type": "advance", "pos": hurt.global_position}})

	# Khai thác mỏ đã thấy
	for node in get_tree().get_nodes_in_group("minable"):
		if not is_known(node) or _reserved_by_other(node, u, "mine"):
			continue
		var bonus := 1.0
		if obj_type == "mine" and node.data.get("drops", {}).has(objective.get("item", "")) and not level.objective_done():
			bonus = obj_bonus
		if node.node_id == "salvage_crate":
			bonus *= 1.3
		tasks.append({"score": _score(u, "mine", node.global_position, bonus), "label": "Khai thác " + node.data.get("name", ""), "order": {"type": "mine", "target": node}})

	# Trạm / tủ tiếp tế / cổ vật / người cần cứu
	for obj in get_tree().get_nodes_in_group("interactables"):
		if not is_known(obj) or obj.done or _reserved_by_other(obj, u, "work"):
			continue
		if obj.needs_work():
			var bonus := obj_bonus if obj.kind == "interact" and obj_type == "interact" else (1.4 if obj.kind == "relic" else 1.0)
			tasks.append({"score": _score(u, "work", obj.global_position, bonus), "label": {"interact": "Làm nhiệm vụ", "cache": "Mở tủ tiếp tế", "relic": "Khám phá cổ vật"}.get(obj.kind, "Làm việc"), "order": {"type": "interact", "target": obj}})
		elif obj.kind in ["collect", "rescue", "stranger"]:
			var bonus := obj_bonus if (obj.kind == "collect" and obj_type == "collect") or obj.kind == "rescue" else 1.2
			tasks.append({"score": _score(u, "collect", obj.global_position, bonus), "label": {"rescue": "Giải cứu", "stranger": "Đón người sống sót"}.get(obj.kind, "Thu thập"), "order": {"type": "advance", "pos": obj.global_position}})

	# Nhặt đồ rơi
	for pickup in get_tree().get_nodes_in_group("pickups"):
		if is_known(pickup) and u.global_position.distance_to(pickup.global_position) > float(u.stats.pickup_radius):
			tasks.append({"score": _score(u, "loot", pickup.global_position, 0.8), "label": "Nhặt đồ", "order": {"type": "advance", "pos": pickup.global_position}})

	# Thăm dò điểm khám phá chưa tới
	var gen: LevelGenerator = level.gen
	for i in gen.rooms.size():
		if _visited_rooms.has(i):
			continue
		var pos: Vector2 = level.map.cell_to_world(gen.room_center(i))
		var bonus := 1.0 if not level.objective_done() else 0.6
		tasks.append({"score": _score(u, "explore", pos, bonus) * 0.8, "label": "Thăm dò", "order": {"type": "advance", "pos": pos}})

	var best: Dictionary = {}
	for t in tasks:
		if best.is_empty() or t.score > best.score:
			best = t
	return best


func _nearest_ally(u: Unit, filter: Callable) -> Unit:
	var best: Unit = null
	for ally in level.units:
		if ally.is_active() and filter.call(ally):
			if best == null or u.global_position.distance_to(ally.global_position) < u.global_position.distance_to(best.global_position):
				best = ally
	return best


# --- Tự dùng kỹ năng -------------------------------------------------------------------------------

func _use_abilities(u: Unit) -> void:
	for ability_id in u.abilities:
		if u.cooldown_left(ability_id) > 0.0:
			continue
		var a := Content.get_entry("abilities", ability_id)
		if u.energy < float(a.get("energy", 0)):
			continue
		var target := _ability_target(u, a)
		if target != Vector2.INF and u.use_ability(ability_id, target):
			return


func _ability_target(u: Unit, a: Dictionary) -> Vector2:
	var near := get_tree().get_nodes_in_group("enemies").filter(func(e): return u.global_position.distance_to(e.global_position) < float(a.get("range", 420)))
	match a.get("type", ""):
		"aoe", "slow_enemies":
			# Ném vào chỗ quái tụ đông nhất (≥3)
			var best_pos := Vector2.INF
			var best_count := 2
			for e in near:
				var count := near.filter(func(o): return o.global_position.distance_to(e.global_position) < float(a.get("radius", 130))).size()
				if count > best_count:
					best_count = count
					best_pos = e.global_position
			return best_pos
		"mining_blast":
			var nodes := get_tree().get_nodes_in_group("minable").filter(func(n): return is_known(n) and u.global_position.distance_to(n.global_position) < float(a.get("range", 380)))
			return nodes[0].global_position if nodes.size() >= 2 else Vector2.INF
		"heal_allies":
			var hurt: Array = level.units.filter(func(o): return o.is_active() and o.hp < o.stats.max_hp * 0.6 and u.global_position.distance_to(o.global_position) < float(a.get("radius", 260)))
			return u.global_position if hurt.size() >= 2 else Vector2.INF
		"heal":
			return u.global_position if u.hp < u.stats.max_hp * 0.5 else Vector2.INF
		"buff", "turret":
			return near[0].global_position if near.size() >= 2 else Vector2.INF
		"flare":
			return Vector2.INF if level.map.outdoor or near.is_empty() else near[0].global_position
		"scan":
			return u.global_position if not level.is_revealed() and level.elapsed > 8.0 and _known.size() < 15 else Vector2.INF
	return Vector2.INF


# --- Tự rút lui -----------------------------------------------------------------------------------------

func _auto_evac() -> void:
	if not auto_evac or level.evac_active:
		return
	if not level.units.any(func(x): return x.is_active() and x.auto):
		return
	if level.objective_done():
		if _objective_done_at < 0.0:
			_objective_done_at = level.elapsed
		if level.elapsed - _objective_done_at >= float(_cfg.get("evac_delay", 25)):
			level.hud.show_message("Tự động: mục tiêu hoàn thành, cả đội rút về tàu.")
			level.call_evac()
	elif level.seconds_left() <= float(_cfg.get("evac_time_left", 60)):
		level.hud.show_message("Tự động: sắp hết thời gian, rút lui!")
		level.call_evac()
