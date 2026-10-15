extends Node
## Hệ thống save có phiên bản.
##
## Mỗi file save là JSON: {save_version, game_version, saved_at, state: {...}}
## Khi đổi cấu trúc state:
##   1. Tăng SAVE_VERSION.
##   2. Thêm hàm _migrate_<cũ>_to_<mới>(state) -> state vào MIGRATIONS.
##   3. Thêm test cho migration trong tests/test_save.gd.
## Save cũ sẽ được nâng cấp lần lượt qua từng bước, không bao giờ bị "hỏng" sau bản cập nhật.

signal saved(slot: String)
signal loaded(slot: String)

const SAVE_VERSION := 3
## Đổi được (ví dụ test dùng thư mục riêng để không ghi đè save thật)
var save_dir := "user://saves"
const AUTOSAVE_SLOT := "autosave"

## version cũ -> Callable(state: Dictionary) -> Dictionary
var MIGRATIONS := {
	0: _migrate_0_to_1,
	1: _migrate_1_to_2,
	2: _migrate_2_to_3,
}


func save_game(slot: String = AUTOSAVE_SLOT) -> Error:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var payload := {
		"save_version": SAVE_VERSION,
		"game_version": ProjectSettings.get_setting("application/config/version", "0.0.0"),
		"content_version": Content.config.get("content_version", 0),
		"saved_at": Time.get_datetime_string_from_system(true),
		"state": Game.to_dict(),
	}
	var path := _slot_path(slot)
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	# Ghi vào file tạm rồi đổi tên: tắt game giữa chừng cũng không làm hỏng save cũ
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err == OK:
		saved.emit(slot)
	return err


func load_game(slot: String = AUTOSAVE_SLOT) -> Error:
	var text := FileAccess.get_file_as_string(_slot_path(slot))
	if text.is_empty():
		return ERR_FILE_NOT_FOUND
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		return ERR_FILE_CORRUPT
	var result := migrate(data)
	if result.is_empty():
		return ERR_FILE_UNRECOGNIZED
	Game.from_dict(result.state)
	loaded.emit(slot)
	return OK


## Nâng cấp payload lên SAVE_VERSION. Trả về {} nếu save đến từ bản game mới hơn.
func migrate(payload: Dictionary) -> Dictionary:
	var version := int(payload.get("save_version", 0))
	if version > SAVE_VERSION:
		push_error("Save version %d mới hơn game (%d). Hãy cập nhật game." % [version, SAVE_VERSION])
		return {}
	var state: Dictionary = payload.get("state", {})
	while version < SAVE_VERSION:
		state = MIGRATIONS[version].call(state)
		version += 1
	payload.state = state
	payload.save_version = version
	return payload


func has_save(slot: String = AUTOSAVE_SLOT) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func delete_save(slot: String = AUTOSAVE_SLOT) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(_slot_path(slot))


func save_info(slot: String = AUTOSAVE_SLOT) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(_slot_path(slot)))
	if not data is Dictionary:
		return {}
	return {
		"saved_at": data.get("saved_at", ""),
		"year": data.get("state", {}).get("year", 0),
		"game_version": data.get("game_version", ""),
	}


func _slot_path(slot: String) -> String:
	return save_dir.path_join(slot.validate_filename() + ".json")


# --- Migrations ----------------------------------------------------------------

## v0 (bản prototype): tài nguyên nằm trong "resources" thay vì "stats".
func _migrate_0_to_1(state: Dictionary) -> Dictionary:
	if state.has("resources") and not state.has("stats"):
		state.stats = state.resources
		state.erase("resources")
	return state


## v1 -> v2: "characters" (mảng id) được thay bằng "crew" (id -> trạng thái, kỹ năng).
func _migrate_1_to_2(state: Dictionary) -> Dictionary:
	if state.has("characters") and not state.has("crew"):
		var crew := {}
		for char_id in state.characters:
			crew[char_id] = {
				"skills": Content.get_entry("characters", char_id).get("skills", {}).duplicate(),
				"xp": {},
				"status": "idle",
			}
		state.crew = crew
		state.erase("characters")
	return state


## v2 -> v3: trang bị chuyển từ loadout chung (weapons/modules) sang từng thành viên (crew[id].equipment).
## Vật phẩm vẫn còn trong kho; Game.from_dict() sẽ tự trang bị lại theo vai trò.
func _migrate_2_to_3(state: Dictionary) -> Dictionary:
	var loadout: Dictionary = state.get("loadout", {})
	state.loadout = {"consumables": loadout.get("consumables", [])}
	for char_id in state.get("crew", {}):
		if not state.crew[char_id].has("equipment"):
			state.crew[char_id].equipment = {}
	return state
