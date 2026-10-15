class_name Backlog
extends Control
## Nhật ký: xem lại toàn bộ lời thoại, lựa chọn và sự kiện của tàu (lưu trong save).
## Lọc theo: Tất cả / Hội thoại / Sự kiện tàu.

var _list: VBoxContainer
var _scroll: ScrollContainer
var _filter := "all"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := VBoxContainer.new()
	box.position = Vector2(140, 30)
	box.size = Vector2(1000, 660)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var title := UI.label("NHẬT KÝ HÀNH TRÌNH", 26, Color("#C9A06A"))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for f in [["all", "Tất cả"], ["dialogue", "Hội thoại"], ["system", "Sự kiện tàu"]]:
		header.add_child(UI.button(f[1], func():
			_filter = f[0]
			_refresh()))
	header.add_child(UI.button("Đóng ✕", close))
	box.add_child(header)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(1000, 600)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	UI.clear(_list)
	var last_year := -999
	for e in Game.log_entries:
		var kind: String = e.get("kind", "system")
		if _filter == "dialogue" and kind == "system":
			continue
		if _filter == "system" and kind != "system":
			continue
		if int(e.year) != last_year:
			last_year = int(e.year)
			_list.add_child(UI.label("— Năm %d —" % last_year, 15, Color("#5C8DB0")))
		var speaker: String = e.get("speaker", "")
		match kind:
			"dialogue":
				if speaker != "":
					var c := Content.get_entry("characters", speaker)
					var row := HBoxContainer.new()
					row.add_theme_constant_override("separation", 10)
					row.add_child(UI.portrait_bust(speaker, 44))
					row.add_child(UI.rich("[color=#C9A06A][b]%s[/b][/color]\n%s" % [c.get("name", speaker), e.text]))
					_list.add_child(row)
				else:
					_list.add_child(UI.rich("[i][color=#B8C4D6]%s[/color][/i]" % e.text))
			"choice":
				_list.add_child(UI.rich("[color=#B4FF39]%s[/color]" % e.text))
			_:
				_list.add_child(UI.rich("[color=#8FA3BF][font_size=15]• %s[/font_size][/color]" % e.text))
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
