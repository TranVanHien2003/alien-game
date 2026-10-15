extends Control
## Hub trên tàu Âu Cơ: quản lý phi hành đoàn, nhiệm vụ, nghiên cứu, kho/trang bị, chế tạo, bản đồ sao.
## Toàn bộ nội dung từng tab được dựng lại từ Game mỗi khi state_changed.

const MISSION_SCENE := "res://scenes/mission/mission_level.tscn"
const TITLE_SCENE := "res://scenes/title/title.tscn"

@onready var _year_label: Label = %YearLabel
@onready var _stats_box: HBoxContainer = %StatsBox
@onready var _tabs: TabContainer = %Tabs
@onready var _advance_button: Button = %AdvanceButton
@onready var _save_button: Button = %SaveButton
@onready var _menu_button: Button = %MenuButton
@onready var _overlay: Control = %Overlay
@onready var _overlay_box: VBoxContainer = %OverlayBox

var _lists: Dictionary = {}
var _log_label: RichTextLabel
## Màn hình chuẩn bị nhiệm vụ đang mở: {option, team: []}
var _prep: Dictionary = {}
var _dialogue_queue: Array = []


func _ready() -> void:
	for tab in ["Tổng quan", "Phi hành đoàn", "Nhiệm vụ", "Nghiên cứu", "Kho & Trang bị", "Chế tạo", "Bản đồ sao"]:
		var parts := UI.scroll_list()
		parts[0].name = tab
		_tabs.add_child(parts[0])
		_lists[tab] = parts[1]
	_advance_button.pressed.connect(_on_advance)
	_save_button.pressed.connect(func():
		SaveManager.save_game()
		Game.add_log("Đã lưu game."))
	_menu_button.pressed.connect(func():
		SaveManager.save_game()
		get_tree().change_scene_to_file(TITLE_SCENE))
	Game.state_changed.connect(_refresh)
	Game.log_added.connect(func(_e): _refresh_log())
	Game.event_started.connect(_show_event)
	Game.game_ended.connect(_show_ending)
	Game.chapter_completed.connect(_show_chapter_end)
	_overlay.visible = false
	_refresh()
	if Game.pending_event != "":
		_show_event(Game.get_pending_event())
	elif Game.ending_id != "":
		_show_ending(Content.get_entry("endings", Game.ending_id))
	elif Game.chapter_done:
		_show_chapter_end(Game.current_chapter())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("advance_year") and not _overlay.visible:
		_on_advance()
	elif event.is_action_pressed("quick_save"):
		SaveManager.save_game()
		Game.add_log("Đã lưu nhanh.")


func _on_advance() -> void:
	if Game.advance_year():
		SaveManager.save_game()


# --- Làm mới --------------------------------------------------------------------

func _refresh() -> void:
	var chapter := Game.current_chapter()
	_year_label.text = "Năm %d · Thế hệ %d · %s" % [Game.year, Game.generation, chapter.get("title", "")]
	UI.clear(_stats_box)
	for stat in Content.stat_ids():
		var def: Dictionary = Content.config.stats[stat]
		var l := UI.label("%s %d" % [def.get("label", stat), roundi(Game.get_stat(stat))], 16, Color(def.get("color", "#FFFFFF")))
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		_stats_box.add_child(l)
	_advance_button.disabled = not Game.can_advance()
	_build_overview()
	_build_crew()
	_build_missions()
	_build_research()
	_build_inventory()
	_build_crafting()
	_build_map()


func _refresh_log() -> void:
	if _log_label == null or not is_instance_valid(_log_label):
		return
	var lines := PackedStringArray()
	for i in range(Game.log_entries.size() - 1, maxi(-1, Game.log_entries.size() - 40), -1):
		var e: Dictionary = Game.log_entries[i]
		lines.append("[color=#5C8DB0]Năm %d[/color]  %s" % [e.year, e.text])
	_log_label.text = "\n".join(lines)


func _build_overview() -> void:
	var list: VBoxContainer = _lists["Tổng quan"]
	UI.clear(list)
	var missing := CrewSystem.missing_members(Game)
	for char_id in missing:
		list.add_child(UI.card([UI.rich("[color=#FF2BD6]⚠ %s mất tích tại %s — còn %d năm để giải cứu.[/color]" % [
			CrewSystem.display_name(char_id),
			Content.get_entry("locations", Game.crew[char_id].missing_at).get("name", ""),
			CrewSystem.years_left_to_rescue(Game, char_id)])]))
	for entry in Game.active_missions:
		list.add_child(UI.label("🚀 %s — còn %d năm (%s)" % [Content.get_entry("missions", entry.mission).get("name", ""), entry.years_left, ", ".join(entry.team.map(func(id): return CrewSystem.display_name(id)))], 15))
	var research := "Đang nghiên cứu: %s (%d/%d) · +%.1f điểm/năm" % [
		Content.get_entry("tech", Game.research_current).get("name", "—"),
		ResearchSystem.progress(Game, Game.research_current),
		int(Content.get_entry("tech", Game.research_current).get("cost", 0)),
		ResearchSystem.points_per_year(Game)] if Game.research_current != "" else "⚠ Chưa chọn dự án nghiên cứu (tab Nghiên cứu)."
	list.add_child(UI.label(research, 15))
	list.add_child(UI.label("Nhật ký tàu", 20))
	_log_label = UI.rich("")
	list.add_child(_log_label)
	_refresh_log()


func _build_crew() -> void:
	var list: VBoxContainer = _lists["Phi hành đoàn"]
	UI.clear(list)
	var status_names := {CrewSystem.IDLE: "Trên tàu", CrewSystem.MISSION: "Đang làm nhiệm vụ", CrewSystem.MISSING: "MẤT TÍCH", CrewSystem.TRAINING: "Đang huấn luyện"}
	for char_id in Game.crew:
		var data := Content.get_entry("characters", char_id)
		var member: Dictionary = Game.crew[char_id]
		var skills := PackedStringArray()
		for skill_id in member.skills:
			var skill := Content.get_entry("skills", skill_id)
			skills.append("%s%s %d[/color]" % ["[color=#FF2BD6]" if skill.get("high_tech", false) else "[color=#00E5FF]", skill.get("name", skill_id), member.skills[skill_id]])
		var age := "" if data.get("ageless", false) else " · %d tuổi" % Game.character_age(char_id)
		var children: Array = [
			UI.hbox([UI.portrait(char_id), UI.rich("[b]%s[/b] — [color=%s]%s[/color] · %s%s · [i]%s[/i]" % [data.get("name", char_id), Roles.color_of(Roles.role_of(char_id)).to_html(false), Roles.name_of(Roles.role_of(char_id)), _role_title(data), age, status_names.get(member.status, member.status)])]),
			UI.rich(" · ".join(skills) if skills.size() > 0 else "[color=#5C6B80]Chưa có kỹ năng[/color]"),
			UI.label(data.get("bio", ""), 14, Color("#8FA3BF")),
		]
		if char_id in CrewSystem.available(Game):
			for skill_id in CrewSystem.trainable_skills(Game, char_id):
				children.append(UI.button("Huấn luyện %s (1 năm)" % Content.get_entry("skills", skill_id).name, func():
					CrewSystem.start_training(Game, char_id, skill_id)
					Game.state_changed.emit()))
		list.add_child(UI.card(children))


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


# --- Lớp phủ: sự kiện, kết thúc --------------------------------------------------

func _open_overlay() -> void:
	UI.clear(_overlay_box)
	_overlay.visible = true
	_advance_button.disabled = true


func _close_overlay() -> void:
	_overlay.visible = false
	_refresh()


func _show_event(event: Dictionary) -> void:
	_dialogue_queue = Content.get_entry("dialogues", event.get("dialogue", "")).get("lines", []).duplicate()
	_render_event(event)


func _render_event(event: Dictionary) -> void:
	_open_overlay()
	_overlay_box.add_child(UI.label(event.get("title", ""), 26, Color("#00E5FF")))
	if not _dialogue_queue.is_empty():
		var line: Dictionary = _dialogue_queue.pop_front()
		var speaker := Content.get_entry("characters", line.get("speaker", ""))
		_overlay_box.add_child(UI.rich("[color=#FFC94D][b]%s[/b][/color]: %s" % [speaker.get("name", "???"), line.get("text", "")]))
		_overlay_box.add_child(UI.button("Tiếp ▸", func(): _render_event(event)))
		return
	_overlay_box.add_child(UI.rich(event.get("text", "")))
	for option in Game.available_choices(event):
		_overlay_box.add_child(UI.button(option.choice.get("text", "..."), func():
			_close_overlay()
			Game.choose(option.index)
			SaveManager.save_game()))


func _show_ending(ending: Dictionary) -> void:
	_open_overlay()
	_overlay_box.add_child(UI.label(ending.get("title", "Kết thúc"), 30, Color("#FF2BD6")))
	_overlay_box.add_child(UI.rich(ending.get("text", "")))
	_overlay_box.add_child(UI.button("Về màn hình chính", func():
		SaveManager.delete_save()
		get_tree().change_scene_to_file(TITLE_SCENE)))


func _show_chapter_end(chapter: Dictionary) -> void:
	_open_overlay()
	_overlay_box.add_child(UI.label(chapter.get("title", ""), 28, Color("#B4FF39")))
	_overlay_box.add_child(UI.rich(chapter.get("outro", "")))
	_overlay_box.add_child(UI.button("Về màn hình chính", func(): get_tree().change_scene_to_file(TITLE_SCENE)))
