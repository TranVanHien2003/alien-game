class_name MissionHud
extends CanvasLayer
## HUD của màn action: máu, năng lượng, vũ khí, kỹ năng, vật phẩm, mục tiêu, thanh máu boss,
## menu tạm dừng và bảng kết quả. Dựng bằng code để dễ đổi bố cục theo dữ liệu.

signal resume_pressed
signal abort_pressed
signal return_pressed

var _player: Player
var _hp_bar: ProgressBar
var _energy_bar: ProgressBar
var _weapon_label: Label
var _objective_label: Label
var _loot_label: Label
var _hotbar_label: Label
var _message_label: Label
var _boss_box: VBoxContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _pause_panel: PanelContainer
var _result_panel: PanelContainer
var _result_title: Label
var _result_body: RichTextLabel
var _message_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func setup(_level: Node, player: Player, mission: Dictionary, entry: Dictionary) -> void:
	_player = player
	player.hp_changed.connect(_set_bar.bind(_hp_bar))
	player.energy_changed.connect(_set_bar.bind(_energy_bar))
	player.weapon_changed.connect(_on_weapon_changed)
	player.message.connect(show_message)
	_hp_bar.max_value = player.stats.max_hp
	_hp_bar.value = player.hp
	_energy_bar.max_value = player.stats.max_energy
	_energy_bar.value = player.energy
	_on_weapon_changed(player.current_weapon())
	var location := Content.get_entry("locations", entry.location)
	show_message("%s — %s (Đội trưởng: %s)" % [mission.get("name", ""), location.get("name", ""), CrewSystem.display_name(entry.leader)])


func track_boss(boss: Enemy) -> void:
	_boss_box.visible = true
	_boss_name.text = boss.data.get("name", "BOSS")
	_boss_bar.max_value = boss.max_hp
	_boss_bar.value = boss.hp
	boss.hp_changed.connect(_set_bar.bind(_boss_bar))
	boss.died.connect(func(_b): _boss_box.visible = false)


func _set_bar(value: float, max_value: float, bar: ProgressBar) -> void:
	bar.max_value = max_value
	bar.value = value


func _on_weapon_changed(item_id: String) -> void:
	_weapon_label.text = "Vũ khí: " + Content.get_entry("items", item_id).get("name", item_id)


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
	_message_time = 2.5


func show_pause(paused: bool) -> void:
	_pause_panel.visible = paused


func show_result(report: Dictionary, loot: Dictionary, leader_down: bool) -> void:
	_pause_panel.visible = false
	_result_panel.visible = true
	var success: bool = report.get("success", false)
	_result_title.text = "NHIỆM VỤ THÀNH CÔNG" if success else ("ĐỘI TRƯỞNG GỤC NGÃ" if leader_down else "NHIỆM VỤ THẤT BẠI")
	_result_title.modulate = Color("#B4FF39") if success else Color("#FF2BD6")
	var lines := PackedStringArray([report.get("title", "")])
	if loot.is_empty():
		lines.append("Không mang được gì về tàu.")
	else:
		lines.append("\n[b]Mang về tàu:[/b]")
		for item_id in loot:
			lines.append("• %s x%d" % [Content.get_entry("items", item_id).get("name", item_id), loot[item_id]])
	for char_id in report.get("missing", []):
		lines.append("\n[color=#FF2BD6]⚠ %s mất tích! Hãy mở nhiệm vụ Giải cứu trước khi quá muộn.[/color]" % CrewSystem.display_name(char_id))
	_result_body.text = "\n".join(lines)


func _process(delta: float) -> void:
	_message_time -= delta
	_message_label.modulate.a = clampf(_message_time, 0.0, 1.0)
	if _player == null:
		return
	var parts := PackedStringArray()
	var keys := ["Q", "R"]
	for i in mini(_player.abilities.size(), 2):
		var id: String = _player.abilities[i]
		var cd := _player.cooldown_left(id)
		parts.append("[%s] %s%s" % [keys[i], Content.get_entry("abilities", id).get("name", id), " (%.0fs)" % cd if cd > 0.0 else ""])
	for i in mini(_player.consumables.size(), 2):
		var id: String = _player.consumables[i]
		parts.append("[%d] %s x%d" % [i + 3, Content.get_entry("items", id).get("name", id), _player.count_item.call(id)])
	_hotbar_label.text = "    ".join(parts)


# --- Dựng giao diện -------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var status := VBoxContainer.new()
	status.position = Vector2(16, 16)
	status.custom_minimum_size = Vector2(280, 0)
	root.add_child(status)
	_hp_bar = _bar(Color("#FF2BD6"))
	_energy_bar = _bar(Color("#00E5FF"))
	status.add_child(_labeled("Máu", _hp_bar))
	status.add_child(_labeled("Năng lượng", _energy_bar))
	_weapon_label = Label.new()
	status.add_child(_weapon_label)

	_objective_label = Label.new()
	_objective_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_objective_label.position = Vector2(-200, 16)
	_objective_label.custom_minimum_size = Vector2(400, 0)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.add_theme_font_size_override("font_size", 22)
	root.add_child(_objective_label)

	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_box.position = Vector2(-300, 56)
	_boss_box.custom_minimum_size = Vector2(600, 0)
	_boss_box.visible = false
	root.add_child(_boss_box)
	_boss_name = Label.new()
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss_bar = _bar(Color("#FF8A3D"))
	_boss_box.add_child(_boss_bar)

	_loot_label = Label.new()
	_loot_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_loot_label.position = Vector2(-260, 16)
	_loot_label.custom_minimum_size = Vector2(244, 0)
	_loot_label.add_theme_font_size_override("font_size", 15)
	root.add_child(_loot_label)

	_hotbar_label = Label.new()
	_hotbar_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar_label.position = Vector2(-450, -48)
	_hotbar_label.custom_minimum_size = Vector2(900, 0)
	_hotbar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_hotbar_label)

	var help := Label.new()
	help.text = "WASD di chuyển · Chuột bắn · Shift lướt · 1/2 đổi súng · E tương tác · Esc tạm dừng"
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.position = Vector2(-450, -22)
	help.custom_minimum_size = Vector2(900, 0)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.5)
	root.add_child(help)

	_message_label = Label.new()
	_message_label.set_anchors_preset(Control.PRESET_CENTER)
	_message_label.position = Vector2(-400, 120)
	_message_label.custom_minimum_size = Vector2(800, 0)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 20)
	root.add_child(_message_label)

	_pause_panel = _center_panel(root)
	var pause_box := _pause_panel.get_child(0)
	var pause_title := Label.new()
	pause_title.text = "TẠM DỪNG"
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_box.add_child(pause_title)
	pause_box.add_child(_button("Tiếp tục", func(): resume_pressed.emit()))
	pause_box.add_child(_button("Bỏ nhiệm vụ (mất đồ đã nhặt)", func(): abort_pressed.emit()))

	_result_panel = _center_panel(root)
	var result_box := _result_panel.get_child(0)
	_result_title = Label.new()
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.add_theme_font_size_override("font_size", 28)
	result_box.add_child(_result_title)
	_result_body = RichTextLabel.new()
	_result_body.bbcode_enabled = true
	_result_body.fit_content = true
	_result_body.custom_minimum_size = Vector2(460, 0)
	result_box.add_child(_result_body)
	result_box.add_child(_button("Về tàu Âu Cơ", func(): return_pressed.emit()))


func _bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(200, 14)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	return bar


func _labeled(text: String, bar: ProgressBar) -> HBoxContainer:
	var box := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(90, 0)
	label.add_theme_font_size_override("font_size", 14)
	box.add_child(label)
	box.add_child(bar)
	return box


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


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	return b
