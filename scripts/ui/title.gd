extends Control
## Màn hình tiêu đề. Nút bấm đầu tiên cũng "mở khóa" âm thanh trên trình duyệt.

const HUB_SCENE := "res://scenes/hub/hub.tscn"

@onready var _continue: Button = %ContinueButton
@onready var _new: Button = %NewButton
@onready var _quit: Button = %QuitButton
@onready var _info: Label = %InfoLabel


func _ready() -> void:
	_continue.visible = SaveManager.has_save()
	if _continue.visible:
		var info := SaveManager.save_info()
		_continue.text = "Tiếp tục (Năm %d)" % int(info.get("year", 0))
	# Trên web không có khái niệm "thoát game"
	_quit.visible = not OS.has_feature("web")
	_continue.pressed.connect(_on_continue)
	_new.pressed.connect(_on_new)
	_quit.pressed.connect(func(): get_tree().quit())
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	_info.text = "v%s · save v%d" % [version, SaveManager.SAVE_VERSION]
	if not Content.errors.is_empty():
		_info.text += "\n⚠ %d lỗi nội dung — xem Output/console" % Content.errors.size()
	if Content.loaded_mods.size() > 0:
		_info.text += "\nMod: " + ", ".join(Content.loaded_mods)
	(_continue if _continue.visible else _new).grab_focus()


func _on_continue() -> void:
	if SaveManager.load_game() == OK:
		get_tree().change_scene_to_file(HUB_SCENE)
	else:
		_info.text = "Không đọc được file save."


func _on_new() -> void:
	Game.new_game()
	SaveManager.save_game()
	get_tree().change_scene_to_file(HUB_SCENE)
