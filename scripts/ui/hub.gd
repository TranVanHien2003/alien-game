extends Control
## Hub trên tàu Âu Cơ: điều hướng bên trái, tài nguyên ở trên, nội dung từng mục ở giữa.
## Sự kiện cốt truyện phát bằng StoryPlayer (kiểu visual novel); sự kiện của tàu hiện dạng thông báo trượt.
## Toàn bộ nội dung từng mục được dựng lại từ Game mỗi khi state_changed.

const MISSION_SCENE := "res://scenes/mission/mission_level.tscn"
const TITLE_SCENE := "res://scenes/title/title.tscn"
const PAGES := [
	["Tổng quan", "home"], ["Phi hành đoàn", "multiplayer"], ["Nhiệm vụ", "target"], ["Nghiên cứu", "signal3"],
	["Kho & Trang bị", "basket"], ["Chế tạo", "wrench"], ["Bản đồ sao", "star"],
]

@onready var _year_label: Label = %YearLabel
@onready var _stats_box: HBoxContainer = %StatsBox
@onready var _tabs: TabContainer = %Tabs
@onready var _nav: VBoxContainer = %Nav
@onready var _advance_button: Button = %AdvanceButton
@onready var _save_button: Button = %SaveButton
@onready var _menu_button: Button = %MenuButton
@onready var _log_button: Button = %LogButton
@onready var _toasts: VBoxContainer = %Toasts
@onready var _overlay: Control = %Overlay
@onready var _overlay_box: VBoxContainer = %OverlayBox

var _lists: Dictionary = {}
var _nav_buttons: Array = []
## Màn hình chuẩn bị nhiệm vụ đang mở: {option, team: []}
var _prep: Dictionary = {}
var _story: StoryPlayer
var _backlog: Backlog
var _last_stats: Dictionary = {}
var _pending_result := ""
## Sự kiện đặc biệt đang phát (lễ trưởng thành / kỳ ngộ)
var _special: Dictionary = {}
var _special_options: Array = []
var _talent_member := ""


func _ready() -> void:
	_tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var group := ButtonGroup.new()
	for i in PAGES.size():
		var parts := UI.scroll_list()
		parts[0].name = PAGES[i][0]
		_tabs.add_child(parts[0])
		_lists[PAGES[i][0]] = parts[1]
		var b := Button.new()
		b.text = "  " + PAGES[i][0]
		b.icon = UI.ui_icon(PAGES[i][1])
		b.add_theme_constant_override("icon_max_width", 22)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 46)
		b.button_pressed = i == 0
		b.pressed.connect(func(): _tabs.current_tab = i)
		_nav.add_child(b)
		_nav_buttons.append(b)
	_advance_button.icon = UI.ui_icon("right")
	_log_button.icon = UI.ui_icon("menuList")
	_save_button.icon = UI.ui_icon("save")
	_menu_button.icon = UI.ui_icon("home")
	for b in [_advance_button, _log_button, _save_button, _menu_button]:
		b.add_theme_constant_override("icon_max_width", 20)
	_advance_button.pressed.connect(_on_advance)
	_save_button.pressed.connect(func():
		SaveManager.save_game()
		_toast("Đã lưu game.", Color("#B4FF39")))
	_menu_button.pressed.connect(func():
		SaveManager.save_game()
		get_tree().change_scene_to_file(TITLE_SCENE))
	_story = StoryPlayer.new()
	add_child(_story)
	_story.choice_made.connect(_on_story_choice)
	_story.finished.connect(_on_story_finished)
	_backlog = Backlog.new()
	add_child(_backlog)
	_log_button.pressed.connect(_backlog.open)
	Game.state_changed.connect(_refresh)
	Game.log_added.connect(_on_log)
	Game.event_started.connect(_show_event)
	Game.game_ended.connect(_show_ending)
	Game.chapter_completed.connect(_show_chapter_end)
	_overlay.visible = false
	_last_stats = Game.stats.duplicate()
	_refresh()
	if not Game.has_flag("intro_seen") and Game.year == int(Game.current_chapter().get("start_year", 0)):
		Game.flags["intro_seen"] = true
		_play_dialogue(Game.current_chapter().get("intro_dialogue", ""))
	elif Game.pending_event != "":
		_show_event(Game.get_pending_event())
	elif Game.ending_id != "":
		_show_ending(Content.get_entry("endings", Game.ending_id))
	elif Game.chapter_done:
		_show_chapter_end(Game.current_chapter())


func _unhandled_input(event: InputEvent) -> void:
	if _story.is_playing() or _backlog.visible:
		return
	if event.is_action_pressed("advance_year") and not _overlay.visible:
		_on_advance()
	elif event.is_action_pressed("quick_save"):
		SaveManager.save_game()
		_toast("Đã lưu nhanh.", Color("#B4FF39"))


func _on_advance() -> void:
	_last_stats = Game.stats.duplicate()
	if Game.advance_year():
		SaveManager.save_game()
		_play_next_special()


# --- Thông báo trượt (thay cho cửa sổ log) ------------------------------------------------

func _on_log(entry: Dictionary) -> void:
	if entry.get("kind", "system") != "system" or _story.is_playing():
		return
	var text: String = entry.text
	var color := Color("#8FA3BF")
	if text.begins_with("⚠") or text.begins_with("✝") or text.contains("THẤT BẠI"):
		color = Color("#FF5A5A")
	elif text.begins_with("✔") or text.begins_with("🔬") or text.begins_with("🛰") or text.begins_with("Nhận"):
		color = Color("#B4FF39")
	_toast(text, color)


func _toast(text: String, color: Color) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.13, 0.95)
	style.border_color = color
	style.border_width_left = 4
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label(text, 15, Color(1, 1, 1, 0.95))
	l.custom_minimum_size = Vector2(330, 0)
	panel.add_child(l)
	_toasts.add_child(panel)
	while _toasts.get_child_count() > 6:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	panel.modulate.a = 0.0
	panel.position.x = 60
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.25)
	tween.tween_interval(4.5)
	tween.tween_property(panel, "modulate:a", 0.0, 0.6)
	tween.tween_callback(panel.queue_free)


# --- Làm mới --------------------------------------------------------------------

func _refresh() -> void:
	var chapter := Game.current_chapter()
	_year_label.text = "Năm %d · Thế hệ %d\n%s" % [Game.year, Game.generation, chapter.get("title", "")]
	UI.clear(_stats_box)
	for stat in Content.stat_ids():
		_stats_box.add_child(_stat_chip(stat))
	_advance_button.disabled = not Game.can_advance()
	_build_overview()
	_build_crew()
	_build_missions()
	_build_research()
	_build_inventory()
	_build_crafting()
	_build_map()


## Ô tài nguyên: tên, giá trị, thanh mức, mũi tên thay đổi so với năm trước.
func _stat_chip(stat: String) -> PanelContainer:
	var def: Dictionary = Content.config.stats[stat]
	var color := Color(def.get("color", "#FFFFFF"))
	var value := Game.get_stat(stat)
	var delta := value - float(_last_stats.get(stat, value))
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.85)
	style.border_color = Color(color, 0.6)
	style.border_width_bottom = 3
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	var name := UI.label(def.get("label", stat), 12, Color(color, 0.85))
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	var arrow := ""
	if absf(delta) >= 0.5:
		arrow = " [color=#B4FF39]▲%d[/color]" % roundi(delta) if delta > 0 else " [color=#FF5A5A]▼%d[/color]" % roundi(-delta)
	var val := UI.rich("[b]%d[/b]%s" % [roundi(value), arrow])
	val.fit_content = true
	val.autowrap_mode = TextServer.AUTOWRAP_OFF
	val.custom_minimum_size = Vector2(72, 0)
	box.add_child(name)
	box.add_child(val)
	var max_v := float(def.get("max", 100))
	if max_v <= 100.0:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(72, 3)
		bar.show_percentage = false
		bar.max_value = max_v
		bar.value = value
		var fill := StyleBoxFlat.new()
		fill.bg_color = color if value > max_v * 0.25 else Color("#FF5A5A")
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.08)
		bar.add_theme_stylebox_override("background", bg)
		box.add_child(bar)
	panel.tooltip_text = "%s: %.1f / %d" % [def.get("label", stat), value, int(max_v)]
	return panel


func _build_overview() -> void:
	var list: VBoxContainer = _lists["Tổng quan"]
	UI.clear(list)
	var chapter := Game.current_chapter()
	var progress := float(Game.year - int(chapter.get("start_year", 0))) / maxf(1.0, float(chapter.get("end_year", 25)) - float(chapter.get("start_year", 0)))
	var hero := UI.card([
		UI.label(chapter.get("title", ""), 24, Color("#C9A06A")),
		UI.label("Hành trình tới Văn Lang · còn %d năm của chương này" % maxi(0, int(chapter.get("end_year", 25)) - Game.year), 15, Color("#8FA3BF")),
	])
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.value = progress * 100.0
	hero.get_child(0).add_child(bar)
	list.add_child(hero)
	var alerts: Array = []
	for char_id in CrewSystem.missing_members(Game):
		alerts.append(UI.rich("[color=#FF5A5A]⚠ [b]%s[/b] mất tích tại %s — còn %d năm để giải cứu.[/color]" % [
			CrewSystem.display_name(char_id),
			Content.get_entry("locations", Game.crew[char_id].missing_at).get("name", ""),
			CrewSystem.years_left_to_rescue(Game, char_id)]))
	for stat in Content.stat_ids():
		var max_v := float(Content.config.stats[stat].get("max", 100))
		if max_v <= 100.0 and Game.get_stat(stat) < 25.0:
			alerts.append(UI.rich("[color=#FF8A3D]⚠ %s đang ở mức nguy hiểm (%d).[/color]" % [Content.stat_label(stat), roundi(Game.get_stat(stat))]))
	if Game.research_current == "":
		alerts.append(UI.rich("[color=#FFC94D]• Chưa chọn dự án nghiên cứu.[/color]"))
	if not alerts.is_empty():
		list.add_child(UI.section("Cần chú ý", alerts))
	var ops: Array = []
	for entry in Game.active_missions:
		ops.append(UI.label("🚀 %s — còn %d năm (%s)" % [Content.get_entry("missions", entry.mission).get("name", ""), entry.years_left, ", ".join(entry.team.map(func(id): return CrewSystem.display_name(id)))], 15))
	if Game.research_current != "":
		var tech := Content.get_entry("tech", Game.research_current)
		ops.append(UI.label("🔬 %s: %d/%d · +%.1f điểm/năm" % [tech.get("name", ""), ResearchSystem.progress(Game, Game.research_current), int(tech.get("cost", 0)), ResearchSystem.points_per_year(Game)], 15))
	ops.append(UI.label("👥 %d/%d thành viên sẵn sàng đổ bộ" % [CrewSystem.available(Game).size(), Game.crew.size()], 15))
	list.add_child(UI.section("Hoạt động", ops))
	# Vài dòng nhật ký gần nhất (xem đầy đủ ở nút Nhật ký)
	var recent: Array = []
	for i in range(Game.log_entries.size() - 1, maxi(-1, Game.log_entries.size() - 7), -1):
		var e: Dictionary = Game.log_entries[i]
		var who: String = Content.get_entry("characters", e.get("speaker", "")).get("name", "")
		recent.append(UI.rich("[color=#5C8DB0]Năm %d[/color]  %s%s" % [e.year, ("[color=#C9A06A]%s:[/color] " % who) if who != "" else "", e.text]))
	var log_btn := UI.button("Mở nhật ký đầy đủ", _backlog.open)
	recent.append(log_btn)
	list.add_child(UI.section("Gần đây", recent))


func _build_crew() -> void:
	var list: VBoxContainer = _lists["Phi hành đoàn"]
	UI.clear(list)
	if _talent_member != "" and Game.crew.has(_talent_member):
		_build_talent_tree(list, _talent_member)
		return
	var food := NutritionSystem.crew_consumption(Game)
	list.add_child(UI.label("Phi hành đoàn tiêu thụ %.2f Lương thực/năm%s" % [food, " — ĐANG ĐÓI" if NutritionSystem.is_hungry(Game) else ""], 14, Color("#FF5A5A") if NutritionSystem.is_hungry(Game) else Color("#8FA3BF")))
	var status_names := {CrewSystem.IDLE: "Trên tàu", CrewSystem.MISSION: "Đang làm nhiệm vụ", CrewSystem.MISSING: "MẤT TÍCH", CrewSystem.TRAINING: "Đang huấn luyện"}
	for char_id in Game.crew:
		var data := Content.get_entry("characters", char_id)
		var member: Dictionary = Game.crew[char_id]
		var child := Lifecycle.is_child(Game, char_id)
		var age := "" if data.get("ageless", false) else " · %d tuổi" % Game.character_age(char_id)
		var group: String = NutritionSystem.age_group(Game, char_id).get("label", "")
		var header := UI.rich("[b]%s[/b] — %s%s · [i]%s[/i]\n[color=#8FA3BF]%s · ăn %.3f/năm · Cấp %d[/color]" % [
			data.get("name", char_id), data.get("title", ""), age, status_names.get(member.status, member.status),
			group, NutritionSystem.consumption(Game, char_id), Talents.level(Game, char_id)])
		var children: Array = [UI.hbox([UI.portrait_bust(char_id, 64), header])]
		children.append(_attribute_bars(char_id))
		if child:
			var years := int(Content.config.get("lifecycle", {}).get("coming_of_age", 16)) - Game.character_age(char_id)
			var hints: Array = AttributeSystem.best_roles_for(AttributeSystem.all_values(Game, char_id), 2).map(func(r): return Roles.name_of(r))
			children.append(UI.rich("[color=#FFC94D]Trẻ em — lễ trưởng thành sau %d năm. Năng khiếu: %s[/color]" % [maxi(0, years), ", ".join(hints)]))
		elif not data.get("ageless", false):
			children.append(_role_row(char_id))
			children.append(_training_row(char_id))
		var skills := PackedStringArray()
		for skill_id in member.skills:
			var skill := Content.get_entry("skills", skill_id)
			skills.append("%s%s %d[/color]" % ["[color=#FF2BD6]" if skill.get("high_tech", false) else "[color=#00E5FF]", skill.get("name", skill_id), member.skills[skill_id]])
		if skills.size() > 0:
			children.append(UI.rich("Kỹ năng: " + " · ".join(skills)))
		if char_id in CrewSystem.available(Game):
			for skill_id in CrewSystem.trainable_skills(Game, char_id):
				children.append(UI.button("Huấn luyện %s (1 năm)" % Content.get_entry("skills", skill_id).name, func():
					CrewSystem.start_training(Game, char_id, skill_id)
					Game.state_changed.emit()))
		list.add_child(UI.card(children))


## 6 thanh thuộc tính (giá trị hiệu lực, phần cộng từ trang bị/tài năng hiện màu sáng hơn).
func _attribute_bars(char_id: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 14)
	for attr in AttributeSystem.ids():
		var def: Dictionary = Content.config.attributes[attr]
		var base := AttributeSystem.base(Game, char_id, attr)
		var total := AttributeSystem.value(Game, char_id, attr)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		var l := UI.label("%s %d%s" % [def.get("short", attr), roundi(total), (" (+%d)" % roundi(total - base)) if total - base >= 1 else ""], 12, Color(def.get("color", "#FFFFFF")))
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		box.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(110, 5)
		bar.show_percentage = false
		bar.max_value = 100
		bar.value = total
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(def.get("color", "#FFFFFF"))
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.08)
		bar.add_theme_stylebox_override("background", bg)
		box.add_child(bar)
		box.tooltip_text = "%s: gốc %.1f, hiệu lực %.1f" % [def.get("label", attr), base, total]
		grid.add_child(box)
	return grid


## Các vai đang có (bấm để chọn vai chính) + giao thêm vai + mở cây tài năng.
func _role_row(char_id: String) -> HBoxContainer:
	var row: Array = [UI.label("Vai:", 14)]
	var member: Dictionary = Game.crew[char_id]
	for role_id in member.get("roles", []):
		var active: bool = role_id == member.get("active_role", "")
		var b := UI.button("%s%s %d%%" % ["★ " if active else "", Roles.name_of(role_id), roundi(AttributeSystem.proficiency(Game, char_id, role_id))], func():
			AttributeSystem.set_active_role(Game, char_id, role_id)
			Game.state_changed.emit())
		b.add_theme_color_override("font_color", Roles.color_of(role_id))
		b.tooltip_text = "Hiệu quả vai ×%.2f — bấm để đặt làm vai chính" % AttributeSystem.efficiency(Game, char_id, role_id)
		row.append(b)
	var assign := OptionButton.new()
	assign.add_item("+ Giao vai...")
	assign.set_item_metadata(0, "")
	for role in Content.all("roles"):
		if AttributeSystem.can_assign(Game, char_id, role.id):
			assign.add_item("%s (%d%%)" % [role.name, roundi(AttributeSystem.proficiency(Game, char_id, role.id))])
			assign.set_item_metadata(assign.item_count - 1, role.id)
	assign.disabled = assign.item_count <= 1
	assign.item_selected.connect(func(i):
		var role_id: String = assign.get_item_metadata(i)
		if role_id != "":
			AttributeSystem.assign_role(Game, char_id, role_id)
			Game.state_changed.emit())
	row.append(assign)
	var tp := Talents.points(Game, char_id)
	var tree := UI.button("Cây tài năng%s" % (" (%d điểm)" % tp if tp > 0 else ""), func():
		_talent_member = char_id
		_build_crew())
	if tp > 0:
		tree.add_theme_color_override("font_color", Color("#FFC94D"))
	row.append(tree)
	return UI.hbox(row)


func _training_row(char_id: String) -> HBoxContainer:
	var pick := OptionButton.new()
	pick.add_item("Không huấn luyện")
	pick.set_item_metadata(0, "")
	var focus: String = Game.crew[char_id].get("training_focus", "")
	for attr in AttributeSystem.ids():
		pick.add_item("Tập %s" % AttributeSystem.label(attr))
		pick.set_item_metadata(pick.item_count - 1, attr)
		if attr == focus:
			pick.select(pick.item_count - 1)
	pick.item_selected.connect(func(i):
		Game.crew[char_id].training_focus = pick.get_item_metadata(i)
		Game.state_changed.emit())
	return UI.hbox([UI.label("Huấn luyện mỗi năm (khi rảnh):", 14, Color("#8FA3BF")), pick])


func _build_talent_tree(list: VBoxContainer, char_id: String) -> void:
	var role_id := Roles.role_of(char_id)
	list.add_child(UI.hbox([
		UI.button("◂ Quay lại", func():
			_talent_member = ""
			_build_crew()),
		UI.label("Cây tài năng — %s · %s · %d điểm" % [CrewSystem.display_name(char_id), Roles.name_of(role_id), Talents.points(Game, char_id)], 20, Color("#C9A06A")),
	]))
	for role in Game.crew[char_id].get("roles", []):
		list.add_child(UI.label(Roles.name_of(role), 18, Roles.color_of(role)))
		for tier in [1, 2, 3]:
			var row: Array = [UI.label("Bậc %d" % tier, 13, Color("#8FA3BF"))]
			for t in Talents.for_role(role).filter(func(x): return int(x.get("tier", 1)) == tier):
				var owned: bool = t.id in Talents.owned(Game, char_id)
				var mods := PackedStringArray()
				for stat in t.get("modifiers", {}):
					mods.append("%s +%s" % [Content.config.combat_stats.get(stat, {}).get("label", stat), CombatStats.format(stat, float(t.modifiers[stat]))])
				for attr in t.get("attributes", {}):
					mods.append("%s +%d" % [AttributeSystem.label(attr), int(t.attributes[attr])])
				if t.get("grants_ability", "") != "":
					mods.append("Kỹ năng: " + Content.get_entry("abilities", t.grants_ability).get("name", ""))
				var learn := func():
					Talents.learn(Game, char_id, t.id)
					Game.state_changed.emit()
				var b := UI.button(("✔ " if owned else "") + "%s (%d)" % [t.name, int(t.get("cost", 1))], learn, owned or not Talents.can_learn(Game, char_id, t.id))
				b.tooltip_text = "\n".join(mods)
				row.append(b)
			list.add_child(UI.hbox(row))
	var rare := Talents.owned(Game, char_id).filter(func(id): return Content.get_entry("talents", id).get("rare", false))
	if not rare.is_empty():
		list.add_child(UI.label("Tài năng hiếm (kỳ ngộ)", 18, Color("#C08CFF")))
		for id in rare:
			var t := Content.get_entry("talents", id)
			list.add_child(UI.rich("[color=#C08CFF]✦ %s[/color] — %s" % [t.name, t.get("description", "")]))


func _role_title(data: Dictionary) -> String:
	return data.get("title", "")


func _build_missions() -> void:
	var list: VBoxContainer = _lists["Nhiệm vụ"]
	UI.clear(list)
	if not _prep.is_empty():
		_build_mission_prep(list)
		return
	var options := MissionSystem.available(Game)
	if options.is_empty():
		list.add_child(UI.label("Không có nhiệm vụ khả dụng. Hãy nghiên cứu hoặc quét không gian để mở thêm.", 16))
	for option in options:
		var m: Dictionary = option.mission
		var location := Content.get_entry("locations", option.location)
		var title: String = m.name + (" " + CrewSystem.display_name(option.target) if option.target != "" else "")
		var hazards: Array = location.get("hazards", []).map(func(h): return Content.config.hazards[h].label)
		var req := PackedStringArray()
		for skill_id in m.get("skills", {}):
			req.append("%s %d" % [Content.get_entry("skills", skill_id).get("name", skill_id), m.skills[skill_id]])
		var d := Difficulty.level(Game, m, option.location)
		var roles: Array = m.get("recommended_roles", {}).keys().map(func(r): return "%s×%d" % [Roles.name_of(r), m.recommended_roles[r]])
		list.add_child(UI.card([
			UI.rich("[b]%s[/b] · %s · Đội %d–%d người · [color=#FFC94D]%s %s[/color]%s" % [title, location.get("name", ""), m.team_size[0], m.team_size[1], Difficulty.stars(d), Difficulty.label(d), (" · %d phút" % roundi(float(m.time_limit) / 60.0)) if m.has("time_limit") else ""]),
			UI.rich("[color=#8FA3BF]Đề cử: %s[/color]" % ", ".join(roles)) if roles.size() > 0 else UI.label(""),
			UI.label(m.get("description", ""), 15, Color("#8FA3BF")),
			UI.rich("Kỹ năng khuyến nghị: %s%s" % [", ".join(req), ("   [color=#FF8A3D]Nguy hiểm: %s[/color]" % ", ".join(hazards)) if hazards.size() > 0 else ""]),
			UI.button("Chuẩn bị đội", func():
				_prep = {"option": option, "team": []}
				_build_missions()),
		]))


func _build_mission_prep(list: VBoxContainer) -> void:
	var option: Dictionary = _prep.option
	var m: Dictionary = option.mission
	var team: Array = _prep.team
	var d := Difficulty.level(Game, m, option.location)
	var size: Array = m.get("team_size", [1, 1])
	list.add_child(UI.label("Chuẩn bị: " + m.name, 22))
	var objective: Dictionary = m.get("objective", {})
	var info := "Độ khó %s %s · Đội %d–%d người" % [Difficulty.stars(d), Difficulty.label(d), size[0], size[1]]
	if m.has("time_limit"):
		info += " · Thời gian %d phút" % roundi(float(m.time_limit) / 60.0)
	if not objective.is_empty():
		info += " · Mục tiêu: %s (%d)" % [objective.get("label", ""), int(objective.get("count", 1))]
	list.add_child(UI.label(info, 15, Color("#FFC94D")))

	# Vai trò đề cử
	var rec := Roles.recommendation(m, team)
	if not rec.is_empty():
		var parts := PackedStringArray()
		for r in rec:
			parts.append("%s%s %d/%d[/color]" % ["[color=#B4FF39]✔ " if r.have >= r.need else "[color=#FF5A5A]✘ ", Roles.name_of(r.role), r.have, r.need])
		list.add_child(UI.rich("Vai trò đề cử: " + "   ".join(parts)))

	for char_id in CrewSystem.available(Game):
		var check := CheckBox.new()
		var role := Roles.role_of(char_id)
		var gear := PackedStringArray()
		for slot in Inventory.MEMBER_SLOTS:
			var item_id := Inventory.equipped(Game, char_id, slot)
			if item_id != "":
				gear.append(Content.get_entry("items", item_id).get("name", item_id))
		check.text = "%s — %s · %s" % [CrewSystem.display_name(char_id), Roles.name_of(role), ", ".join(gear) if gear.size() > 0 else "không trang bị"]
		check.button_pressed = char_id in team
		check.disabled = not char_id in team and team.size() >= int(size[1])
		check.add_theme_color_override("font_color", Roles.color_of(role))
		check.toggled.connect(func(on):
			if on and not char_id in team:
				team.append(char_id)
			elif not on:
				team.erase(char_id)
			_build_missions())
		list.add_child(UI.hbox([UI.portrait(char_id, 40), check]))

	var unprotected := MissionSystem.unprotected_hazards(Game, option.location, team) if team.size() > 0 else []
	if unprotected.size() > 0:
		list.add_child(UI.label("⚠ Chưa được bảo vệ khỏi: " + ", ".join(unprotected.map(func(h): return Content.config.hazards[h].label)), 15, Color("#FF8A3D")))
	var valid := MissionSystem.valid_team(Game, m, team)
	var chance := MissionSystem.chance(Game, m, team, option.location) if team.size() > 0 else 0.0
	var buttons: Array = []
	if not m.get("auto_only", false):
		var deploy := func():
			if MissionSystem.start_action(Game, option, team):
				_prep = {}
				SaveManager.save_game()
				get_tree().change_scene_to_file(MISSION_SCENE)
		buttons.append(UI.button("▶ Đổ bộ (chỉ huy trên bản đồ)", deploy, not valid))
	var send_auto := func():
		if MissionSystem.launch_auto(Game, option, team):
			_prep = {}
			Game.state_changed.emit()
	buttons.append(UI.button("Gửi đội tự động (%d%%, %d năm)" % [roundi(chance * 100), int(m.get("duration", 1))], send_auto, not valid))
	buttons.append(UI.button("Hủy", func():
		_prep = {}
		_build_missions()))
	list.add_child(UI.hbox(buttons))
	if not valid and team.size() > 0:
		list.add_child(UI.label("Cần %d–%d thành viên." % [size[0], size[1]], 14, Color("#FF5A5A")))


func _build_research() -> void:
	var list: VBoxContainer = _lists["Nghiên cứu"]
	UI.clear(list)
	list.add_child(UI.label("Điểm nghiên cứu: +%.1f/năm (nhà khoa học rảnh rỗi đóng góp nhiều hơn). Dự trữ: %.1f" % [ResearchSystem.points_per_year(Game), Game.research_bank], 15))
	for tech in Content.all("tech"):
		var done: bool = tech.id in Game.techs
		var can := ResearchSystem.can_research(Game, tech.id)
		var status := "[color=#B4FF39]✔ Đã mở[/color]" if done else ("[color=#00E5FF]▶ Đang nghiên cứu %d/%d[/color]" % [ResearchSystem.progress(Game, tech.id), tech.cost] if tech.id == Game.research_current else "Chi phí %d" % tech.cost)
		var req: Array = tech.get("requires", []).map(func(id): return Content.get_entry("tech", id).get("name", id))
		var children: Array = [
			UI.rich("[b]%s[/b] — %s" % [tech.name, status]),
			UI.label(tech.get("description", "") + ("  (Cần: %s)" % ", ".join(req) if req.size() > 0 else ""), 14, Color("#8FA3BF")),
		]
		if can and tech.id != Game.research_current:
			children.append(UI.button("Nghiên cứu", func():
				ResearchSystem.set_project(Game, tech.id)
				Game.state_changed.emit()))
		list.add_child(UI.card(children))


func _build_inventory() -> void:
	var list: VBoxContainer = _lists["Kho & Trang bị"]
	UI.clear(list)
	list.add_child(UI.label("Trang bị từng thành viên (theo vai trò)", 20))
	for char_id in Game.crew:
		if not Content.get_entry("characters", char_id).get("assignable", true):
			continue
		var role := Roles.role_of(char_id)
		var row: Array = [UI.portrait(char_id, 36), UI.label("%s\n%s" % [CrewSystem.display_name(char_id), Roles.name_of(role)], 14, Roles.color_of(role))]
		row[1].custom_minimum_size = Vector2(170, 0)
		for slot in Inventory.MEMBER_SLOTS:
			row.append(_equip_picker(char_id, slot))
		var stats := CombatStats.compute(Game, char_id)
		row.append(UI.label("Máu %d · Giáp %d · ST %s · Tầm %d" % [stats.max_hp, stats.armor, CombatStats.format("damage_mult", stats.damage_mult), stats.sight_radius], 13, Color("#8FA3BF")))
		list.add_child(UI.hbox(row))

	var consumables: Array = Game.loadout.get("consumables", [])
	var row: Array = [UI.label("Vật phẩm nhanh của đội (%d/%d):" % [consumables.size(), Inventory.consumable_slots()], 16)]
	for item_id in consumables:
		row.append(UI.icon(Inventory.icon(item_id), 32))
		row.append(UI.button(Content.get_entry("items", item_id).name + " ✕", func():
			Inventory.unequip_consumable(Game, item_id)
			Game.state_changed.emit()))
	list.add_child(UI.hbox(row))

	var names := {"weapon": "Vũ khí", "tool": "Công cụ", "module": "Module", "consumable": "Vật phẩm tiêu hao", "material": "Nguyên liệu", "key": "Vật phẩm cốt truyện"}
	for cat in names:
		var ids := Inventory.items_in(Game, cat)
		if ids.is_empty():
			continue
		list.add_child(UI.label(names[cat], 20))
		for item_id in ids:
			var item := Content.get_entry("items", item_id)
			var extra := ""
			if cat in ["weapon", "tool"]:
				var type: String = item.get(cat, {}).get("type", "")
				var roles: Array = Content.all("roles").filter(func(r): return type in r.get(cat + "_types", [])).map(func(r): return r.name)
				extra = " · Dùng được: " + ", ".join(roles) + " · Còn trống %d" % Inventory.available(Game, item_id)
			var item_row: Array = [UI.icon(Inventory.icon(item_id)), UI.rich("[b]%s[/b] x%d — %s[color=#8FA3BF]%s[/color]" % [item.name, Game.item_count(item_id), item.get("description", ""), extra])]
			if cat == "consumable":
				var equip := func():
					Inventory.equip_consumable(Game, item_id)
					Game.state_changed.emit()
				item_row.append(UI.button("Mang theo", equip, item_id in consumables or consumables.size() >= Inventory.consumable_slots()))
			list.add_child(UI.hbox(item_row))


## Ô chọn trang bị: chỉ liệt kê đồ vai trò dùng được và còn trong kho.
func _equip_picker(char_id: String, slot: String) -> OptionButton:
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(190, 0)
	pick.add_theme_constant_override("icon_max_width", 24)
	pick.get_popup().add_theme_constant_override("icon_max_width", 24)
	var current := Inventory.equipped(Game, char_id, slot)
	var labels := {"weapon": "— vũ khí —", "tool": "— công cụ —", "module": "— module —"}
	pick.add_item(labels[slot])
	pick.set_item_metadata(0, "")
	for item_id in Inventory.items_in(Game, slot):
		if not Roles.can_use(char_id, item_id):
			continue
		if item_id != current and Inventory.available(Game, item_id) <= 0:
			continue
		pick.add_icon_item(Inventory.icon(item_id), Content.get_entry("items", item_id).name)
		var idx := pick.item_count - 1
		pick.set_item_metadata(idx, item_id)
		if item_id == current:
			pick.select(idx)
	pick.disabled = pick.item_count <= 1
	pick.item_selected.connect(func(i):
		var item_id: String = pick.get_item_metadata(i)
		Inventory.unequip_member(Game, char_id, slot)
		if item_id != "":
			Inventory.equip_member(Game, char_id, slot, item_id)
		Game.state_changed.emit())
	return pick


func _build_crafting() -> void:
	var list: VBoxContainer = _lists["Chế tạo"]
	UI.clear(list)
	list.add_child(UI.label("Nguyên liệu lấy từ khai thác mỏ, trục vớt, quái và boss trong các màn đổ bộ.", 15, Color("#8FA3BF")))
	for recipe in Crafting.unlocked(Game):
		var mats := PackedStringArray()
		for item_id in recipe.materials:
			var have := Game.item_count(item_id)
			var need := int(recipe.materials[item_id])
			mats.append("%s%s %d/%d[/color]" % ["[color=#B4FF39]" if have >= need else "[color=#FF2BD6]", Content.get_entry("items", item_id).name, have, need])
		var result_items: Array = recipe.get("result", {}).get("items_add", {}).keys()
		list.add_child(UI.hbox([
			UI.icon(Inventory.icon(result_items[0]) if result_items.size() > 0 else null, 36),
			UI.rich("[b]%s[/b]  ←  %s" % [recipe.name, ", ".join(mats)]),
			UI.button("Chế tạo", func(): Crafting.craft(Game, recipe.id), not Crafting.can_craft(Game, recipe)),
		]))
	var locked := Content.all("recipes").size() - Crafting.unlocked(Game).size()
	if locked > 0:
		list.add_child(UI.label("🔒 %d công thức khác cần nghiên cứu công nghệ để mở." % locked, 15, Color("#5C6B80")))


func _build_map() -> void:
	var list: VBoxContainer = _lists["Bản đồ sao"]
	UI.clear(list)
	for loc_id in Game.known_locations:
		var loc := Content.get_entry("locations", loc_id)
		var hazards: Array = loc.get("hazards", []).map(func(h): return Content.config.hazards[h].label)
		list.add_child(UI.card([
			UI.rich("[b]%s[/b] · khoảng cách %d" % [loc.name, int(loc.get("distance", 0))] + ("  [color=#FF8A3D]%s[/color]" % ", ".join(hazards) if hazards.size() > 0 else "")),
			UI.label(loc.get("description", ""), 14, Color("#8FA3BF")),
		]))
	var unknown := Content.ids("locations").size() - Game.known_locations.size()
	if unknown > 0:
		list.add_child(UI.label("??? Còn %d tín hiệu chưa xác định. Nghiên cứu Máy quét tầm xa để khám phá." % unknown, 15, Color("#5C6B80")))


# --- Dẫn truyện: sự kiện, kết thúc ----------------------------------------------------

func _dialogue_beats(dialogue_id: String) -> Array:
	var dialogue := Content.get_entry("dialogues", dialogue_id)
	var beats: Array = []
	for line in dialogue.get("lines", []):
		beats.append(line.duplicate())
	if not beats.is_empty() and dialogue.has("bg") and not beats[0].has("bg"):
		beats[0].bg = dialogue.bg
	return beats


func _play_dialogue(dialogue_id: String) -> void:
	var beats := _dialogue_beats(dialogue_id)
	if beats.is_empty():
		_on_story_finished()
		return
	_story.clear_portraits()
	_story.play(beats)


func _show_event(event: Dictionary) -> void:
	var beats := _dialogue_beats(event.get("dialogue", ""))
	if event.has("background"):
		if beats.is_empty():
			beats.append({"speaker": "", "text": event.get("text", ""), "bg": event.background})
		else:
			beats[0].bg = event.background
	beats.append({"speaker": "", "text": "【%s】 %s" % [event.get("title", ""), event.get("text", "")]})
	var choices := []
	for option in Game.available_choices(event):
		choices.append({"text": option.choice.get("text", "..."), "index": option.index})
	if not _story.is_playing():
		_story.clear_portraits()
		_story.play(beats, choices)
	else:
		_story.continue_with(beats, choices)


func _on_story_choice(index: int) -> void:
	if not _special.is_empty():
		_resolve_special(index)
		return
	var event := Game.get_pending_event()
	var result: String = event.get("choices", [])[index].get("effects", {}).get("log", "") if index < event.get("choices", []).size() else ""
	Game.choose(index)
	SaveManager.save_game()
	if Game.pending_event != "":
		return  # sự kiện nối tiếp đã được phát bởi event_started
	if result != "":
		_story.continue_with([{"speaker": "", "text": result}])
	else:
		_story.continue_with([])


func _on_story_finished() -> void:
	_refresh()
	if Game.pending_event != "" and not _story.is_playing():
		_show_event(Game.get_pending_event())
	else:
		_play_next_special()


# --- Sự kiện đặc biệt: lễ trưởng thành, kỳ ngộ ------------------------------------------------

func _play_next_special() -> void:
	if _story.is_playing() or Game.pending_event != "" or Game.special_queue.is_empty():
		return
	_special = Game.special_queue[0]
	var char_id: String = _special.char_id
	var name := CrewSystem.display_name(char_id)
	var encounter := Content.get_entry("encounters", _special.get("encounter", ""))
	var beats: Array = []
	for line in encounter.get("lines", []):
		var b: Dictionary = line.duplicate()
		b.text = b.text.replace("{name}", name)
		beats.append(b)
	if not beats.is_empty():
		beats[0].bg = encounter.get("bg", "corridor")
	var choices := []
	match _special.type:
		"coming_of_age":
			beats.append({"speaker": "", "text": "【Lễ trưởng thành】 %s tròn %d tuổi. Hội đồng cùng %s chọn con đường cho tương lai." % [name, Game.character_age(char_id), name], "bg": "corridor" if beats.is_empty() else encounter.get("bg", "corridor")})
			_special_options = Lifecycle.coming_of_age_options(Game, _special)
			for i in _special_options.size():
				choices.append({"text": _special_options[i].text, "index": i})
		_:
			beats.append({"speaker": "", "text": "【Kỳ ngộ】 " + encounter.get("title", "")})
			_special_options = [{}]
			choices.append({"text": "Ghi nhận", "index": 0})
	_story.clear_portraits()
	_story.play(beats, choices)


func _resolve_special(index: int) -> void:
	var special := _special
	_special = {}
	Game.special_queue.erase(special)
	var text := ""
	if special.type == "coming_of_age":
		text = Lifecycle.resolve_coming_of_age(Game, special, _special_options[index])
	else:
		text = Lifecycle.resolve_encounter(Game, special.char_id, special.get("encounter", ""))
	SaveManager.save_game()
	Game.state_changed.emit()
	_story.continue_with([{"speaker": "", "text": text}])


func _open_overlay() -> void:
	UI.clear(_overlay_box)
	_overlay.visible = true
	_advance_button.disabled = true


func _show_ending(ending: Dictionary) -> void:
	_story.clear_portraits()
	_story.play([{"speaker": "", "text": ending.get("text", ""), "bg": ending.get("background", "space")}])
	await _story.finished
	_open_overlay()
	_overlay_box.add_child(UI.label(ending.get("title", "Kết thúc"), 30, Color("#FF2BD6")))
	_overlay_box.add_child(UI.rich(ending.get("text", "")))
	_overlay_box.add_child(UI.button("Về màn hình chính", func():
		SaveManager.delete_save()
		get_tree().change_scene_to_file(TITLE_SCENE)))


func _show_chapter_end(chapter: Dictionary) -> void:
	_play_dialogue(chapter.get("outro_dialogue", ""))
	await _story.finished
	_open_overlay()
	_overlay_box.add_child(UI.label(chapter.get("title", ""), 28, Color("#B4FF39")))
	_overlay_box.add_child(UI.rich(chapter.get("outro", "")))
	_overlay_box.add_child(UI.button("Về màn hình chính", func(): get_tree().change_scene_to_file(TITLE_SCENE)))
