class_name UnitSprites
extends RefCounted
## Tạo SpriteFrames cho thành viên từ các dải ảnh trong assets/units (sinh bởi tools/import_assets.py):
##   <vai trò>_<loại súng>_<idle|move|shoot>.png và feet_<walk|idle>.png. Có cache theo khóa.

const DIR := "res://assets/units/"
const WEAPON_KIND := {"pistol": "handgun", "shotgun": "shotgun"}

static var _cache: Dictionary = {}
static var _meta: Dictionary = {}


static func kind_for_weapon(weapon_type: String) -> String:
	return WEAPON_KIND.get(weapon_type, "rifle")


static func body_frames(role: String, kind: String) -> SpriteFrames:
	var key := "%s_%s" % [role, kind]
	if not _cache.has(key):
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		for anim in [["idle", 10.0, true], ["move", 14.0, true], ["shoot", 18.0, false]]:
			_add(frames, anim[0], "%s%s_%s_%s.png" % [DIR, role, kind, anim[0]], _count("%s_%s" % [kind, anim[0]]), anim[1], anim[2])
		_cache[key] = frames
	return _cache[key]


static func feet_frames() -> SpriteFrames:
	if not _cache.has("feet"):
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		_add(frames, "walk", DIR + "feet_walk.png", _count("feet_walk"), 14.0, true)
		_add(frames, "idle", DIR + "feet_idle.png", _count("feet_idle"), 4.0, true)
		_cache["feet"] = frames
	return _cache["feet"]


static func _count(name: String) -> int:
	if _meta.is_empty():
		_meta = JSON.parse_string(FileAccess.get_file_as_string(DIR + "units.json"))
	return int(_meta.get("anims", {}).get(name, 1))


static func _add(frames: SpriteFrames, anim: String, path: String, count: int, fps: float, loop: bool) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loop)
	if not ResourceLoader.exists(path):
		return
	var sheet: Texture2D = load(path)
	var w := sheet.get_width() / maxi(1, count)
	for i in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * w, 0, w, sheet.get_height())
		frames.add_frame(anim, atlas)
