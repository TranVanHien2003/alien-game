class_name Pickup
extends Area2D
## Vật phẩm rơi trên sàn (icon thật từ assets/items). Bị hút về phía người chơi khi trong bán kính hút đồ.

signal picked(item_id: String, count: int)

const RARE := ["module", "weapon", "key"]

var item_id := ""
var count := 1
var _t := 0.0
var _sprite: Sprite2D


func setup(id: String, n: int) -> void:
	item_id = id
	count = n


func _ready() -> void:
	body_entered.connect(func(b):
		if b is Unit and b.is_active():
			Sfx.play("pickup", 0.15, -8.0)
			picked.emit(item_id, count)
			queue_free())
	_sprite = Sprite2D.new()
	var path := "res://assets/items/%s.png" % item_id
	if ResourceLoader.exists(path):
		_sprite.texture = load(path)
	_sprite.scale = Vector2.ONE * 0.45
	add_child(_sprite)
	if Inventory.category(item_id) in RARE:
		var glow := PointLight2D.new()
		glow.texture = preload("res://assets/fx/light.png")
		glow.texture_scale = 0.8
		glow.color = Color("#FFC94D")
		add_child(glow)


func _physics_process(delta: float) -> void:
	_t += delta
	_sprite.position.y = sin(_t * 4.0) * 3.0
	# Bị hút về thành viên gần nhất trong bán kính hút đồ của người đó
	for unit in get_tree().get_nodes_in_group("squad_active"):
		var to: Vector2 = unit.global_position - global_position
		if to.length() < float(unit.stats.get("pickup_radius", 70)):
			global_position += to.normalized() * minf(to.length(), 420.0 * delta)
			break
