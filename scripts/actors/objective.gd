class_name Objective
extends Area2D
## Điểm tương tác trên bản đồ:
##   "collect"  — thành viên chạm vào là nhặt được
##   "interact" — thành viên đứng làm việc (Unit gọi work()); kỹ sư + bộ sửa chữa làm nhanh hơn
##   "rescue"   — người mất tích: chạm vào thì đi theo người cứu
##   "cache"    — tủ tiếp tế: mở (như interact, nhanh hơn) để rơi loot; không tính vào mục tiêu
##   "relic"    — cổ vật / kỳ ngộ: người mở nhận thuộc tính hoặc tài năng hiếm
##   "stranger" — người sống sót lạ: chạm vào thì gia nhập đội (cuối màn chọn thu nhận hay không)

signal completed(objective: Objective)
## Unit hoàn thành (người chạm/người làm việc)
var finisher: Node

var kind := "collect"
var label := ""
var color := Color("#B4FF39")
var done := false
var work_needed := 3.0
var _progress := 0.0
var _follow: Node2D
var _t := 0.0
var _sprite: Sprite2D


## sprite_path: ảnh hiển thị (trạm máy tính, thùng hàng, hoặc nhân vật cần giải cứu)
func setup(objective_kind: String, objective_label: String, accent: Color, sprite_path: String = "") -> void:
	kind = objective_kind
	label = objective_label
	color = accent
	work_needed = float(Content.config.get("player", {}).get("interact_time", 3.0)) * (0.5 if kind == "cache" else (1.5 if kind == "relic" else 1.0))
	_sprite = Sprite2D.new()
	if sprite_path == "":
		sprite_path = {
			"interact": "res://assets/props/terminal.png",
			"collect": "res://assets/props/salvage_crate.png",
			"cache": "res://assets/props/deco_crate_small.png",
			"relic": "res://assets/props/crystal_vein.png",
		}.get(kind, "")
	if ResourceLoader.exists(sprite_path):
		_sprite.texture = load(sprite_path)
	if kind == "collect":
		_sprite.scale = Vector2.ONE * 0.6
	elif kind == "cache":
		_sprite.scale = Vector2.ONE * 1.3
		_sprite.modulate = Color("#FFE0A0")
	elif kind == "relic":
		_sprite.scale = Vector2.ONE * 1.6
		_sprite.modulate = Color(1.6, 1.2, 2.0)
	add_child(_sprite)
	var light := PointLight2D.new()
	light.texture = preload("res://assets/fx/light.png")
	light.texture_scale = 1.0 if kind != "cache" else 0.6
	light.energy = 0.7
	light.color = Color("#FFC94D") if kind in ["rescue", "cache", "stranger"] else (Color("#C08CFF") if kind == "relic" else accent)
	add_child(light)


func _ready() -> void:
	add_to_group("interactables")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if done or not (body is Unit and body.is_active()):
		return
	match kind:
		"collect":
			Sfx.play("pickup")
			_finish()
			queue_free()
		"rescue", "stranger":
			# Người được cứu gia nhập đội ngay trên bản đồ (MissionLevel tạo Unit mới)
			finisher = body
			_finish()
			queue_free()


## Unit gọi mỗi khung khi đang làm việc ở đây (amount = giây × tốc độ tương tác).
func work(unit: Node, amount: float) -> void:
	if done or not kind in ["interact", "cache", "relic"]:
		return
	finisher = unit
	_progress += amount / work_needed
	if _progress >= 1.0:
		Sfx.play("door")
		_finish()


func needs_work() -> bool:
	return kind in ["interact", "cache", "relic"] and not done


func _physics_process(delta: float) -> void:
	_t += delta
	if is_instance_valid(_follow):
		var to := _follow.global_position - global_position
		_sprite.rotation = lerp_angle(_sprite.rotation, to.angle(), 0.2)
		if to.length() > 44.0:
			global_position += to.normalized() * minf(to.length() - 44.0, float(_follow.stats.get("move_speed", 200)) * 1.05 * delta)
	queue_redraw()


func _finish() -> void:
	done = true
	if kind == "cache":
		_sprite.modulate = Color(0.5, 0.5, 0.5)
	completed.emit(self)


func _draw() -> void:
	var pulse := 0.6 + 0.4 * sin(_t * 4.0)
	if kind in ["interact", "cache", "relic"]:
		var r := 28.0 if kind != "cache" else 22.0
		if done:
			if kind == "interact":
				draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color("#B4FF39"), 2.0)
		elif _progress > 0.0:
			draw_arc(Vector2.ZERO, r, -PI / 2, -PI / 2 + TAU * _progress, 32, Color.WHITE, 4.0)
		else:
			draw_arc(Vector2.ZERO, r - 2.0 + pulse * 4.0, 0.0, TAU, 32, Color(color if kind == "interact" else Color("#FFC94D"), 0.6), 1.5)
	elif kind in ["rescue", "stranger"]:
		draw_arc(Vector2.ZERO, 24.0 + pulse * 6.0, 0.0, TAU, 24, Color("#FFC94D", 0.7), 2.0)
		draw_string(UI.font(), Vector2(-60, -34), "NGƯỜI MẤT TÍCH" if kind == "rescue" else "NGƯỜI SỐNG SÓT?", HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color("#FFC94D"))
	if kind == "relic" and not done:
		draw_string(UI.font(), Vector2(-40, -40), "KỲ NGỘ", HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color("#C08CFF"))
