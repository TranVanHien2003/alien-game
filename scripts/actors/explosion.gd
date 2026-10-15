class_name Explosion
extends Sprite2D
## Hiệu ứng nổ / chớp sáng: sprite từ assets/fx phóng to rồi mờ dần, luôn sáng trong bóng tối.

var radius := 100.0
var _t := 0.0


static func create(pos: Vector2, r: float, c: Color, texture_name: String = "explosion") -> Explosion:
	var e := Explosion.new()
	e.position = pos
	e.radius = r
	e.texture = load("res://assets/fx/%s.png" % texture_name)
	e.modulate = c
	e.material = Projectile.glow_material()
	e.rotation = randf() * TAU
	e.z_index = 5
	return e


func _process(delta: float) -> void:
	_t += delta * 3.5
	if _t >= 1.0:
		queue_free()
		return
	var size := maxf(1.0, float(texture.get_width()))
	scale = Vector2.ONE * (radius * 2.0 / size) * (0.4 + 0.6 * _t)
	modulate.a = 1.0 - _t
