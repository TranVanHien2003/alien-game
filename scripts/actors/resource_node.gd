class_name ResourceNode
extends StaticBody2D
## Mỏ tài nguyên / thùng hàng: bắn (hoặc dùng máy cắt plasma) để khai thác, vỡ ra rơi nguyên liệu.

signal depleted(node: ResourceNode, by: Node)

var node_id := ""
var data: Dictionary = {}
var max_hp := 40.0
var hp := 40.0
var _color := Color.WHITE
var _flash := 0.0
var _sprite: Sprite2D


func setup(id: String) -> void:
	node_id = id
	data = Content.get_entry("resource_nodes", id)
	max_hp = float(data.get("hp", 40))
	hp = max_hp
	_color = Color(data.get("color", "#C9D3E0"))
	var shape := CircleShape2D.new()
	shape.radius = float(data.get("radius", 18))
	$CollisionShape2D.shape = shape
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/props/%s.png" % data.get("sprite", "ore_metal"))
	_sprite.scale = Vector2.ONE * float(data.get("sprite_scale", 1.0))
	_sprite.rotation = randf_range(-0.3, 0.3)
	add_child(_sprite)


## by: Unit đang khai thác (null nếu do đạn) — dùng để biết ai lấy được thưởng nghiên cứu.
func mine(amount: float, by: Node = null) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash = 0.06
	queue_redraw()
	if hp <= 0.0:
		depleted.emit(self, by)
		get_parent().add_child(Explosion.create(global_position, 30.0, _color, "spark"))
		queue_free()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		_sprite.modulate = Color(2, 2, 2) if _flash > 0.0 else Color.WHITE
		_sprite.position = Vector2(randf_range(-2, 2), randf_range(-2, 2)) if _flash > 0.0 else Vector2.ZERO


func _draw() -> void:
	if hp < max_hp:
		draw_rect(Rect2(-18, -30, 36, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-18, -30, 36 * hp / max_hp, 4), _color)
