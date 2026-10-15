class_name Pickup
extends Area2D
## Vật phẩm rơi trên sàn. Bị hút về phía người chơi khi trong bán kính hút đồ (chỉ số pickup_radius).

signal picked(item_id: String, count: int)

var item_id := ""
var count := 1
var _player: Player
var _t := 0.0
var _color := Color.WHITE


func setup(id: String, n: int, player: Player) -> void:
	item_id = id
	count = n
	_player = player
	var colors := {"material": "#C9D3E0", "consumable": "#B4FF39", "module": "#FF2BD6", "weapon": "#FFC94D", "key": "#00E5FF"}
	_color = Color(colors.get(Inventory.category(id), "#FFFFFF"))


func _ready() -> void:
	body_entered.connect(func(b):
		if b is Player:
			picked.emit(item_id, count)
			queue_free())


func _physics_process(delta: float) -> void:
	_t += delta
	if is_instance_valid(_player):
		var to := _player.global_position - global_position
		if to.length() < float(_player.stats.get("pickup_radius", 70)):
			global_position += to.normalized() * minf(to.length(), 420.0 * delta)
	queue_redraw()


func _draw() -> void:
	var s := 6.0 + sin(_t * 5.0)
	var rare := Inventory.category(item_id) in ["module", "weapon", "key"]
	if rare:
		draw_arc(Vector2.ZERO, s + 8.0, 0.0, TAU, 20, Color(_color, 0.5), 1.5)
	draw_rect(Rect2(-s / 2, -s / 2, s, s), _color)
