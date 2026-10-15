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
	t.check(hub.get_node("%Overlay").visible, "sự kiện mở đầu hiện lên")
	Game.choose(0)
	hub._close_overlay()
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
