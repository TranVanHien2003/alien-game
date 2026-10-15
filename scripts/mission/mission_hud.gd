class_name MissionHud
extends CanvasLayer
## HUD chỉ huy (bố cục kiểu chiến thuật):
##   trên-trái: tên màn, độ khó, đồng hồ, đợt quái · trên-giữa: mục tiêu + máu boss · trên-phải: đồ đã nhặt
##   trái: danh sách thành viên (bấm để chọn) · dưới-giữa: kỹ năng/vật phẩm + thanh lệnh đội hình
##   dưới-phải: minimap, zoom, tốc độ trò chơi
## Dựng bằng code để bố cục theo dữ liệu.

signal resume_pressed
signal abort_pressed
signal return_pressed

const PANEL_BG := Color(0.04, 0.06, 0.1, 0.88)
const GOLD := Color("#C9A06A")

var _level: Node
var _info_label: Label
var _timer_label: Label
var _objective_label: Label
var _loot_label: Label
var _message_label: Label
var _boss_box: VBoxContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _roster: VBoxContainer
var _cards: Array = []  # [{unit, panel, hp, energy, state}]
var _actions_box: HBoxContainer
var _ability_buttons: Array = []
var _item_buttons: Array = []
var _formation_buttons: Dictionary = {}
var _speed_buttons: Dictionary = {}
var _minimap: Minimap
var _evac_label: Label
var _pause_panel: PanelContainer
var _result_panel: PanelContainer
var _result_title: Label
var _result_body: RichTextLabel
var _message_time := 0.0
var _auto_all: Button
var _auto_evac: Button


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
	_highlight_formation()
	_highlight_speed()
	show_message("Đổ bộ xuống %s. Chuột trái chọn, chuột phải ra lệnh." % loc.get("name", ""))


func add_unit_card(unit: Unit) -> void:
	_add_card(unit)


## Phần sau bảng kết quả: thuộc tính tăng, kỳ ngộ, và nút thu nhận người lạ.
func show_growth(growth: Dictionary, relics: Array, guests: Array) -> void:
	var box := _result_panel.get_child(0)
	var lines := PackedStringArray()
	for char_id in growth:
		if growth[char_id] != "":
			lines.append("• %s: %s" % [CrewSystem.display_name(char_id), growth[char_id]])
	for text in relics:
		lines.append("[color=#C08CFF]✦ %s[/color]" % text)
	if not lines.is_empty():
		var growth_label := UI.rich("[b]Trưởng thành sau chuyến đi:[/b]\n" + "\n".join(lines))
		growth_label.custom_minimum_size = Vector2(520, 0)
		box.add_child(growth_label)
		box.move_child(growth_label, box.get_child_count() - 2)
	for guest_id in guests:
		var data := Content.get_entry("characters", guest_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.portrait_bust(guest_id, 44))
		var top := AttributeSystem.best_roles_for(AttributeSystem.all_values(Game, guest_id), 2).map(func(r): return Roles.name_of(r))
		row.add_child(UI.rich("[b]%s[/b] — %s\nHợp vai: %s" % [data.get("name", ""), data.get("title", ""), ", ".join(top)]))
		var accept := UI.button("Thu nhận", func(): pass)
		var reject := UI.button("Để họ đi", func(): pass)
		accept.pressed.connect(func():
			_level.decide_recruit(guest_id, true)
			row.queue_free())
		reject.pressed.connect(func():
			_level.decide_recruit(guest_id, false)
			row.queue_free())
		row.add_child(accept)
		row.add_child(reject)
		box.add_child(row)
		box.move_child(row, box.get_child_count() - 2)


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
	_message_time -= delta / maxf(0.1, Engine.time_scale)
	_message_label.modulate.a = clampf(_message_time, 0.0, 1.0)
	if _level == null:
		return
	var left: float = _level.seconds_left()
	_timer_label.text = "⏱ %d:%02d   Đợt quái tiếp: %d:%02d" % [int(left) / 60, int(left) % 60, int(_level.next_wave_in()) / 60, int(_level.next_wave_in()) % 60]
	_timer_label.modulate = Color("#FF5A5A") if left < 90.0 else Color.WHITE
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
			_:
				if u.order.get("auto", false):
					state = "⚙ " + u.order.get("task", "")
				else:
					state = {"idle": "Sẵn sàng" if not u.auto else "⚙ Đang suy nghĩ", "move": "Di chuyển", "advance": "Tiến công", "attack": "Tấn công", "mine": "Khai thác", "interact": "Làm việc", "revive": "Cứu người", "evac": "Rút lui"}.get(u.order.type, "")
					if u.order.get("manual", false) and u.order.type != "idle":
						state = "★ " + state
		card.state.text = state + (" · Giữ" if u.hold_position and u.is_active() else "")
		card.panel.modulate = Color(1, 1, 1) if u.is_active() else Color(1, 0.6, 0.7) if u.state == Unit.State.DOWNED else Color(0.5, 0.5, 0.5)
		card.panel.self_modulate = Color("#B4FF39") if u.selected else Color.WHITE
		card.auto.set_pressed_no_signal(u.auto)
		card.auto.modulate = Color("#B4FF39") if u.auto else Color(1, 1, 1, 0.5)
	_update_action_labels()
	if _auto_all:
		_auto_all.self_modulate = GOLD if _level.units.any(func(u): return u.auto) else Color.WHITE
		_auto_evac.self_modulate = GOLD if _level.autopilot and _level.autopilot.auto_evac else Color.WHITE


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
	for i in u.abilities.size():
		var b := UI.button("", _cast.bind(i))
		b.tooltip_text = Content.get_entry("abilities", u.abilities[i]).get("description", "")
		b.add_theme_font_size_override("font_size", 14)
		_actions_box.add_child(b)
		_ability_buttons.append(b)
	var consumables: Array = Game.loadout.get("consumables", [])
	for i in consumables.size():
		var b := UI.button("", _use_item.bind(i))
		b.icon = Inventory.icon(consumables[i])
		b.add_theme_constant_override("icon_max_width", 24)
		b.add_theme_font_size_override("font_size", 14)
		b.tooltip_text = Content.get_entry("items", consumables[i]).get("description", "")
		_actions_box.add_child(b)
		_item_buttons.append(b)
	_update_action_labels()


func _cast(slot: int) -> void:
	_level.controller.cast(slot)


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


func _highlight_formation() -> void:
	for key in _formation_buttons:
		_formation_buttons[key].self_modulate = GOLD if _level and _level.controller.formation == key else Color.WHITE


func _highlight_speed() -> void:
	for key in _speed_buttons:
		_speed_buttons[key].self_modulate = GOLD if _level and is_equal_approx(_level.game_speed, key) else Color.WHITE


# --- Dựng giao diện -------------------------------------------------------------------------

func _panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(GOLD, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", style)
	p.custom_minimum_size = min_size
	return p


func _add_card(unit: Unit) -> void:
	var panel := _panel(Vector2(196, 0))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var portrait := UI.portrait_bust(unit.char_id, 34)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)
	var role := Roles.role_of(unit.char_id)
	var words := unit.display_name().split(" ")
	var name := UI.label("%d. %s · %s" % [_cards.size() + 1, words[words.size() - 1], Roles.name_of(role)], 12, Roles.color_of(role))
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name)
	var auto_btn := Button.new()
	auto_btn.toggle_mode = true
	auto_btn.button_pressed = unit.auto
	auto_btn.text = "AUTO"
	auto_btn.focus_mode = Control.FOCUS_NONE
	auto_btn.add_theme_font_size_override("font_size", 9)
	auto_btn.custom_minimum_size = Vector2(38, 20)
	auto_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	auto_btn.add_theme_stylebox_override("normal", _tight_style(Color(0.1, 0.13, 0.22)))
	auto_btn.add_theme_stylebox_override("pressed", _tight_style(Color(0.1, 0.35, 0.15)))
	auto_btn.add_theme_stylebox_override("hover", _tight_style(Color(0.12, 0.2, 0.32)))
	auto_btn.tooltip_text = "Tự động làm việc theo vai trò"
	auto_btn.toggled.connect(func(on):
		unit.auto = on
		if not on and unit.order.get("auto", false):
			unit.stop())
	var hp := _bar(Color("#7CFFB2"), 6, 130)
	var energy := _bar(Color("#00E5FF"), 3, 130)
	var state := UI.label("", 11, Color("#8FA3BF"))
	state.autowrap_mode = TextServer.AUTOWRAP_OFF
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hp)
	box.add_child(energy)
	box.add_child(state)
	row.add_child(auto_btn)
	panel.gui_input.connect(_on_card_input.bind(unit))
	_roster.add_child(panel)
	_cards.append({"unit": unit, "panel": panel, "hp": hp, "energy": energy, "state": state, "auto": auto_btn})


func _on_card_input(e: InputEvent, unit: Unit) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and unit.is_active():
		_level.controller.toggle(unit, Input.is_key_pressed(KEY_SHIFT))
		if e.double_click:
			_level.controller.focus(unit)


func _command_button(label: String, icon_name: String, tooltip: String, callback: Callable) -> Button:
	var b := Button.new()
	b.icon = UI.ui_icon(icon_name)
	b.text = label
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_constant_override("icon_max_width", 26)
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_constant_override("h_separation", 0)
	b.add_theme_stylebox_override("normal", _tight_style(Color(0.1, 0.13, 0.22)))
	b.add_theme_stylebox_override("hover", _tight_style(Color(0.12, 0.2, 0.32)))
	b.add_theme_stylebox_override("pressed", _tight_style(Color(0, 0.45, 0.55)))
	b.custom_minimum_size = Vector2(56, 54)
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	return b


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Trên-trái: thông tin màn
	var info_panel := _panel()
	info_panel.position = Vector2(12, 10)
	root.add_child(info_panel)
	var info := VBoxContainer.new()
	info_panel.add_child(info)
	_info_label = UI.label("", 14)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_timer_label = UI.label("", 16)
	_timer_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.add_child(_info_label)
	info.add_child(_timer_label)

	_objective_label = _centered_label(root, 12, 21)
	_evac_label = _centered_label(root, 96, 20)
	_evac_label.modulate = Color("#FF8A3D")
	_evac_label.visible = false

	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_box.position = Vector2(-260, 46)
	_boss_box.custom_minimum_size = Vector2(520, 0)
	_boss_box.visible = false
	root.add_child(_boss_box)
	_boss_name = UI.label("", 15)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss_bar = _bar(Color("#FF8A3D"), 12, 520)
	_boss_box.add_child(_boss_bar)

	_loot_label = UI.label("", 13)
	_loot_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_loot_label.position = Vector2(-236, 12)
	_loot_label.custom_minimum_size = Vector2(224, 0)
	root.add_child(_loot_label)

	# Trái: danh sách thành viên
	_roster = VBoxContainer.new()
	_roster.position = Vector2(12, 92)
	_roster.add_theme_constant_override("separation", 4)
	root.add_child(_roster)

	# Dưới-giữa: kỹ năng + thanh lệnh
	var bottom := VBoxContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 216
	bottom.offset_right = 976
	bottom.offset_bottom = -10
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("separation", 6)
	root.add_child(bottom)
	_actions_box = HBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", 6)
	bottom.add_child(_actions_box)
	var bar_panel := _panel()
	bottom.add_child(bar_panel)
	var commands := HBoxContainer.new()
	commands.add_theme_constant_override("separation", 4)
	bar_panel.add_child(commands)
	for f in [["wedge", "Nêm", "arrowUp", "mũi nhọn"], ["line", "Ngang", "barsHorizontal", "hàng ngang"], ["column", "Dọc", "barsVertical", "hàng dọc"], ["spread", "Tản", "massiveMultiplayer", "tản ra"]]:
		var b := _command_button(f[1], f[2], "Đội hình " + f[3], func():
			_level.controller.set_formation(f[0])
			_highlight_formation())
		_formation_buttons[f[0]] = b
		commands.add_child(b)
	commands.add_child(VSeparator.new())
	commands.add_child(_command_button("Tiến", "target", "Tiến tới con trỏ, gặp quái thì dừng lại bắn", func(): _level.controller.advance(false)))
	commands.add_child(_command_button("Xung kích", "fastForward", "Tăng tốc + sát thương 6 giây, lao về phía con trỏ", func(): _level.controller.advance(true)))
	commands.add_child(_command_button("Giữ", "locked", "Giữ vị trí, không đuổi theo quái", func(): _level.controller.toggle_hold()))
	commands.add_child(_command_button("Lùi", "arrowDown", "Lùi xa khỏi quái gần nhất", func(): _level.controller.fall_back()))
	commands.add_child(_command_button("Dừng", "stop", "Dừng mọi lệnh", _stop_selected))
	commands.add_child(_command_button("Rút lui", "exitLeft", "Cả đội về tàu con thoi", func(): _level.call_evac()))
	commands.add_child(VSeparator.new())
	_auto_all = _command_button("Tự động", "gear", "Bật/tắt tự động cho các thành viên đang chọn (hoặc cả đội nếu không chọn ai)", _toggle_auto_all)
	commands.add_child(_auto_all)
	_auto_evac = _command_button("Tự rút", "return", "Tự rút lui khi xong mục tiêu / sắp hết giờ", func():
		_level.autopilot.auto_evac = not _level.autopilot.auto_evac
		show_message("Tự rút lui: " + ("bật" if _level.autopilot.auto_evac else "tắt")))
	commands.add_child(_auto_evac)

	# Dưới-phải: minimap + zoom + tốc độ
	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_top = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -300
	right.offset_right = -12
	right.offset_bottom = -10
	right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	right.add_theme_constant_override("separation", 4)
	root.add_child(right)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 3)
	right.add_child(controls)
	for z in [["zoomOut", 1.0 / 1.25], ["zoomIn", 1.25]]:
		var b := _small_button("", z[0], func(): _level.controller.zoom_by(z[1]))
		controls.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	controls.add_child(_small_button("", "pause", func(): _level._toggle_pause()))
	for sp in [0.5, 1.0, 2.0]:
		var b := _small_button("×%s" % ("½" if sp == 0.5 else str(int(sp))), "", func():
			_level.set_speed(sp)
			_highlight_speed())
		_speed_buttons[sp] = b
		controls.add_child(b)
	var mini_panel := _panel()
	right.add_child(mini_panel)
	_minimap = Minimap.new()
	_minimap.custom_minimum_size = Vector2(234, 164)
	_minimap.size = Vector2(234, 164)
	mini_panel.add_child(_minimap)

	_message_label = _centered_label(root, 140, 18)

	_pause_panel = _center_panel(root)
	var pause_box := _pause_panel.get_child(0)
	pause_box.add_child(UI.label("TẠM DỪNG", 24))
	pause_box.add_child(UI.label("Chuột trái: chọn/kéo khung · Chuột phải: lệnh theo ngữ cảnh · 1–6 chọn · Ctrl+A cả đội\nQ/E/R kỹ năng · Z/X vật phẩm · G giữ · H dừng · B rút lui · WASD/mép màn hình/lăn chuột: camera", 14, Color("#8FA3BF")))
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


func _toggle_auto_all() -> void:
	var sel: Array = _level.controller.selected()
	var targets: Array = sel if not sel.is_empty() else _level.units
	var on := not targets.all(func(u): return u.auto)
	for u in targets:
		u.auto = on
		if not on and u.order.get("auto", false):
			u.stop()
	show_message("Tự động: %s (%d người)" % ["BẬT" if on else "TẮT", targets.size()])


func _tight_style(color: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.border_color = Color(0, 0.9, 1, 0.5)
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	st.content_margin_left = 4
	st.content_margin_right = 4
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	return st


func _stop_selected() -> void:
	for u in _level.controller.selected():
		u.stop()


func _small_button(text: String, icon_name: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	if icon_name != "":
		b.icon = UI.ui_icon(icon_name)
		b.add_theme_constant_override("icon_max_width", 18)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_stylebox_override("normal", _tight_style(Color(0.1, 0.13, 0.22)))
	b.add_theme_stylebox_override("hover", _tight_style(Color(0.12, 0.2, 0.32)))
	b.add_theme_stylebox_override("pressed", _tight_style(Color(0, 0.45, 0.55)))
	b.custom_minimum_size = Vector2(34, 28)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	return b


func _centered_label(root: Control, y: float, font_size: int) -> Label:
	var l := UI.label("", font_size)
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.position = Vector2(-450, y)
	l.custom_minimum_size = Vector2(900, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(l)
	return l


func _bar(color: Color, height: int, width: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, height)
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
