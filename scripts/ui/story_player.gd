class_name StoryPlayer
extends CanvasLayer
## Dẫn truyện kiểu visual novel: nền minh họa, chân dung hai bên (người đang nói sáng lên),
## bảng tên, khung thoại với chữ hiện dần, nút Bỏ qua / Tự động / Nhật ký, và lựa chọn.
##
## play(beats, choices):
##   beats:   [{speaker: id nhân vật | "", text, side: "left"|"right" (tùy chọn), bg: tên nền (tùy chọn)}]
##   choices: [{text, index}] — rỗng nếu chỉ là đoạn hội thoại
## Tín hiệu: choice_made(index) khi chọn, finished khi hết (và không có lựa chọn).
## Mọi câu thoại được ghi vào Game (nhật ký) để xem lại trong Backlog.

signal finished
signal choice_made(index: int)

const BG_DIR := "res://assets/backgrounds/%s.jpg"
const PORTRAIT_DIR := "res://assets/portraits/%s.png"
const PORTRAIT_HEIGHT := 470.0

var chars_per_second := 48.0
var auto_mode := false

var _beats: Array = []
var _choices: Array = []
var _index := -1
var _typing := false
var _visible_chars := 0.0
var _auto_wait := 0.0
var _left_id := ""
var _right_id := ""

var _root: Control
var _bg_a: TextureRect
var _bg_b: TextureRect
var _left: TextureRect
var _right: TextureRect
var _box: PanelContainer
var _name_plate: PanelContainer
var _name_label: Label
var _text: RichTextLabel
var _arrow: Label
var _choice_box: VBoxContainer
var _auto_button: Button
var _backlog: Backlog
var _t := 0.0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func is_playing() -> bool:
	return visible


func play(beats: Array, choices: Array = []) -> void:
	_beats = beats
	_choices = choices
	_index = -1
	visible = true
	_choice_box.visible = false
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.25)
	_next()


# --- Điều khiển ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _backlog.visible:
		return
	var advance: bool = event.is_action_pressed("ui_accept") or event.is_action_pressed("advance_year") \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if advance:
		get_viewport().set_input_as_handled()
		_advance()


func _advance() -> void:
	if _choice_box.visible:
		return
	if _typing:
		_finish_typing()
	else:
		_next()


func _skip() -> void:
	# Ghi phần còn lại vào nhật ký rồi nhảy tới lựa chọn / kết thúc
	if _typing:
		_finish_typing()
	while _index < _beats.size() - 1:
		_index += 1
		_record(_beats[_index])
	# Hiện câu cuối (thường là phần mô tả trước lựa chọn) cho người chơi đọc
	if not _beats.is_empty() and not _choices.is_empty():
		_show_beat(_beats[_beats.size() - 1])
		_finish_typing()
	_end_of_beats()


func _next() -> void:
	_index += 1
	if _index >= _beats.size():
		_end_of_beats()
		return
	var beat: Dictionary = _beats[_index]
	_record(beat)
	_show_beat(beat)


func _end_of_beats() -> void:
	if not _choices.is_empty():
		_show_choices()
		return
	_close()
	finished.emit()


func _close() -> void:
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): visible = false)


func _record(beat: Dictionary) -> void:
	Game.add_story(beat.get("speaker", ""), beat.get("text", ""))


# --- Hiển thị -------------------------------------------------------------------------

func _show_beat(beat: Dictionary) -> void:
	if beat.has("bg"):
		set_background(beat.bg)
	var speaker: String = beat.get("speaker", "")
	var character := Content.get_entry("characters", speaker)
	_name_plate.visible = speaker != ""
	_name_label.text = character.get("name", speaker)
	if speaker != "" and character.has("portrait"):
		var side: String = beat.get("side", "")
		if side == "":
			side = "left" if speaker == _left_id else ("right" if speaker == _right_id else ("left" if _left_id == "" else "right"))
		_set_portrait(side, speaker)
	_highlight(speaker)
	var text: String = beat.get("text", "")
	_text.text = ("[i]%s[/i]" % text) if speaker == "" else text
	_text.visible_characters = 0
	_visible_chars = 0.0
	_typing = true
	_arrow.visible = false
	_auto_wait = 0.0


func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1
	_arrow.visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_arrow.position.y = sin(_t * 5.0) * 4.0
	if _typing:
		_visible_chars += delta * chars_per_second
		_text.visible_characters = int(_visible_chars)
		if _visible_chars >= _text.get_total_character_count():
			_finish_typing()
	elif auto_mode and not _choice_box.visible:
		_auto_wait += delta
		if _auto_wait > 1.2 + _text.get_total_character_count() / 60.0:
			_next()


func set_background(name: String) -> void:
	var path := BG_DIR % name
	if not ResourceLoader.exists(path):
		return
	# Chuyển cảnh mờ dần giữa hai lớp nền
	_bg_b.texture = _bg_a.texture
	_bg_b.modulate.a = 1.0
	_bg_a.texture = load(path)
	var tween := create_tween()
	tween.tween_property(_bg_b, "modulate:a", 0.0, 0.5)


func _set_portrait(side: String, speaker: String) -> void:
	var rect := _left if side == "left" else _right
	if (side == "left" and _left_id == speaker) or (side == "right" and _right_id == speaker):
		return
	if side == "left":
		_left_id = speaker
	else:
		_right_id = speaker
	var path := PORTRAIT_DIR % Content.get_entry("characters", speaker).get("portrait", "")
	rect.texture = load(path) if ResourceLoader.exists(path) else null
	rect.flip_h = side == "right"
	if rect.texture == null:
		return
	# Kích thước theo tỉ lệ ảnh, đáy chân dung nằm sau mép trên khung thoại
	# Chân dung nửa người (ngang) nhỏ hơn chân dung toàn thân (dọc)
	var aspect := rect.texture.get_width() / float(rect.texture.get_height())
	var h := PORTRAIT_HEIGHT * (0.78 if aspect > 1.0 else 1.0)
	var w := h * aspect
	rect.size = Vector2(w, h)
	rect.pivot_offset = Vector2(w / 2.0, h)
	var target_x := 40.0 if side == "left" else 1280.0 - 40.0 - w
	rect.position = Vector2(target_x, 540.0 - h)
	# Trượt vào từ mép
	rect.position.x += -80.0 if side == "left" else 80.0
	rect.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(rect, "position:x", target_x, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(rect, "modulate:a", 1.0, 0.3)


func _highlight(speaker: String) -> void:
	for pair in [[_left, _left_id], [_right, _right_id]]:
		var rect: TextureRect = pair[0]
		if rect.texture == null:
			continue
		var active: bool = pair[1] == speaker
		var tween := create_tween().set_parallel()
		tween.tween_property(rect, "self_modulate", Color.WHITE if active else Color(0.45, 0.47, 0.55), 0.2)
		tween.tween_property(rect, "scale", Vector2.ONE * (1.0 if active else 0.96), 0.2)


func _show_choices() -> void:
	UI.clear(_choice_box)
	_choice_box.visible = true
	_arrow.visible = false
	for c in _choices:
		var b := UI.button(c.text, _on_choice.bind(c))
		b.custom_minimum_size = Vector2(620, 50)
		b.add_theme_font_size_override("font_size", 19)
		_choice_box.add_child(b)
	_choice_box.modulate.a = 0.0
	create_tween().tween_property(_choice_box, "modulate:a", 1.0, 0.2)


func _on_choice(choice: Dictionary) -> void:
	_choice_box.visible = false
	Game.add_story("", "▸ " + choice.text, "choice")
	_choices = []
	Sfx.play("ui_click")
	choice_made.emit(choice.index)


## Phát tiếp đoạn mới (ví dụ kết quả lựa chọn) mà không đóng cảnh.
func continue_with(beats: Array, choices: Array = []) -> void:
	_beats = beats
	_choices = choices
	_index = -1
	_next()


func clear_portraits() -> void:
	_left_id = ""
	_right_id = ""
	_left.texture = null
	_right.texture = null


# --- Dựng giao diện -------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(black)
	for i in 2:
		var bg := TextureRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(bg)
		if i == 0:
			_bg_a = bg
		else:
			_bg_b = bg
	# Làm tối nhẹ phía dưới để khung thoại nổi bật
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0.4)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	_left = _portrait_rect()
	_right = _portrait_rect()

	_box = PanelContainer.new()
	_box.position = Vector2(110, 500)
	_box.size = Vector2(1060, 190)
	_box.custom_minimum_size = Vector2(1060, 190)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.96, 0.93, 0.93)
	style.set_corner_radius_all(16)
	style.border_color = Color(1, 1, 1, 0.9)
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 34
	style.content_margin_bottom = 20
	_box.add_theme_stylebox_override("panel", style)
	_root.add_child(_box)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	_text.add_theme_color_override("default_color", Color("#5A3E2B"))
	_text.add_theme_font_size_override("normal_font_size", 25)
	_text.add_theme_font_size_override("italics_font_size", 24)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_text)

	_name_plate = PanelContainer.new()
	_name_plate.position = Vector2(140, 478)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color("#C9A06A")
	plate.border_color = Color("#8A6236")
	plate.set_border_width_all(2)
	plate.set_corner_radius_all(4)
	plate.content_margin_left = 22
	plate.content_margin_right = 30
	plate.content_margin_top = 4
	plate.content_margin_bottom = 4
	plate.shadow_color = Color(0, 0, 0, 0.3)
	plate.shadow_size = 4
	_name_plate.add_theme_stylebox_override("panel", plate)
	_name_label = UI.label("", 22, Color("#FFFFFF"))
	_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_name_label.add_theme_color_override("font_shadow_color", Color(0.3, 0.18, 0.05, 0.8))
	_name_label.add_theme_constant_override("shadow_offset_y", 2)
	_name_plate.add_child(_name_label)
	_root.add_child(_name_plate)

	var arrow_holder := Control.new()
	arrow_holder.position = Vector2(1130, 655)
	_root.add_child(arrow_holder)
	_arrow = UI.label("▼", 22, Color("#8A6236"))
	arrow_holder.add_child(_arrow)

	var top := HBoxContainer.new()
	top.position = Vector2(880, 16)
	top.add_theme_constant_override("separation", 8)
	_root.add_child(top)
	var log_button := _top_button("Nhật ký", "menuList")
	log_button.pressed.connect(func(): _backlog.open())
	_auto_button = _top_button("Tự động", "right")
	_auto_button.toggle_mode = true
	_auto_button.toggled.connect(func(on): auto_mode = on)
	var skip := _top_button("Bỏ qua", "next")
	skip.pressed.connect(_skip)
	for b in [log_button, _auto_button, skip]:
		top.add_child(b)

	_choice_box = VBoxContainer.new()
	_choice_box.position = Vector2(330, 150)
	_choice_box.custom_minimum_size = Vector2(620, 0)
	_choice_box.add_theme_constant_override("separation", 10)
	_root.add_child(_choice_box)

	_backlog = Backlog.new()
	add_child(_backlog)


func _portrait_rect() -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r


func _top_button(text: String, icon_name: String) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = UI.ui_icon(icon_name)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 18)
	b.flat = true
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	b.add_theme_font_size_override("font_size", 16)
	return b
