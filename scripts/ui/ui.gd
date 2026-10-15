class_name UI
extends RefCounted
## Hàm tiện ích dựng giao diện bằng code (giữ các scene UI gọn và theo dữ liệu).


static func label(text: String, size: int = 0, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


static func rich(text: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.text = text
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


static func button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.pressed.connect(callback)
	return b


static func card(children: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	for c in children:
		box.add_child(c)
	return panel


static func hbox(children: Array, separation: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	for c in children:
		# Nhãn tự xuống dòng trong HBox sẽ bị co còn 1 ký tự -> tắt wrap cho nhãn ngắn
		if c is Label and c.autowrap_mode != TextServer.AUTOWRAP_OFF:
			c.autowrap_mode = TextServer.AUTOWRAP_OFF
		if c is Button:
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(c)
	return box


static func scroll_list() -> Array:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	return [scroll, list]


static func icon(texture: Texture2D, size: int = 40) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r


static func portrait(char_id: String, size: int = 56) -> TextureRect:
	var data := Content.get_entry("characters", char_id)
	var path := "res://assets/characters/%s_stand.png" % data.get("sprite", "survivor")
	var r := icon(load(path) if ResourceLoader.exists(path) else null, size)
	r.modulate = Color(data.get("tint", "#FFFFFF"))
	return r


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func color_hex(c: String) -> String:
	return "[color=%s]" % c


## Font của theme dự án (hỗ trợ tiếng Việt) để vẽ chữ trong _draw().
static func font() -> Font:
	var theme := ThemeDB.get_project_theme()
	if theme != null and theme.default_font != null:
		return theme.default_font
	return ThemeDB.fallback_font
