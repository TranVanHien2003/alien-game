extends Node
## Trình chạy test tối giản (không cần addon). Chạy: make test
## Tự tìm mọi file tests/test_*.gd, gọi các hàm bắt đầu bằng "test_".
## Mỗi hàm test nhận một đối tượng `t` (TestContext) để gọi t.check(...).

class TestContext:
	var failures: PackedStringArray = []
	var current := ""

	func check(condition: bool, message: String = "") -> void:
		if not condition:
			failures.append("%s: %s" % [current, message])

	func equal(actual, expected, message: String = "") -> void:
		if actual != expected:
			failures.append("%s: %s (thực tế=%s, mong đợi=%s)" % [current, message, actual, expected])


func _ready() -> void:
	# Không để test đụng vào save thật của người chơi
	SaveManager.save_dir = "user://test_saves"
	var ctx := TestContext.new()
	var total := 0
	for file in DirAccess.get_files_at("res://tests"):
		file = file.trim_suffix(".remap")
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_runner.gd":
			continue
		var script: GDScript = load("res://tests/" + file)
		var suite = script.new()
		if suite is Node:
			add_child(suite)
		for method in script.get_script_method_list():
			if not method.name.begins_with("test_"):
				continue
			total += 1
			ctx.current = "%s::%s" % [file, method.name]
			var before := ctx.failures.size()
			# await an toàn cho cả test đồng bộ lẫn test có await bên trong
			await suite.call(method.name, ctx)
			print(("  ✔ " if ctx.failures.size() == before else "  ✘ ") + ctx.current)
		if suite is Node:
			suite.queue_free()
	print("")
	if ctx.failures.is_empty():
		print("TẤT CẢ %d TEST ĐỀU QUA" % total)
	else:
		for f in ctx.failures:
			printerr("FAIL " + f)
		printerr("%d/%d test lỗi" % [ctx.failures.size(), total])
	get_tree().quit(0 if ctx.failures.is_empty() else 1)
