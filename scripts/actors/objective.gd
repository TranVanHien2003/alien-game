class_name Objective
extends Area2D
## Mục tiêu trong màn: "collect" (chạm để nhặt), "interact" (giữ E), "rescue" (chạm để người mất tích đi theo).

signal completed(objective: Objective)

var kind := "collect"
var label := ""
var color := Color("#B4FF39")
var done := false
var _player: Player
var _progress := 0.0
var _following := false
var _t := 0.0


var _sprite: Sprite2D


## sprite_path: ảnh hiển thị (trạm máy tính, thùng hàng, hoặc nhân vật cần giải cứu)
func setup(objective_kind: String, objective_label: String, accent: Color, sprite_path: String = "") -> void:
	kind = objective_kind
	label = objective_label
	color = accent
	_sprite = Sprite2D.new()
	if sprite_path == "":
		sprite_path = {"interact": "res://assets/props/terminal.png", "collect": "res://assets/props/salvage_crate.png"}.get(kind, "")
	if ResourceLoader.exists(sprite_path):
		_sprite.texture = load(sprite_path)
	if kind == "collect":
		_sprite.scale = Vector2.ONE * 0.6
	add_child(_sprite)
	var light := PointLight2D.new()
	light.texture = preload("res://assets/fx/light.png")
	light.texture_scale = 1.2
	light.energy = 0.7
	light.color = Color("#FFC94D") if kind == "rescue" else accent
	add_child(light)


func _ready() -> void:
	body_entered.connect(func(b): if b is Player: _on_player_enter(b))
	body_exited.connect(func(b): if b == _player and kind == "interact": _player = null)


func _on_player_enter(player: Player) -> void:
	if done:
		return
	_player = player
	match kind:
		"collect":
			_finish()
			queue_free()
		"rescue":
			_following = true
			_finish()


func _physics_process(delta: float) -> void:
	_t += delta
	if kind == "interact" and not done and _player != null:
		if Input.is_action_pressed("interact"):
			_progress += delta / _player.interact_time
			if _progress >= 1.0:
				_finish()
		else:
			_progress = maxf(0.0, _progress - delta)
	if _following and is_instance_valid(_player):
		var to := _player.global_position - global_position
		_sprite.rotation = lerp_angle(_sprite.rotation, to.angle(), 0.2)
		if to.length() > 40.0:
			global_position += to.normalized() * minf(to.length() - 40.0, float(_player.stats.get("move_speed", 220)) * 1.05 * delta)
	queue_redraw()


func _finish() -> void:
	done = true
	completed.emit(self)


## Dùng cho HUD: 0..1 khi đang giữ E, -1 nếu không tương tác.
func interact_progress() -> float:
	return _progress if kind == "interact" and _player != null and not done else -1.0


func _draw() -> void:
	var pulse := 0.6 + 0.4 * sin(_t * 4.0)
	if kind == "interact":
		if done:
			draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 32, Color("#B4FF39"), 2.0)
		elif _progress > 0.0:
			draw_arc(Vector2.ZERO, 28.0, -PI / 2, -PI / 2 + TAU * _progress, 32, Color.WHITE, 4.0)
		else:
			draw_arc(Vector2.ZERO, 26.0 + pulse * 4.0, 0.0, TAU, 32, Color(color, 0.6), 1.5)
	elif kind == "rescue" and not _following:
		draw_arc(Vector2.ZERO, 24.0 + pulse * 6.0, 0.0, TAU, 24, Color("#FFC94D", 0.7), 2.0)
