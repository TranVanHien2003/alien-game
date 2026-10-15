extends Node
## Chụp ảnh một scene để kiểm tra nhanh / làm ảnh README.
## godot --path . res://tools/screenshot.tscn -- --scene=res://scenes/hub/hub.tscn --out=build/shot.png [--frames=90]

func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var scene_path: String = args.get("scene", "res://scenes/title/title.tscn")
	var out: String = args.get("out", "build/screenshot.png")
	SaveManager.save_dir = "user://test_saves"
	if scene_path.contains("hub"):
		Game.new_game(1)
		if not args.has("story_steps"):
			Game.flags["intro_seen"] = true
			Game.choose(0)
		Game.items.merge({"kim_loai": 6, "tinh_the": 3, "bang": 3, "armor_plate": 1, "w_scatter": 1})
	if args.has("mission"):
		# Chụp một nhiệm vụ cụ thể: --mission=msn_derelict
		Game.new_game(int(args.get("seed", "3")))
		Game.pending_event = ""
		Game.known_locations = Content.ids("locations")
		var option: Dictionary = MissionSystem.available(Game).filter(func(o): return o.mission.id == args.mission)[0]
		MissionSystem.start_action(Game, option, ["khang", "tuan", "bao", "thu_ha", "huy"].slice(0, int(option.mission.team_size[1])))
	var scene: Node = load(scene_path).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	for i in int(args.get("frames", 90)):
		await get_tree().process_frame
	if args.has("story_steps") and scene.get("_story"):
		for i in int(args.story_steps):
			scene._story._advance()
		for i in 60:
			await get_tree().process_frame
	if args.has("skip_story") and scene.get("_story"):
		while scene._story.is_playing() or Game.pending_event != "":
			if scene._story._choice_box.visible:
				scene._story._on_choice(scene._story._choices[0])
			else:
				scene._story._skip()
			await get_tree().process_frame
			if not scene._story._choice_box.visible and not scene._story._typing and Game.pending_event == "":
				break
		for i in 40:
			await get_tree().process_frame
	if args.has("coming_of_age") and scene.get("_story"):
		var child := CharacterFactory.newborn(Game, Game.rng, ["thu_ha", "khang"])
		CrewSystem.add_member(Game, child.id)
		Game.special_queue.append({"type": "coming_of_age", "char_id": child.id, "encounter": "enc_van_lang_call"})
		scene._play_next_special()
		for i in 6:
			scene._story._skip()
			await get_tree().process_frame
		for i in 30:
			await get_tree().process_frame
	if args.has("tab") and scene.has_node("%Tabs"):
		scene.get_node("%Tabs").current_tab = int(args.tab)
		for i in 5:
			await get_tree().process_frame
	if scene_path.contains("mission"):
		# Bắn vài phát cho có hiệu ứng
		var player = scene.get("player")
		if player:
			player._shoot()
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out).get_base_dir())
	image.save_png(ProjectSettings.globalize_path("res://" + out))
	print("Saved ", out)
	get_tree().quit()
