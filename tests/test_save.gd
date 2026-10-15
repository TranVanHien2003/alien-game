extends RefCounted
## Save có phiên bản: lưu/nạp khứ hồi và nâng cấp save cũ.

const SLOT := "test_slot"


func test_roundtrip(t) -> void:
	Game.new_game(11)
	Game.choose(0)
	Game.advance_year()
	var before := Game.to_dict()
	t.equal(SaveManager.save_game(SLOT), OK, "lưu được")
	Game.new_game(99)
	t.equal(SaveManager.load_game(SLOT), OK, "nạp được")
	# So qua JSON vì JSON không phân biệt int/float
	var normalize := func(d): return JSON.stringify(JSON.parse_string(JSON.stringify(d)))
	t.equal(normalize.call(Game.to_dict()), normalize.call(before), "trạng thái giống hệt sau khi nạp")
	SaveManager.delete_save(SLOT)


func test_migrate_v0(t) -> void:
	var old := {"save_version": 0, "state": {"year": 4, "resources": {"food": 12.0}, "characters": ["khang", "bao"]}}
	var result := SaveManager.migrate(old)
	t.equal(result.save_version, SaveManager.SAVE_VERSION, "lên phiên bản mới nhất")
	t.check(result.state.has("stats") and not result.state.has("resources"), "v0->v1 đổi resources thành stats")
	t.check(result.state.crew.has("bao") and not result.state.has("characters"), "v1->v2 tạo crew")
	Game.from_dict(result.state)
	t.equal(Game.get_stat("food"), 12.0, "giá trị được giữ")


func test_reject_future_save(t) -> void:
	t.check(SaveManager.migrate({"save_version": SaveManager.SAVE_VERSION + 1, "state": {}}).is_empty(), "từ chối save từ bản mới hơn")


func test_sanitize_removed_content(t) -> void:
	Game.new_game(1)
	var data := Game.to_dict()
	data.crew["nhan_vat_da_xoa"] = {"skills": {}, "xp": {}, "status": "idle"}
	data.items["vat_pham_da_xoa"] = 3
	data.techs.append("tech_da_xoa")
	Game.from_dict(data)
	t.check(not Game.crew.has("nhan_vat_da_xoa"), "bỏ nhân vật không còn")
	t.check(not Game.items.has("vat_pham_da_xoa"), "bỏ vật phẩm không còn")
	t.check(not "tech_da_xoa" in Game.techs, "bỏ công nghệ không còn")
