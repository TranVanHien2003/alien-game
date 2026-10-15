extends Node
## Test khói giao diện: dựng được các màn hình và thao tác cơ bản không lỗi.


func test_title_screen(t) -> void:
	var title: Control = load("res://scenes/title/title.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	t.check(title.get_node("%NewButton").visible, "có nút hành trình mới")
	title.queue_free()


func test_hub_flow(t) -> void:
	Game.new_game(4)
	var hub: Control = load("res://scenes/hub/hub.tscn").instantiate()
	add_child(hub)
	await get_tree().process_frame
	t.check(hub._story.is_playing(), "phần mở đầu cốt truyện được phát")
	hub._story._skip()
	await get_tree().process_frame
	t.check(Game.log_entries.any(func(e): return e.get("kind", "") == "dialogue"), "lời thoại được ghi vào nhật ký")
	Game.choose(0)
	# Mở màn chuẩn bị nhiệm vụ và chọn đội
	var option: Dictionary = MissionSystem.available(Game)[0]
	hub._prep = {"option": option, "team": ["bao", "tuan"]}
	hub._build_missions()
	t.check(hub._lists["Nhiệm vụ"].get_child_count() > 3, "màn chuẩn bị có nội dung")
	hub._prep = {}
	Game.items["kim_loai"] = 10
	Crafting.craft(Game, "r_hull_patch")
	for i in 3:
		while Game.pending_event != "":
			Game.choose(Game.available_choices(Game.get_pending_event())[0].index)
		hub._on_advance()
	await get_tree().process_frame
	t.check(Game.year >= 1, "qua năm từ hub")
	hub.queue_free()
	await get_tree().process_frame


func test_story_player_flow(t) -> void:
	Game.new_game(5)
	var story := StoryPlayer.new()
	add_child(story)
	var chosen := [-1]
	story.choice_made.connect(func(i): chosen[0] = i)
	story.play([{"speaker": "khang", "text": "Xin chào", "bg": "bridge"}, {"speaker": "lac", "text": "Chào thuyền trưởng"}, {"speaker": "", "text": "Lời dẫn"}], [{"text": "Đồng ý", "index": 1}])
	await get_tree().process_frame
	t.check(story._typing, "chữ đang hiện dần")
	story._advance()
	t.check(not story._typing, "bấm lần 1 hiện hết câu")
	story._advance()
	t.equal(story._index, 1, "bấm lần 2 sang câu tiếp")
	t.check(story._left.texture != null and story._right.texture != null, "hai chân dung hai bên")
	story._skip()
	t.check(story._choice_box.visible, "bỏ qua tới phần lựa chọn")
	story._on_choice({"text": "Đồng ý", "index": 1})
	t.equal(chosen[0], 1, "trả về lựa chọn")
	story.queue_free()
