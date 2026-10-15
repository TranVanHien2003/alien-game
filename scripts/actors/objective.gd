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


func setup(objective_kind: String, objective_label: String, accent: Color) -> void:
	kind = objective_kind
	label = objective_label
	color = accent


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
	match kind:
		"collect":
			var s := 9.0
			draw_colored_polygon(PackedVector2Array([Vector2(0, -s), Vector2(s, 0), Vector2(0, s), Vector2(-s, 0)]), Color(color, pulse))
		"interact":
			var c := Color("#4D9DFF") if done else color
			draw_rect(Rect2(-14, -14, 28, 28), Color(c, 0.2))
			draw_rect(Rect2(-14, -14, 28, 28), c, false, 2.0)
			if _progress > 0.0 and not done:
				draw_arc(Vector2.ZERO, 22.0, -PI / 2, -PI / 2 + TAU * _progress, 32, Color.WHITE, 3.0)
		"rescue":
			draw_circle(Vector2.ZERO, 12.0, Color("#FFC94D", 0.35))
			draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 20, Color("#FFC94D"), 2.0)
			if not _following:
				draw_arc(Vector2.ZERO, 18.0 + pulse * 6.0, 0.0, TAU, 24, Color("#FFC94D", 0.5), 1.5)
