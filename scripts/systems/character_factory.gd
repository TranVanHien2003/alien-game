class_name CharacterFactory
extends RefCounted
## Sinh nhân vật mới lúc chạy: trẻ em sinh ra trên tàu, người sống sót gặp trong màn chơi.
## Nhân vật được đăng ký vào Content (danh mục characters) và lưu vào Game.custom_characters.

const SURNAMES := ["Nguyễn", "Trần", "Lê", "Phạm", "Hoàng", "Vũ", "Đặng", "Bùi", "Đỗ", "Hồ", "Ngô", "Dương", "Lý", "Trịnh", "Đào", "Mai", "Tô", "Lâm"]
const MIDDLE := {"male": ["Văn", "Minh", "Quốc", "Đức", "Hữu", "Thanh", "Gia"], "female": ["Thị", "Ngọc", "Thu", "Minh", "Bảo", "Thanh", "Diệu"]}
const GIVEN := {
	"male": ["Long", "Phong", "Sơn", "Khôi", "Nam", "Duy", "Tùng", "Hiếu", "Kiên", "Lâm", "Đạt", "Vĩnh", "Trung", "Hào"],
	"female": ["Linh", "Trang", "Vy", "Ngân", "Hương", "Yến", "Thảo", "Chi", "Nhi", "Uyên", "Hạnh", "Quyên", "My", "Khuê"],
}
const PORTRAITS := {
	"male": ["vs_male6", "vs_male16", "vs_male20", "vs_male2", "vs_male3", "vs_male7", "vs_male8", "vs_male19"],
	"female": ["vs_women3", "vs_women26", "vs_women2", "vs_women9", "vs_women14", "vs_women17", "vs_women27", "vs_women36"],
}
const SPRITES := {"male": ["man_brown", "man_blue", "man_old", "soldier", "hitman"], "female": ["woman_green", "survivor"]}


static func new_id(game: Node, prefix: String) -> String:
	var n: int = game.custom_characters.size() + 1
	while Content.has_entry("characters", "%s_%d" % [prefix, n]):
		n += 1
	return "%s_%d" % [prefix, n]


static func random_name(rng: RandomNumberGenerator, gender: String) -> String:
	var g := "female" if gender == "female" else "male"
	return "%s %s %s" % [SURNAMES[rng.randi() % SURNAMES.size()], MIDDLE[g][rng.randi() % MIDDLE[g].size()], GIVEN[g][rng.randi() % GIVEN[g].size()]]


## Trẻ sơ sinh: thuộc tính thấp, thừa hưởng một phần từ "cha mẹ" (hai thành viên trưởng thành).
static func newborn(game: Node, rng: RandomNumberGenerator, parents: Array) -> Dictionary:
	var gender := "female" if rng.randf() < 0.5 else "male"
	var attrs := {}
	for attr in Content.config.get("attributes", {}):
		var inherited := 0.0
		for p in parents:
			inherited += float(game.crew.get(p, {}).get("attributes", {}).get(attr, 30))
		inherited /= maxf(1.0, parents.size())
		attrs[attr] = clampi(int(6 + inherited * 0.12 + rng.randi_range(0, 6)), 5, 20)
	var parent_names: Array = parents.map(func(p): return CrewSystem.display_name(p))
	var entry := {
		"id": new_id(game, "child"),
		"name": random_name(rng, gender),
		"title": "Con của " + " & ".join(parent_names),
		"generation": game.generation + 1,
		"birth_year": game.year,
		"gender": gender,
		"child": true,
		"traits": [["tò mò", "lém lỉnh", "trầm tính", "hiếu động", "nhút nhát"][rng.randi() % 5]],
		"bio": "Sinh ra năm %d trên tàu Âu Cơ." % game.year,
		"skills": {},
		"attributes": attrs,
		"parents": parents,
		"sprite": SPRITES[gender][rng.randi() % SPRITES[gender].size()],
		"portrait": PORTRAITS[gender][rng.randi() % PORTRAITS[gender].size()],
		"runtime": true,
	}
	register(game, entry)
	return entry


## Người sống sót gặp trên bản đồ: trưởng thành, có sẵn một vai theo thuộc tính.
static func stranger(game: Node, rng: RandomNumberGenerator, origin: String) -> Dictionary:
	var gender := "female" if rng.randf() < 0.5 else "male"
	var attrs := {}
	for attr in Content.config.get("attributes", {}):
		attrs[attr] = rng.randi_range(28, 62)
	# Một thuộc tính nổi trội
	var keys: Array = attrs.keys()
	attrs[keys[rng.randi() % keys.size()]] += rng.randi_range(10, 20)
	var entry := {
		"id": new_id(game, "stranger"),
		"name": random_name(rng, gender),
		"title": "Người sống sót (%s)" % origin,
		"generation": game.generation,
		"birth_year": game.year - rng.randi_range(22, 45),
		"gender": gender,
		"traits": [["cảnh giác", "biết ơn", "bí ẩn", "cứng cỏi", "ít nói"][rng.randi() % 5]],
		"bio": "Được tìm thấy tại %s năm %d. Không nhớ rõ mình đến từ đâu." % [origin, game.year],
		"skills": {"survival": rng.randi_range(1, 3)},
		"attributes": attrs,
		"sprite": SPRITES[gender][rng.randi() % SPRITES[gender].size()],
		"portrait": PORTRAITS[gender][rng.randi() % PORTRAITS[gender].size()],
		"runtime": true,
	}
	entry.role = AttributeSystem.best_roles_for(attrs, 1)[0]
	register(game, entry)
	return entry


static func register(game: Node, entry: Dictionary) -> void:
	game.custom_characters[entry.id] = entry
	Content.add_runtime("characters", entry)


static func unregister(game: Node, char_id: String) -> void:
	game.custom_characters.erase(char_id)
	Content.remove_runtime("characters", char_id)
