extends RefCounted
## Nội dung JSON phải hợp lệ: CI sẽ chặn deploy nếu có tham chiếu sai.


func test_content_has_no_errors(t) -> void:
	for err in Content.errors:
		t.check(false, err)


func test_core_categories_not_empty(t) -> void:
	for category in ["chapters", "characters", "events", "missions", "tech", "items", "enemies", "levels", "loot", "recipes"]:
		t.check(Content.all(category).size() > 0, "danh mục rỗng: " + category)
