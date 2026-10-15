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
var _repath := 0.0
var _base_tint := Color.WHITE

@onready var body: Sprite2D = $Body
@onready var agent: NavigationAgent2D = $Agent


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
	var sprite_path := "res://assets/enemies/%s.png" % data.get("sprite", id)
	if ResourceLoader.exists(sprite_path):
		$Body.texture = load(sprite_path)
	$Body.scale = Vector2.ONE * float(data.get("sprite_scale", 1.0))
	_base_tint = Color(data.get("tint", "#FFFFFF"))
	$Body.modulate = _base_tint
	$Agent.radius = _radius
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
		velocity = _chase_direction(delta, to_target, sees) * speed if _awake else velocity.move_toward(Vector2.ZERO, 400 * delta)
		move_and_slide()
		_try_melee(to_target)
	elif sees and _attack_timer <= 0.0:
		_attack_timer = float(data.get("fire_interval", 1.5)) / _slow
		_fire(to_target.normalized(), float(data.get("projectile_speed", 300)))
	_face(to_target if (sees or is_boss or data.get("attack", "melee") == "ranged") else velocity)
	body.modulate = Color(3, 3, 3) if _flash > 0.0 else (_base_tint * Color(0.75, 1.3, 0.75) if _slow < 1.0 else _base_tint)
	queue_redraw()


## Thấy mục tiêu: lao thẳng. Không thấy (đã bị đánh thức): đi theo lưới tìm đường vòng qua tường.
func _chase_direction(delta: float, to_target: Vector2, sees: bool) -> Vector2:
	if sees:
		return to_target.normalized()
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.4
		agent.target_position = target.global_position
	if agent.is_navigation_finished():
		return Vector2.ZERO
	return (agent.get_next_path_position() - global_position).normalized()


func _face(dir: Vector2) -> void:
	if dir.length_squared() > 1.0:
		body.rotation = lerp_angle(body.rotation, dir.angle(), 0.25)


func _try_melee(to_target: Vector2) -> void:
	if to_target.length() < _radius + 18.0 and _attack_timer <= 0.0:
		target.take_damage(float(data.get("damage", 10)))
		_attack_timer = 0.8


func _fire(dir: Vector2, speed: float) -> void:
	var p := PROJECTILE.instantiate()
	p.setup(global_position + dir * (_radius + 6.0), dir * speed, float(data.get("damage", 8)), "player", _color)
	p.texture_name = data.get("projectile", "laser_red")
	p.lifetime = 3.0
	Sfx.play("shoot_enemy", 0.1, -10.0)
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
	Sfx.play("hit", 0.2, -10.0)
	if hp <= 0.0:
		died.emit(self)
		Sfx.play("boss_explosion" if is_boss else ("slime" if data.get("attack", "melee") == "melee" else "explosion"))
		get_parent().add_child(Explosion.create(global_position, _radius * (4.0 if is_boss else 2.2), _color))
		queue_free()


func show_damage(amount: float, crit: bool) -> void:
	get_parent().add_child(FloatingText.create(global_position, str(roundi(amount)) + ("!" if crit else ""), Color("#FFC94D") if crit else Color.WHITE, 20 if crit else 14))


func apply_slow(factor: float, duration: float) -> void:
	_slow = factor
	_slow_timer = duration


func _draw() -> void:
	if not is_boss and hp < max_hp:
		draw_rect(Rect2(-_radius, -_radius - 10, _radius * 2, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-_radius, -_radius - 10, _radius * 2 * hp / max_hp, 4), _color)
