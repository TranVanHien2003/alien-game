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
		Game.choose(0)
	var scene: Node = load(scene_path).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	for i in int(args.get("frames", 90)):
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
