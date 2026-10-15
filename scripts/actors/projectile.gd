class_name Projectile
extends Area2D
## Viên đạn laser. target_group = "enemies" hoặc "player" để biết được phép gây sát thương cho ai.
## Đạn của người chơi cũng khai thác được mỏ tài nguyên (nhóm "minable") với mining_damage.

## Vật liệu "không bị ánh sáng ảnh hưởng" + cộng màu: đạn/hiệu ứng luôn sáng rực trong bóng tối
static var GLOW: CanvasItemMaterial

var velocity := Vector2.ZERO
var damage := 10.0
var mining_damage := 0.0
var target_group := "enemies"
var color := Color.WHITE
var crit := false
var pierce := 0
var lifetime := 2.0
var texture_name := "laser_blue"
var _hit: Array = []


static func glow_material() -> CanvasItemMaterial:
	if GLOW == null:
		GLOW = CanvasItemMaterial.new()
		GLOW.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		GLOW.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return GLOW


func setup(pos: Vector2, vel: Vector2, dmg: float, group: String, c: Color) -> void:
	position = pos
	velocity = vel
	damage = dmg
	target_group = group
	color = c
	rotation = vel.angle()


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/fx/%s.png" % texture_name)
	# Sprite laser gốc nằm dọc -> xoay để nằm theo hướng bay
	sprite.rotation = PI / 2.0
	sprite.scale = Vector2.ONE * (0.75 if crit else 0.55)
	sprite.material = glow_material()
	add_child(sprite)


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
		_impact()
		pierce -= 1
		if pierce < 0:
			queue_free()
	elif body.is_in_group("minable") and target_group == "enemies":
		body.mine(mining_damage)
		Sfx.play("mine", 0.15, -8.0)
		_impact()
		queue_free()
	elif body.is_in_group("walls") or body.is_in_group("minable") or body is TileMapLayer:
		_impact()
		queue_free()


func _impact() -> void:
	var fx := Explosion.create(global_position, 18.0, color, "hit_red" if target_group == "player" else "hit_blue")
	get_parent().add_child(fx)
