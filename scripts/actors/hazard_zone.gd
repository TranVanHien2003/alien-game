class_name HazardZone
extends Area2D
## Vùng nguy hiểm môi trường (bức xạ, lạnh, sinh vật lạ). Gây sát thương liên tục
## trừ khi đội đã được bảo vệ bằng công nghệ hoặc kỹ năng (MissionSystem.is_protected).

const COLORS := {"radiation": Color("#B4FF39"), "extreme_cold": Color("#9FE8FF"), "unknown_biology": Color("#FF2BD6")}

var hazard := "radiation"
var size := Vector2(160, 160)
var dps := 8.0
var _bodies: Array[Player] = []
var _t := 0.0


func setup(hazard_id: String, zone_size: Vector2, damage_per_second: float) -> void:
	hazard = hazard_id
	size = zone_size
	dps = damage_per_second


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	$CollisionShape2D.shape = shape
	body_entered.connect(func(b): if b is Player: _bodies.append(b))
	# Vài đám khói/hạt trôi lơ lửng để vùng nguy hiểm "có thật"
	for i in 4:
		var puff := Sprite2D.new()
		puff.texture = preload("res://assets/fx/smoke.png")
		puff.modulate = Color(COLORS.get(hazard, Color.RED), 0.35)
		puff.material = Projectile.glow_material()
		puff.position = Vector2(randf_range(-0.35, 0.35) * size.x, randf_range(-0.35, 0.35) * size.y)
		puff.scale = Vector2.ONE * minf(size.x, size.y) / 260.0
		add_child(puff)
	body_exited.connect(func(b): if b is Player: _bodies.erase(b))


func _physics_process(delta: float) -> void:
	_t += delta
	for i in get_child_count():
		var c := get_child(i)
		if c is Sprite2D:
			c.rotation += delta * (0.2 + i * 0.05)
	for player in _bodies:
		if not player.is_protected(hazard):
			player.take_hazard_damage(dps * delta)
	queue_redraw()


func _draw() -> void:
	var c: Color = COLORS.get(hazard, Color.RED)
	var r := Rect2(-size / 2.0, size)
	draw_rect(r, Color(c, 0.08 + 0.05 * sin(_t * 3.0)))
	draw_rect(r, Color(c, 0.5), false, 1.5)
	var label: String = Content.config.get("hazards", {}).get(hazard, {}).get("label", hazard)
	draw_string(UI.font(), r.position + Vector2(6, 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(c, 0.8))
