class_name MissionHud
extends CanvasLayer
## HUD chỉ huy: thông tin màn (độ khó, thời gian, đợt quái), mục tiêu, thanh máu boss,
## thẻ thành viên (bấm để chọn), kỹ năng + vật phẩm của người đang chọn, nút lệnh, minimap,
## menu tạm dừng và bảng kết quả. Dựng bằng code để bố cục theo dữ liệu.

signal resume_pressed
signal abort_pressed
signal return_pressed

var _level: Node
var _info_label: Label
var _timer_label: Label
var _objective_label: Label
var _loot_label: Label
var _message_label: Label
var _boss_box: VBoxContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _cards_box: HBoxContainer
var _cards: Array = []  # [{unit, panel, hp, energy, state}]
var _actions_box: HBoxContainer
var _ability_buttons: Array = []
var _item_buttons: Array = []
var _minimap: Minimap
var _evac_label: Label
var _pause_panel: PanelContainer
var _result_panel: PanelContainer
var _result_title: Label
var _result_body: RichTextLabel
var _message_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func setup(level: Node) -> void:
	_level = level
	var loc := Content.get_entry("locations", level.entry.location)
	_info_label.text = "%s — %s\nĐộ khó %s %s · Đội %d người" % [
		level.mission.get("name", ""), loc.get("name", ""),
		Difficulty.stars(level.difficulty), Difficulty.label(level.difficulty), level.units.size()]
	for unit in level.units:
		_add_card(unit)
	_minimap.setup(level)
	level.controller.selection_changed.connect(_refresh_actions)
	_refresh_actions()
	show_message("Đổ bộ xuống %s. Chuột trái chọn, chuột phải ra lệnh." % loc.get("name", ""))


func track_boss(boss: Enemy) -> void:
	_boss_box.visible = true
	_boss_name.text = boss.data.get("name", "BOSS")
	_boss_bar.max_value = boss.max_hp
	_boss_bar.value = boss.hp
	boss.hp_changed.connect(func(hp, max_hp): _set_bar(_boss_bar, hp, max_hp))
	boss.died.connect(func(_b): _boss_box.visible = false)


func set_objective(text: String, done: bool) -> void:
	_objective_label.text = ("✔ " if done else "◎ ") + text
	_objective_label.modulate = Color("#B4FF39") if done else Color.WHITE


func update_loot(loot: Dictionary) -> void:
	var lines := PackedStringArray(["Đồ đã nhặt:"])
	for item_id in loot:
		lines.append("  %s x%d" % [Content.get_entry("items", item_id).get("name", item_id), loot[item_id]])
	_loot_label.text = "\n".join(lines) if loot.size() > 0 else ""


func show_message(text: String) -> void:
	_message_label.text = text
	_message_time = 3.0


func show_pause(paused: bool) -> void:
	_pause_panel.visible = paused


func show_result(report: Dictionary, loot: Dictionary, aboard: Array) -> void:
	_pause_panel.visible = false
	_result_panel.visible = true
	var success: bool = report.get("success", false)
	_result_title.text = "NHIỆM VỤ THÀNH CÔNG" if success else ("RÚT LUI" if not aboard.is_empty() else "MẤT LIÊN LẠC VỚI ĐỘI")
	_result_title.modulate = Color("#B4FF39") if success else Color("#FF2BD6")
	var lines := PackedStringArray([report.get("title", ""), "Về tàu an toàn: " + (", ".join(aboard.map(func(id): return CrewSystem.display_name(id))) if not aboard.is_empty() else "không ai")])
	if loot.is_empty():
		lines.append("Không mang được gì về tàu.")
	else:
		lines.append("\n[b]Mang về tàu:[/b]")
		for item_id in loot:
			lines.append("• %s x%d" % [Content.get_entry("items", item_id).get("name", item_id), loot[item_id]])
	if _level and _level.run_research > 0.0 and success:
		lines.append("• +%d điểm nghiên cứu (phân tích mẫu vật)" % roundi(_level.run_research))
	for char_id in report.get("missing", []):
		lines.append("\n[color=#FF2BD6]⚠ %s mất tích! Hãy mở nhiệm vụ Giải cứu trước khi quá muộn.[/color]" % CrewSystem.display_name(char_id))
	_result_body.text = "\n".join(lines)


# --- Cập nhật mỗi khung ------------------------------------------------------------------

func _process(delta: float) -> void:
	_message_time -= delta
	_message_label.modulate.a = clampf(_message_time, 0.0, 1.0)
	if _level == null:
		return
	var left: float = _level.seconds_left()
	_timer_label.text = "⏱ %d:%02d   Đợt quái tiếp: %ds" % [int(left) / 60, int(left) % 60, roundi(_level.next_wave_in())]
	_timer_label.modulate = Color("#FF5A5A") if left < 60.0 else Color.WHITE
	_evac_label.visible = _level.evac_active
	if _level.evac_active:
		_evac_label.text = "RÚT LUI — %ds — đưa mọi người vào vòng tàu con thoi" % roundi(maxf(0.0, _level.evac_left))
	for card in _cards:
		var u: Unit = card.unit
		_set_bar(card.hp, u.hp, u.stats.max_hp)
		_set_bar(card.energy, u.energy, u.stats.max_energy)
		var state := ""
		match u.state:
			Unit.State.DOWNED: state = "GỤC %ds" % roundi(u.bleed_left)
			Unit.State.LOST: state = "MẤT TÍCH"
			Unit.State.EVACUATED: state = "Trên tàu"
			_: state = {"idle": "Sẵn sàng", "move": "Di chuyển", "attack": "Tấn công", "mine": "Khai thác", "interact": "Làm việc", "revive": "Cứu người", "evac": "Rút lui"}.get(u.order.type, "")
		card.state.text = state + (" · Giữ" if u.hold_position and u.is_active() else "")
		card.panel.modulate = Color(1, 1, 1) if u.is_active() else Color(1, 0.6, 0.7) if u.state == Unit.State.DOWNED else Color(0.5, 0.5, 0.5)
		card.panel.self_modulate = Color("#B4FF39") if u.selected else Color.WHITE
	_update_action_labels()


func _set_bar(bar: ProgressBar, value: float, max_value: float) -> void:
	bar.max_value = maxf(1.0, max_value)
	bar.value = value


func _refresh_actions() -> void:
	for b in _ability_buttons + _item_buttons:
		b.queue_free()
	_ability_buttons = []
	_item_buttons = []
	if _level == null:
		return
	var sel: Array = _level.controller.selected()
	if sel.is_empty():
		return
	var u: Unit = sel[0]
	var keys := ["Q", "E", "R"]
	for i in u.abilities.size():
		var b := UI.button("", func(): _level.controller.cast(i))
		b.tooltip_text = Content.get_entry("abilities", u.abilities[i]).get("description", "")
		_actions_box.add_child(b)
		_ability_buttons.append(b)
	var consumables: Array = Game.loadout.get("consumables", [])
	for i in consumables.size():
		var b := UI.button("", _use_item.bind(i))
		b.icon = Inventory.icon(consumables[i])
		b.expand_icon = true
		b.custom_minimum_size = Vector2(0, 44)
		_actions_box.add_child(b)
		_item_buttons.append(b)
	_update_action_labels()


func _stop_selected() -> void:
	for u in _level.controller.selected():
		u.stop()


func _use_item(slot: int) -> void:
	var sel: Array = _level.controller.selected()
	if not sel.is_empty():
		_level.use_consumable(sel[0], slot)


func _update_action_labels() -> void:
	var sel: Array = _level.controller.selected()
	if sel.is_empty():
		return
	var u: Unit = sel[0]
	var keys := ["Q", "E", "R"]
	for i in mini(_ability_buttons.size(), u.abilities.size()):
		var a := Content.get_entry("abilities", u.abilities[i])
		var cd := u.cooldown_left(u.abilities[i])
		_ability_buttons[i].text = "[%s] %s%s" % [keys[i], a.get("name", ""), " %ds" % ceili(cd) if cd > 0.0 else ""]
		_ability_buttons[i].disabled = cd > 0.0 or u.energy < float(a.get("energy", 0))
	var consumables: Array = Game.loadout.get("consumables", [])
	for i in mini(_item_buttons.size(), consumables.size()):
		_item_buttons[i].text = "[%s] x%d" % [["Z", "X"][i], _level.item_count(consumables[i])]


# --- Dựng giao diện -------------------------------------------------------------------------

func _add_card(unit: Unit) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(156, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var role := Roles.role_of(unit.char_id)
	var words := unit.display_name().split(" ")
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	for text_info in [["%d. %s" % [_cards.size() + 1, words[words.size() - 1]], 14, Color.WHITE], [Roles.name_of(role), 12, Roles.color_of(role)]]:
		var l := UI.label(text_info[0], text_info[1], text_info[2])
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		names.add_child(l)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var portrait := UI.portrait(unit.char_id, 30)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(portrait)
	head.add_child(names)
	box.add_child(head)
	var hp := _bar(Color("#7CFFB2"), 7)
	var energy := _bar(Color("#00E5FF"), 3)
	var state := UI.label("", 11, Color("#8FA3BF"))
	state.autowrap_mode = TextServer.AUTOWRAP_OFF
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hp)
	box.add_child(energy)
	box.add_child(state)
	panel.gui_input.connect(_on_card_input.bind(unit))
	_cards_box.add_child(panel)
	_cards.append({"unit": unit, "panel": panel, "hp": hp, "energy": energy, "state": state})


func _on_card_input(e: InputEvent, unit: Unit) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and unit.is_active():
		_level.controller.toggle(unit, Input.is_key_pressed(KEY_SHIFT))
		if e.double_click:
			_level.controller.focus(unit)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var info := VBoxContainer.new()
	info.position = Vector2(16, 12)
	root.add_child(info)
	_info_label = UI.label("", 15)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_timer_label = UI.label("", 18)
	_timer_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.add_child(_info_label)
	info.add_child(_timer_label)

	_objective_label = _centered_label(root, 12, 22)
	_evac_label = _centered_label(root, 96, 20)
	_evac_label.modulate = Color("#FF8A3D")
	_evac_label.visible = false

	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_box.position = Vector2(-300, 48)
	_boss_box.custom_minimum_size = Vector2(600, 0)
	_boss_box.visible = false
	root.add_child(_boss_box)
	_boss_name = UI.label("", 16)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss_bar = _bar(Color("#FF8A3D"), 14)
	_boss_box.add_child(_boss_bar)

	_loot_label = UI.label("", 14)
	_loot_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_loot_label.position = Vector2(-250, 12)
	_loot_label.custom_minimum_size = Vector2(236, 0)
	root.add_child(_loot_label)

	_minimap = Minimap.new()
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.custom_minimum_size = Vector2(240, 170)
	_minimap.size = Vector2(240, 170)
	_minimap.position = Vector2(-256, -196)
	root.add_child(_minimap)

	var bottom := VBoxContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 16
	bottom.offset_bottom = -26
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("separation", 6)
	root.add_child(bottom)
	_actions_box = HBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", 6)
	var commands := HBoxContainer.new()
	commands.add_theme_constant_override("separation", 6)
	commands.add_child(UI.button("Dừng (H)", _stop_selected))
	commands.add_child(UI.button("Giữ vị trí (G)", func(): _level.controller.toggle_hold()))
	commands.add_child(UI.button("Rút lui (B)", func(): _level.call_evac()))
	commands.add_child(_actions_box)
	bottom.add_child(commands)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 6)
	bottom.add_child(_cards_box)

	var help := UI.label("Chuột trái: chọn/kéo khung · Chuột phải: di chuyển/tấn công/khai thác/tương tác/cứu · 1–6 chọn · Ctrl+A cả đội · WASD/mép màn hình: camera · Esc tạm dừng", 12)
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.position = Vector2(-640, -18)
	help.custom_minimum_size = Vector2(1280, 0)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.45)
	root.add_child(help)

	_message_label = _centered_label(root, 140, 18)

	_pause_panel = _center_panel(root)
	var pause_box := _pause_panel.get_child(0)
	pause_box.add_child(UI.label("TẠM DỪNG", 24))
	pause_box.add_child(UI.button("Tiếp tục", func(): resume_pressed.emit()))
	pause_box.add_child(UI.button("Bỏ nhiệm vụ (đón người còn đứng được, mất đồ đã nhặt)", func(): abort_pressed.emit()))

	_result_panel = _center_panel(root)
	var result_box := _result_panel.get_child(0)
	_result_title = UI.label("", 28)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_box.add_child(_result_title)
	_result_body = UI.rich("")
	_result_body.custom_minimum_size = Vector2(520, 0)
	result_box.add_child(_result_body)
	result_box.add_child(UI.button("Về tàu Âu Cơ", func(): return_pressed.emit()))


func _centered_label(root: Control, y: float, font_size: int) -> Label:
	var l := UI.label("", font_size)
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.position = Vector2(-450, y)
	l.custom_minimum_size = Vector2(900, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func _bar(color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(130, height)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	return bar


func _center_panel(root: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	root.add_child(panel)
	return panel
