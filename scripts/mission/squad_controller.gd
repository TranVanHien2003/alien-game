class_name SquadController
extends Node2D
## Điều khiển kiểu chỉ huy (RTS):
##   Chuột trái: chọn (click / kéo khung, Shift để thêm)   1–6: chọn từng người   Ctrl+A: chọn cả đội
##   Chuột phải: ra lệnh theo ngữ cảnh — sàn = di chuyển (đội hình), quái = tấn công, mỏ = khai thác,
##               trạm/tủ = tương tác, đồng đội gục = cứu
##   Q/E/R: kỹ năng của người được chọn đầu tiên (nhắm vào con trỏ)   Z/X: vật phẩm nhanh
##   H: dừng   G: giữ vị trí   B: rút lui   Space: về camera đội   WASD/mép màn hình/lăn chuột: camera

signal selection_changed

const EDGE_SCROLL := 14.0
const CAMERA_SPEED := 900.0

var level: Node
var camera: Camera2D
var units: Array = []
var world_size := Vector2(4000, 3000)

## Đội hình khi di chuyển: wedge (nêm), line (hàng ngang), column (hàng dọc), spread (tản ra)
var formation := "wedge"
var _drag_start := Vector2.INF
var _drag_now := Vector2.ZERO
var _markers: Array = []  # [{pos, color, t}]


func setup(lvl: Node, cam: Camera2D, squad: Array, bounds: Vector2) -> void:
	level = lvl
	camera = cam
	units = squad
	world_size = bounds
	z_index = 20
	select_only(units.filter(func(u): return u.is_active()))


func selected() -> Array:
	return units.filter(func(u): return u.selected and u.is_active())


func select_only(list: Array) -> void:
	for u in units:
		u.selected = u in list
	selection_changed.emit()


func toggle(unit: Unit, additive: bool) -> void:
	if additive:
		unit.selected = not unit.selected
		selection_changed.emit()
	else:
		select_only([unit])


func focus(unit: Unit) -> void:
	camera.global_position = unit.global_position


# --- Nhập liệu --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("select"):
		_drag_start = get_global_mouse_position()
		_drag_now = _drag_start
	elif event.is_action_released("select") and _drag_start != Vector2.INF:
		_finish_selection(Input.is_key_pressed(KEY_SHIFT))
		_drag_start = Vector2.INF
	elif event is InputEventMouseMotion and _drag_start != Vector2.INF:
		_drag_now = get_global_mouse_position()
	elif event.is_action_pressed("order"):
		_give_order(get_global_mouse_position())
	elif event.is_action_pressed("zoom_in"):
		zoom_by(1.1)
	elif event.is_action_pressed("zoom_out"):
		zoom_by(1.0 / 1.1)
	elif event.is_action_pressed("select_all"):
		select_only(units.filter(func(u): return u.is_active()))
	elif event.is_action_pressed("stop"):
		for u in selected():
			u.stop()
	elif event.is_action_pressed("hold"):
		toggle_hold()
	elif event.is_action_pressed("center_camera"):
		var sel := selected()
		if not sel.is_empty():
			focus(sel[0])
	elif event.is_action_pressed("evac"):
		level.call_evac()
	else:
		for i in 6:
			if event.is_action_pressed("select_unit_%d" % (i + 1)) and i < units.size() and units[i].is_active():
				toggle(units[i], Input.is_key_pressed(KEY_SHIFT))
		for i in Abilities.MAX_ACTIVE:
			if event.is_action_pressed("ability_%d" % (i + 1)):
				cast(i)
		for i in 2:
			if event.is_action_pressed("item_%d" % (i + 1)):
				var sel := selected()
				if not sel.is_empty():
					level.use_consumable(sel[0], i)


func zoom_by(factor: float) -> void:
	camera.zoom = (camera.zoom * factor).clamp(Vector2(0.25, 0.25), Vector2(1.4, 1.4))


func toggle_hold() -> void:
	var sel := selected()
	var hold := not sel.all(func(u): return u.hold_position)
	for u in sel:
		u.hold_position = hold
	level.hud.show_message("Giữ vị trí" if hold else "Tự do giao chiến")


func cast(slot: int) -> void:
	var sel := selected()
	if sel.is_empty() or slot >= sel[0].abilities.size():
		return
	var ability_id: String = sel[0].abilities[slot]
	if sel[0].use_ability(ability_id, get_global_mouse_position()):
		level.hud.show_message("%s: %s" % [sel[0].display_name(), Content.get_entry("abilities", ability_id).get("name", "")])
	else:
		level.hud.show_message("Chưa sẵn sàng (hồi chiêu hoặc thiếu năng lượng)")


func _finish_selection(additive: bool) -> void:
	var rect := Rect2(_drag_start, _drag_now - _drag_start).abs()
	var picked := []
	if rect.size.length() < 10.0:
		var u := _unit_at(_drag_start)
		if u:
			toggle(u, additive)
			return
	else:
		picked = units.filter(func(u): return u.is_active() and rect.has_point(u.global_position))
	if additive:
		for u in picked:
			u.selected = true
		selection_changed.emit()
	elif not picked.is_empty():
		select_only(picked)


func _unit_at(pos: Vector2) -> Unit:
	for u in units:
		if u.visible and u.global_position.distance_to(pos) < 26.0:
			return u
	return null


## Lệnh theo ngữ cảnh tại vị trí con trỏ.
func _give_order(pos: Vector2) -> void:
	var sel := selected()
	if sel.is_empty():
		return
	var target := _target_at(pos)
	var color := Color("#B4FF39")
	if target is Enemy:
		color = Color("#FF5A5A")
		for u in sel:
			u.command({"type": "attack", "target": target})
	elif target is ResourceNode:
		color = Color("#FFC94D")
		for u in sel:
			u.command({"type": "mine", "target": target})
	elif target is Objective:
		color = Color("#00E5FF")
		# Chỉ cần một người làm: người gần nhất (ưu tiên kỹ sư), số còn lại đứng canh quanh đó
		var engineers := sel.filter(func(u): return Roles.role_of(u.char_id) == "engineer")
		var candidates: Array = engineers if not engineers.is_empty() else sel
		var worker: Unit = candidates[0]
		for u in candidates:
			if u.global_position.distance_to(pos) < worker.global_position.distance_to(pos):
				worker = u
		worker.command({"type": "interact", "target": target})
		_move_group(sel.filter(func(u): return u != worker), pos)
	elif target is Unit:
		color = Color("#7CFFB2")
		var helper: Unit = sel[0]
		for u in sel:
			if Roles.role_of(u.char_id) == "medic":
				helper = u
		helper.command({"type": "revive", "target": target})
	else:
		_move_group(sel, pos)
	_markers.append({"pos": pos, "color": color, "t": 0.6})
	Sfx.play("ui_click", 0.1, -16.0)


func _move_group(group: Array, pos: Vector2, order_type: String = "move") -> void:
	if group.is_empty():
		return
	var spacing := float(Content.config.get("squad", {}).get("formation_spacing", 56))
	var centroid := Vector2.ZERO
	for u in group:
		centroid += u.global_position
	centroid /= group.size()
	var dir := (pos - centroid).normalized() if pos.distance_to(centroid) > 1.0 else Vector2.RIGHT
	var side := dir.orthogonal()
	var n := group.size()
	# Người gần đích nhất đi đầu để đội hình không bị đảo lộn
	var sorted := group.duplicate()
	sorted.sort_custom(func(a, b): return a.global_position.dot(dir) > b.global_position.dot(dir))
	for i in n:
		var offset := Vector2.ZERO
		match formation:
			"line":
				offset = side * (i - (n - 1) / 2.0) * spacing * 1.2
			"column":
				offset = -dir * i * spacing
			"spread":
				offset = Vector2.ZERO if i == 0 else Vector2.from_angle(TAU * (i - 1) / maxf(1, n - 1)) * spacing * 2.4
			_:
				# Nêm: người đầu ở mũi, hai cánh lùi dần về sau
				var rank := (i + 1) / 2
				offset = -dir * rank * spacing * 0.8 + side * rank * spacing * (1 if i % 2 == 1 else -1)
		sorted[i].command({"type": order_type, "pos": pos + offset})


const FORMATION_NAMES := {"wedge": "Nêm", "line": "Hàng ngang", "column": "Hàng dọc", "spread": "Tản ra"}


## Đổi đội hình và xếp lại ngay tại chỗ.
func set_formation(value: String) -> void:
	formation = value
	var sel := selected()
	if sel.is_empty():
		return
	var centroid := Vector2.ZERO
	for u in sel:
		centroid += u.global_position
	_move_group(sel, centroid / sel.size() + Vector2(1, 0))
	level.hud.show_message("Đội hình: " + FORMATION_NAMES.get(value, value))


## Tiến công / xung phong tới vị trí con trỏ.
func advance(charge: bool) -> void:
	var sel := selected()
	if sel.is_empty():
		return
	if charge:
		for u in sel:
			u.add_buff({"move_speed": 90.0, "damage_mult": 0.15}, 6.0)
	_move_group(sel, get_global_mouse_position() if _mouse_in_world() else _forward_point(sel), "advance")
	level.hud.show_message("XUNG PHONG!" if charge else "Tiến công")


## Lùi lại xa khỏi quái gần nhất.
func fall_back() -> void:
	var sel := selected()
	if sel.is_empty():
		return
	var centroid := Vector2.ZERO
	for u in sel:
		centroid += u.global_position
	centroid /= sel.size()
	var threat := Vector2.ZERO
	var count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(centroid) < 700.0:
			threat += enemy.global_position
			count += 1
	var away: Vector2 = (centroid - threat / count).normalized() if count > 0 else (level.exit_zone.global_position - centroid).normalized()
	_move_group(sel, centroid + away * 320.0)
	level.hud.show_message("Lùi lại!")


func _mouse_in_world() -> bool:
	var vp := get_viewport()
	return Rect2(Vector2.ZERO, vp.get_visible_rect().size).has_point(vp.get_mouse_position())


func _forward_point(sel: Array) -> Vector2:
	var centroid := Vector2.ZERO
	for u in sel:
		centroid += u.global_position
	return centroid / sel.size()


func _target_at(pos: Vector2) -> Node:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(pos) < enemy._radius + 14.0:
			return enemy
	for u in units:
		if u.state == Unit.State.DOWNED and u.global_position.distance_to(pos) < 30.0:
			return u
	for obj in get_tree().get_nodes_in_group("interactables"):
		if obj.needs_work() and obj.global_position.distance_to(pos) < 34.0:
			return obj
	for node in get_tree().get_nodes_in_group("minable"):
		if node.global_position.distance_to(pos) < float(node.data.get("radius", 18)) + 14.0:
			return node
	return null


# --- Camera & vẽ -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var dir := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	var viewport := get_viewport()
	var mouse := viewport.get_mouse_position()
	var size := viewport.get_visible_rect().size
	if DisplayServer.window_is_focused() and Rect2(Vector2.ZERO, size).has_point(mouse) and _drag_start == Vector2.INF:
		if mouse.x < EDGE_SCROLL: dir.x = -1
		elif mouse.x > size.x - EDGE_SCROLL: dir.x = 1
		if mouse.y < EDGE_SCROLL: dir.y = -1
		elif mouse.y > size.y - EDGE_SCROLL: dir.y = 1
	if dir != Vector2.ZERO:
		camera.global_position += dir * CAMERA_SPEED * delta / camera.zoom.x
	# Không cho camera nhìn ra ngoài mép bản đồ
	var half := size / camera.zoom / 2.0
	var lo := half.min(world_size / 2.0)
	var hi := (world_size - half).max(world_size / 2.0)
	camera.global_position = camera.global_position.clamp(lo, hi)
	for m in _markers.duplicate():
		m.t -= delta
		if m.t <= 0.0:
			_markers.erase(m)
	queue_redraw()


func _draw() -> void:
	if _drag_start != Vector2.INF and _drag_start.distance_to(_drag_now) > 10.0:
		var rect := Rect2(_drag_start, _drag_now - _drag_start).abs()
		draw_rect(rect, Color(0.7, 1, 0.3, 0.12))
		draw_rect(rect, Color("#B4FF39"), false, 1.5)
	for m in _markers:
		draw_arc(m.pos, 14.0 + (0.6 - m.t) * 30.0, 0.0, TAU, 24, Color(m.color, m.t / 0.6), 2.0)
