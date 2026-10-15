class_name Projectile
extends Area2D
## Viên đạn. target_group = "enemies" hoặc "player" để biết được phép gây sát thương cho ai.
## Đạn của người chơi cũng khai thác được mỏ tài nguyên (nhóm "minable") với mining_damage.

var velocity := Vector2.ZERO
var damage := 10.0
var mining_damage := 0.0
var target_group := "enemies"
var color := Color.WHITE
var crit := false
var pierce := 0
var lifetime := 2.0
var _hit: Array = []


func setup(pos: Vector2, vel: Vector2, dmg: float, group: String, c: Color) -> void:
	position = pos
	velocity = vel
	damage = dmg
	target_group = group
	color = c
	rotation = vel.angle()


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body in _hit:
		return
	if body.is_in_group(target_group):
		_hit.append(body)
		body.take_damage(damage)
		if body.has_method("show_damage"):
			body.show_damage(damage, crit)
		pierce -= 1
		if pierce < 0:
			queue_free()
	elif body.is_in_group("minable") and target_group == "enemies":
		body.mine(mining_damage)
		queue_free()
	elif body.is_in_group("walls") or body.is_in_group("minable"):
		queue_free()


func _draw() -> void:
	var w := 4.0 if crit else 2.5
	draw_line(Vector2(-10, 0), Vector2.ZERO, color, w)
	draw_circle(Vector2.ZERO, w, Color.WHITE)
