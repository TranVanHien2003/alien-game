class_name AllyTurret
extends StaticBody2D
## Tháp pháo tự động do Kỹ sư dựng. Bắn quái gần nhất trong tầm, tự hủy khi hết thời gian hoặc hết máu.

const PROJECTILE := preload("res://scenes/actors/projectile.tscn")

var hp := 150.0
var max_hp := 150.0
var damage := 12.0
var fire_interval := 0.35
var reach := 420.0
var life := 25.0
var _timer := 0.0
var _gun: Sprite2D


func setup(ability: Dictionary, power: float) -> void:
	damage = float(ability.get("damage", 12)) * power
	fire_interval = float(ability.get("fire_interval", 0.35))
	reach = float(ability.get("range", 420))
	life = float(ability.get("duration", 25)) * power
	max_hp = 150.0 * power
	hp = max_hp


func _ready() -> void:
	add_to_group("allies")
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 18.0
	add_child(shape)
	_gun = Sprite2D.new()
	_gun.texture = preload("res://assets/enemies/sentinel.png")
	_gun.scale = Vector2.ONE * 0.45
	_gun.modulate = Color("#9FE8FF")
	add_child(_gun)


func _physics_process(delta: float) -> void:
	life -= delta
	_timer -= delta
	if life <= 0.0 or hp <= 0.0:
		get_parent().add_child(Explosion.create(global_position, 40.0, Color("#9FE8FF")))
		queue_free()
		return
	var target: Node2D = null
	var best := reach
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var d := global_position.distance_to(enemy.global_position)
		if d < best:
			target = enemy
			best = d
	if target:
		var dir := (target.global_position - global_position).normalized()
		_gun.rotation = lerp_angle(_gun.rotation, dir.angle(), 0.3)
		if _timer <= 0.0:
			_timer = fire_interval
			var p := PROJECTILE.instantiate()
			p.setup(global_position + dir * 26.0, dir * 900.0, damage, "enemies", Color("#9FE8FF"))
			p.lifetime = reach / 900.0
			get_parent().add_child(p)
			Sfx.play("shoot", 0.1, -14.0)
	queue_redraw()


func take_damage(amount: float) -> void:
	hp -= amount


func _draw() -> void:
	draw_rect(Rect2(-18, -30, 36, 4), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-18, -30, 36 * clampf(life / 25.0, 0.0, 1.0), 4), Color("#9FE8FF"))
