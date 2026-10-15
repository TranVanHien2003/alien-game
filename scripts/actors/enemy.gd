class_name Enemy
extends CharacterBody2D
## Quái vật / boss dựa trên data/enemies.
##   attack = "melee": đuổi theo và cắn     attack = "ranged": đứng yên và bắn
##   boss = true: nhiều pha (phases), mỗi pha luân phiên các đòn: aimed_burst, radial, charge, summon

signal died(enemy: Enemy)
signal hp_changed(hp: float, max_hp: float)
signal summon_requested(enemy_id: String, pos: Vector2)

const PROJECTILE := preload("res://scenes/actors/projectile.tscn")

var enemy_id := ""
var data: Dictionary = {}
var max_hp := 30.0
var hp := 30.0
var target: Node2D
var is_boss := false
var _attack_timer := 0.0
var _slow := 1.0
var _slow_timer := 0.0
var _flash := 0.0
var _color := Color.WHITE
var _radius := 14.0
var _pattern_index := 0
var _charge_left := 0.0
var _charge_dir := Vector2.ZERO
var _awake := false


func setup(id: String, player: Node2D) -> void:
	enemy_id = id
	data = Content.get_entry("enemies", id)
	max_hp = float(data.get("hp", 30))
	hp = max_hp
	target = player
	is_boss = data.get("boss", false)
	_color = Color(data.get("color", "#FF2BD6"))
	_radius = float(data.get("radius", 14))
	var shape := CircleShape2D.new()
	shape.radius = _radius
	$CollisionShape2D.shape = shape
	_attack_timer = randf() * float(data.get("fire_interval", 1.0))


func _physics_process(delta: float) -> void:
	_attack_timer -= delta
	_flash = maxf(0.0, _flash - delta)
	_slow_timer -= delta
	if _slow_timer <= 0.0:
		_slow = 1.0
	if not is_instance_valid(target):
		return
	var to_target := target.global_position - global_position
	var sees := to_target.length() <= float(data.get("sight", 360)) and _has_line_of_sight()
	_awake = _awake or sees

	if is_boss:
		_boss_process(delta, to_target)
	elif data.get("attack", "melee") == "melee":
		var speed := float(data.get("speed", 120)) * _slow
		velocity = to_target.normalized() * speed if sees else velocity.move_toward(Vector2.ZERO, 400 * delta)
		move_and_slide()
		_try_melee(to_target)
	elif sees and _attack_timer <= 0.0:
		_attack_timer = float(data.get("fire_interval", 1.5)) / _slow
		_fire(to_target.normalized(), float(data.get("projectile_speed", 300)))
	queue_redraw()


func _try_melee(to_target: Vector2) -> void:
	if to_target.length() < _radius + 18.0 and _attack_timer <= 0.0:
		target.take_damage(float(data.get("damage", 10)))
		_attack_timer = 0.8


func _fire(dir: Vector2, speed: float) -> void:
	var p := PROJECTILE.instantiate()
	p.setup(global_position + dir * (_radius + 6.0), dir * speed, float(data.get("damage", 8)), "player", _color)
	p.lifetime = 3.0
	get_parent().add_child(p)


# --- Boss ------------------------------------------------------------------------

func current_phase() -> Dictionary:
	var ratio := hp / max_hp
	for phase in data.get("phases", []):
		if ratio > float(phase.get("hp_above", 0.0)):
			return phase
	var phases: Array = data.get("phases", [{}])
	return phases.back()


func _boss_process(delta: float, to_target: Vector2) -> void:
	if not _awake:
		return
	var phase := current_phase()
	if _charge_left > 0.0:
		_charge_left -= delta
		velocity = _charge_dir * float(data.get("speed", 80)) * 6.0 * _slow
	else:
		velocity = to_target.normalized() * float(data.get("speed", 80)) * _slow
	move_and_slide()
	_try_melee(to_target)
	if _attack_timer > 0.0:
		return
	_attack_timer = float(phase.get("interval", 1.5)) / _slow
	var patterns: Array = phase.get("patterns", ["radial"])
	var pattern: String = patterns[_pattern_index % patterns.size()]
	_pattern_index += 1
	var speed := float(data.get("projectile_speed", 320))
	match pattern:
		"aimed_burst":
			for i in 5:
				_fire(to_target.normalized().rotated(lerpf(-0.35, 0.35, i / 4.0)), speed)
		"radial":
			var offset := randf() * TAU
			for i in 16:
				_fire(Vector2.from_angle(offset + TAU * i / 16.0), speed * 0.8)
		"charge":
			_charge_dir = to_target.normalized()
			_charge_left = 0.5
		"summon":
			for i in 2:
				summon_requested.emit(data.get("summon", "crawler"), global_position + Vector2.from_angle(randf() * TAU) * (_radius + 30.0))


# --- Chung -----------------------------------------------------------------------

func _has_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	amount *= 100.0 / (100.0 + float(data.get("armor", 0)))
	hp -= amount
	_flash = 0.08
	_awake = true
	hp_changed.emit(maxf(hp, 0.0), max_hp)
	if hp <= 0.0:
		died.emit(self)
		queue_free()


func show_damage(amount: float, crit: bool) -> void:
	get_parent().add_child(FloatingText.create(global_position, str(roundi(amount)) + ("!" if crit else ""), Color("#FFC94D") if crit else Color.WHITE, 20 if crit else 14))


func apply_slow(factor: float, duration: float) -> void:
	_slow = factor
	_slow_timer = duration


func _draw() -> void:
	var c := Color.WHITE if _flash > 0.0 else _color
	if is_boss:
		var pts := PackedVector2Array()
		for i in 8:
			pts.append(Vector2.from_angle(TAU * i / 8.0 + PI / 8.0) * _radius)
		draw_colored_polygon(pts, Color(c, 0.3))
		pts.append(pts[0])
		draw_polyline(pts, c, 3.0)
		draw_circle(Vector2.ZERO, _radius * 0.35, c)
	elif data.get("attack", "melee") == "ranged":
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(Vector2.from_angle(TAU * i / 6.0) * _radius)
		draw_colored_polygon(pts, Color(c, 0.3))
		pts.append(pts[0])
		draw_polyline(pts, c, 2.0)
	else:
		draw_circle(Vector2.ZERO, _radius, Color(c, 0.3))
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 16, c, 2.0)
	if _slow < 1.0:
		draw_arc(Vector2.ZERO, _radius + 5.0, 0.0, TAU, 16, Color("#B4FF39", 0.6), 1.5)
	if not is_boss and hp < max_hp:
		draw_rect(Rect2(-_radius, -_radius - 8, _radius * 2, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-_radius, -_radius - 8, _radius * 2 * hp / max_hp, 3), c)
