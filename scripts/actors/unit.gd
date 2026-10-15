class_name Unit
extends CharacterBody2D
## Một thành viên đội đổ bộ. Người chơi là chỉ huy: ra lệnh (di chuyển / tấn công / khai thác /
## tương tác / cứu đồng đội / rút lui), còn Unit tự tìm đường, tự bắn quái trong tầm,
## tự dùng công cụ theo vai trò (khoan, tia hồi máu...) và tự nhặt đồ.

signal downed(unit: Unit)
signal lost(unit: Unit)

const PROJECTILE := preload("res://scenes/actors/projectile.tscn")

enum State { ACTIVE, DOWNED, LOST, EVACUATED }

var char_id := ""
var level: Node
var stats: Dictionary = {}
var base_stats: Dictionary = {}
var hp := 100.0
var energy := 100.0
var weapon_id := ""
var tool_id := ""
var abilities: Array = []
var state := State.ACTIVE
var selected := false
var hold_position := false
var protected_hazards: Array = []
## Lệnh hiện tại: {type: "idle"|"move"|"attack"|"mine"|"interact"|"revive"|"evac", target, pos}
var order: Dictionary = {"type": "idle"}
var revive_progress := 0.0
## Hành động trong màn -> tăng thuộc tính khi về tàu (AttributeSystem.apply_mission_growth)
var counters := {"kills": 0, "mined": 0.0, "worked": 0.0, "revived": 0, "healed": 0.0, "distance": 0.0}
## Người lạ / người được cứu gia nhập giữa màn
var guest := false
## Chế độ tự động (AutoPilot). Lệnh thủ công của chỉ huy luôn được ưu tiên làm xong trước.
var auto := true
var bleed_left := 0.0

var _cooldowns: Dictionary = {}
var _buffs: Array = []
var _fire_timer := 0.0
var _think := 0.0
var _enemy: Node2D
var _beam_target := Vector2.ZERO
var _beam_color := Color.TRANSPARENT
var _beam_time := 0.0
var _hurt_flash := 0.0
var _muzzle_time := 0.0
var _sprite_id := "survivor"
var _tint := Color.WHITE
var _role_color := Color.WHITE

@onready var body: AnimatedSprite2D = $Body
@onready var feet: AnimatedSprite2D = $Feet
@onready var muzzle: Sprite2D = $Body/Muzzle
@onready var sight_light: PointLight2D = $Sight
@onready var agent: NavigationAgent2D = $Agent


func setup(id: String, lvl: Node, hazards_protected: Array) -> void:
	char_id = id
	level = lvl
	protected_hazards = hazards_protected
	var character := Content.get_entry("characters", id)
	_sprite_id = character.get("sprite", "survivor")
	_tint = Color(character.get("tint", "#FFFFFF"))
	_role_color = Roles.color_of(Roles.role_of(id))
	weapon_id = Inventory.equipped(Game, id, "weapon")
	tool_id = Inventory.equipped(Game, id, "tool")
	abilities = Abilities.for_unit(Game, id)
	base_stats = CombatStats.compute(Game, id)
	stats = base_stats.duplicate()
	hp = stats.max_hp
	energy = stats.max_energy
	# Sprite có hoạt ảnh: màu quân phục theo vai trò, tư thế theo loại súng
	body.sprite_frames = UnitSprites.body_frames(Roles.role_of(id), UnitSprites.kind_for_weapon(weapon_data().get("type", "rifle")))
	body.play("idle")
	body.animation_finished.connect(func(): body.play("idle"))
	feet.sprite_frames = UnitSprites.feet_frames()
	feet.play("idle")
	sight_light.texture_scale = float(stats.sight_radius) / 128.0
	_think = randf() * 0.3


## Tính lại chỉ số (sau kỳ ngộ / tài năng mới), giữ tỉ lệ máu.
func refresh_stats() -> void:
	var ratio := hp / maxf(1.0, stats.max_hp)
	base_stats = CombatStats.compute(Game, char_id)
	_recompute_stats()
	abilities = Abilities.for_unit(Game, char_id)
	hp = stats.max_hp * ratio


func display_name() -> String:
	return CrewSystem.display_name(char_id)


func weapon_data() -> Dictionary:
	return Content.get_entry("items", weapon_id).get("weapon", {})


func tool_data() -> Dictionary:
	return Content.get_entry("items", tool_id).get("tool", {})


func is_active() -> bool:
	return state == State.ACTIVE


func weapon_range() -> float:
	return float(weapon_data().get("range", 400))


# --- Lệnh từ chỉ huy ---------------------------------------------------------------

## manual = true: lệnh của chỉ huy (AutoPilot không ghi đè cho tới khi xong).
func command(new_order: Dictionary, manual: bool = true) -> void:
	if not is_active():
		return
	order = new_order
	order.manual = manual
	_enemy = null
	match order.type:
		"move", "evac", "advance":
			agent.target_position = order.pos
		_:
			if is_instance_valid(order.get("target")):
				agent.target_position = order.target.global_position


## Dừng theo lệnh chỉ huy: đứng yên 8 giây (lệnh thủ công) rồi mới quay lại tự động.
func stop() -> void:
	order = {"type": "idle", "manual": true, "until": Time.get_ticks_msec() + 8000}
	agent.target_position = global_position


# --- Vòng lặp ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_tick(delta)
	match state:
		State.DOWNED:
			bleed_left -= delta
			if revive_progress >= 1.0:
				_revive()
			elif bleed_left <= 0.0:
				state = State.LOST
				visible = false
				lost.emit(self)
			queue_redraw()
			return
		State.LOST, State.EVACUATED:
			return

	_think -= delta
	if _think <= 0.0:
		_think = 0.25
		_enemy = _pick_enemy()

	var move_to := Vector2.INF
	var work_done := false
	match order.type:
		"move", "evac":
			if agent.is_navigation_finished():
				if order.type == "move":
					order = {"type": "idle"}
			else:
				move_to = agent.get_next_path_position()
		"advance":
			# Tiến công: đi tới điểm, gặp quái trong tầm bắn thì dừng lại giao chiến
			var engaged := is_instance_valid(_enemy) and global_position.distance_to(_enemy.global_position) <= weapon_range() * 0.9
			if not engaged:
				if agent.is_navigation_finished():
					order = {"type": "idle"}
				else:
					move_to = agent.get_next_path_position()
		"attack":
			if not is_instance_valid(order.target) or order.target.hp <= 0.0:
				order = {"type": "idle"}
			else:
				_enemy = order.target
				if global_position.distance_to(_enemy.global_position) > weapon_range() * 0.85 or not _sees(_enemy):
					move_to = _path_to(order.target.global_position)
		"mine":
			work_done = _do_mine(delta)
			if not work_done and is_instance_valid(order.get("target")):
				move_to = _path_to(order.target.global_position)
		"interact":
			work_done = _do_interact(delta)
			if not work_done and is_instance_valid(order.get("target")):
				move_to = _path_to(order.target.global_position)
		"revive":
			work_done = _do_revive(delta)
			if not work_done and is_instance_valid(order.get("target")):
				move_to = _path_to(order.target.global_position)
		"idle":
			# Chủ động: thấy quái ngoài tầm bắn thì tiến lại gần (trừ khi giữ vị trí)
			if not hold_position and is_instance_valid(_enemy) and global_position.distance_to(_enemy.global_position) > weapon_range() * 0.85:
				move_to = _path_to(_enemy.global_position)

	if move_to != Vector2.INF:
		velocity = (move_to - global_position).normalized() * float(stats.move_speed)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
	move_and_slide()
	counters.distance += velocity.length() * delta

	# Đang khai thác/sửa thì chỉ bắn khi quái đã đến gần
	var busy: bool = order.type in ["mine", "interact", "revive"] and work_done
	if is_instance_valid(_enemy) and (not busy or global_position.distance_to(_enemy.global_position) < 220.0):
		_face(_enemy.global_position - global_position)
		if global_position.distance_to(_enemy.global_position) <= weapon_range() and _fire_timer <= 0.0:
			_shoot(_enemy.global_position)
	elif velocity.length_squared() > 100.0:
		_face(velocity)
	_auto_heal(delta)
	_update_animation()
	queue_redraw()


func _tick(delta: float) -> void:
	_fire_timer -= delta
	_beam_time -= delta
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	_muzzle_time -= delta
	muzzle.visible = _muzzle_time > 0.0
	for id in _cooldowns.keys():
		_cooldowns[id] = maxf(0.0, _cooldowns[id] - delta)
	var changed := false
	for buff in _buffs.duplicate():
		buff.time_left -= delta
		if buff.time_left <= 0.0:
			_buffs.erase(buff)
			changed = true
	if changed:
		_recompute_stats()
	if is_active():
		energy = minf(stats.max_energy, energy + stats.energy_regen * delta)
	var tint := Color.WHITE
	if state == State.DOWNED:
		tint = Color(0.5, 0.5, 0.55)
	elif _hurt_flash > 0.0:
		tint = Color(3, 1.2, 1.2)
	body.modulate = tint


func _path_to(pos: Vector2) -> Vector2:
	if agent.target_position.distance_squared_to(pos) > 900.0:
		agent.target_position = pos
	return agent.get_next_path_position() if not agent.is_navigation_finished() else pos


func _face(dir: Vector2) -> void:
	if dir.length_squared() > 1.0:
		body.rotation = lerp_angle(body.rotation, dir.angle(), 0.3)
		feet.rotation = body.rotation


func _update_animation() -> void:
	var moving := velocity.length_squared() > 400.0
	if body.animation != "shoot" or not body.is_playing():
		var anim := "move" if moving else "idle"
		if body.animation != anim:
			body.play(anim)
	var feet_anim := "walk" if moving else "idle"
	if feet.animation != feet_anim:
		feet.play(feet_anim)
	feet.speed_scale = clampf(velocity.length() / 170.0, 0.5, 2.0)


func _sees(target: Node2D) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1)
	query.exclude = [target.get_rid()] if target is CollisionObject2D else []
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _pick_enemy() -> Node2D:
	var best: Node2D = null
	var best_d := float(stats.sight_radius)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var d := global_position.distance_to(enemy.global_position)
		if d < best_d and _sees(enemy):
			best = enemy
			best_d = d
	return best


# --- Chiến đấu -----------------------------------------------------------------------

func _shoot(target_pos: Vector2) -> void:
	var w := weapon_data()
	if w.is_empty():
		return
	_fire_timer = float(w.get("fire_interval", 0.25)) / maxf(0.1, stats.fire_rate_mult)
	var aim := (target_pos - global_position).normalized()
	var pellets := int(w.get("pellets", 1))
	var spread := float(w.get("spread", 0.0))
	var speed := float(w.get("projectile_speed", 700))
	Sfx.play(w.get("sound", "shoot"), 0.1, -12.0)
	_muzzle_time = 0.05
	body.play("shoot")
	for i in pellets:
		var angle := randf_range(-spread, spread) * 0.5 if pellets == 1 else lerpf(-spread, spread, float(i) / (pellets - 1)) * 0.5
		var dir := aim.rotated(angle)
		var dmg: float = float(w.get("damage", 10)) * stats.damage_mult
		var crit: bool = randf() < stats.crit_chance + float(w.get("crit_bonus", 0.0))
		if crit:
			dmg *= stats.crit_mult
		var p := PROJECTILE.instantiate()
		p.setup(global_position + dir * 30.0, dir * speed, dmg, "enemies", Color(w.get("color", "#00E5FF")))
		p.texture_name = w.get("projectile", "laser_blue")
		p.crit = crit
		p.pierce = int(w.get("pierce", 0))
		p.lifetime = float(w.get("range", 600)) / speed
		p.mining_damage = dmg * float(w.get("mining_mult", 0.5)) * stats.mining_power
		p.source = self
		get_parent().add_child(p)


func take_damage(amount: float) -> void:
	if not is_active():
		return
	hp = maxf(0.0, hp - amount * 100.0 / (100.0 + maxf(0.0, stats.armor)))
	_hurt_flash = 0.12
	if hp <= 0.0:
		_go_down()


func take_hazard_damage(amount: float) -> void:
	if not is_active():
		return
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		_go_down()


func heal(amount: float) -> void:
	if is_active():
		hp = minf(stats.max_hp, hp + amount)


func is_protected(hazard: String) -> bool:
	return hazard in protected_hazards


func _go_down() -> void:
	state = State.DOWNED
	body.stop()
	feet.visible = false
	revive_progress = 0.0
	bleed_left = float(Content.config.get("squad", {}).get("bleed_out_time", 30))
	order = {"type": "idle"}
	velocity = Vector2.ZERO
	remove_from_group("squad_active")
	Sfx.play("hurt")
	downed.emit(self)


func _revive() -> void:
	state = State.ACTIVE
	feet.visible = true
	hp = stats.max_hp * 0.35
	revive_progress = 0.0
	add_to_group("squad_active")


# --- Công cụ theo vai trò --------------------------------------------------------------

func _in_reach(target: Node2D, reach: float) -> bool:
	return is_instance_valid(target) and global_position.distance_to(target.global_position) <= reach


func _do_mine(delta: float) -> bool:
	var node = order.get("target")
	if not is_instance_valid(node):
		order = {"type": "idle"}
		return false
	if tool_data().get("type", "") == "drill":
		if not _in_reach(node, float(tool_data().get("range", 70)) + 20.0):
			return false
		var amount: float = float(tool_data().get("power", 20)) * stats.mining_power * delta
		node.mine(amount, self)
		counters.mined += amount
		_beam(node.global_position, Color("#FFC94D"))
		_face(node.global_position - global_position)
		return true
	# Không có máy khoan: bắn vào mỏ
	if not _in_reach(node, minf(weapon_range() * 0.6, 260.0)):
		return false
	_face(node.global_position - global_position)
	if _fire_timer <= 0.0 and not (is_instance_valid(_enemy) and global_position.distance_to(_enemy.global_position) < 220.0):
		_shoot(node.global_position)
	return true


func _do_interact(delta: float) -> bool:
	var obj = order.get("target")
	if not is_instance_valid(obj) or obj.done:
		order = {"type": "idle"}
		return false
	if not _in_reach(obj, 56.0):
		return false
	var speed: float = stats.interact_speed
	if tool_data().get("type", "") == "repair":
		speed *= 1.0 + float(tool_data().get("power", 0.5))
	obj.work(self, delta * speed)
	counters.worked += delta * speed
	_face(obj.global_position - global_position)
	if obj.done:
		order = {"type": "idle"}
	return true


func _do_revive(delta: float) -> bool:
	var ally = order.get("target")
	if not is_instance_valid(ally) or ally.state != State.DOWNED:
		order = {"type": "idle"}
		return false
	if not _in_reach(ally, 52.0):
		return false
	var revive_time := float(Content.config.get("squad", {}).get("revive_time", 4.0))
	var speed: float = stats.revive_speed * (1.5 if tool_data().get("type", "") == "med" else 1.0)
	ally.revive_progress += delta * speed / revive_time
	_beam(ally.global_position, Color("#7CFFB2"))
	if ally.revive_progress >= 1.0:
		order = {"type": "idle"}
		counters.revived += 1
	return true


## Y sĩ (tia hồi phục): tự hồi máu đồng đội thấp máu nhất trong tầm.
func _auto_heal(delta: float) -> void:
	if tool_data().get("type", "") != "med":
		return
	var reach := float(tool_data().get("range", 200))
	var best: Unit = null
	for ally in get_tree().get_nodes_in_group("squad_active"):
		if ally.hp < ally.stats.max_hp and global_position.distance_to(ally.global_position) <= reach:
			if best == null or ally.hp / ally.stats.max_hp < best.hp / best.stats.max_hp:
				best = ally
	if best:
		var amount: float = float(tool_data().get("power", 10)) * stats.heal_power * delta
		best.heal(amount)
		counters.healed += amount
		if best != self:
			_beam(best.global_position, Color("#7CFFB2"))


func _beam(target: Vector2, color: Color) -> void:
	_beam_target = target
	_beam_color = color
	_beam_time = 0.1


# --- Kỹ năng & vật phẩm ----------------------------------------------------------------

func cooldown_left(ability_id: String) -> float:
	return _cooldowns.get(ability_id, 0.0)


func use_ability(ability_id: String, target_pos: Vector2) -> bool:
	var a := Content.get_entry("abilities", ability_id)
	if not is_active() or a.is_empty() or cooldown_left(ability_id) > 0.0 or energy < float(a.get("energy", 0)):
		return false
	energy -= float(a.get("energy", 0))
	_cooldowns[ability_id] = float(a.get("cooldown", 10))
	Sfx.play("ability")
	var target := global_position + (target_pos - global_position).limit_length(float(a.get("range", 400)))
	match a.get("type", ""):
		"heal":
			heal(float(a.get("amount", 30)) * stats.heal_power)
		"heal_allies":
			for ally in get_tree().get_nodes_in_group("squad_active"):
				if global_position.distance_to(ally.global_position) <= float(a.get("radius", 250)):
					ally.heal(float(a.get("amount", 40)) * stats.heal_power)
			get_parent().add_child(Explosion.create(global_position, float(a.get("radius", 250)), Color("#7CFFB2")))
		"slow_enemies":
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if global_position.distance_to(enemy.global_position) < 700.0:
					enemy.apply_slow(float(a.get("factor", 0.4)), float(a.get("duration", 5)))
		"time_slow":
			Engine.time_scale = float(a.get("time_scale", 0.4))
			get_tree().create_timer(float(a.get("duration", 4)), true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
		"aoe":
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if enemy.global_position.distance_to(target) <= float(a.get("radius", 120)):
					enemy.take_damage(float(a.get("damage", 50)) * stats.damage_mult)
			get_parent().add_child(Explosion.create(target, float(a.get("radius", 120)), Color("#FFC94D")))
			Sfx.play("explosion")
		"mining_blast":
			for node in get_tree().get_nodes_in_group("minable"):
				if node.global_position.distance_to(target) <= float(a.get("radius", 150)):
					node.mine(float(a.get("mining", 100)) * stats.mining_power, self)
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if enemy.global_position.distance_to(target) <= float(a.get("radius", 150)):
					enemy.take_damage(float(a.get("damage", 40)))
			get_parent().add_child(Explosion.create(target, float(a.get("radius", 150)), Color("#C9A27A")))
			Sfx.play("explosion")
		"buff":
			add_buff(a.get("buff", {}), float(a.get("duration", 5)))
		"turret":
			var power := float(tool_data().get("power", 1.0)) if tool_data().get("type", "") == "turret" else 1.0
			level.spawn_turret(target, a, power)
		"flare":
			level.spawn_flare(target, float(a.get("radius", 500)), float(a.get("duration", 15)))
		"scan":
			level.reveal(float(a.get("duration", 15)))
	return true


func apply_consumable(use: Dictionary) -> void:
	if use.has("heal"):
		heal(float(use.heal))
	if use.has("energy"):
		energy = minf(stats.max_energy, energy + float(use.energy))
	if use.has("buff"):
		add_buff(use.buff, float(use.get("duration", 5)))


func add_buff(mods: Dictionary, duration: float) -> void:
	_buffs.append({"mods": mods, "time_left": duration})
	_recompute_stats()


func _recompute_stats() -> void:
	stats = base_stats.duplicate()
	for buff in _buffs:
		for stat in buff.mods:
			stats[stat] = float(stats.get(stat, 0.0)) + float(buff.mods[stat])
	stats = CombatStats.clamp_stats(stats)


# --- Vẽ ------------------------------------------------------------------------------------

func _draw() -> void:
	if state == State.DOWNED:
		var t := clampf(bleed_left / float(Content.config.get("squad", {}).get("bleed_out_time", 30)), 0.0, 1.0)
		draw_arc(Vector2.ZERO, 26.0, -PI / 2, -PI / 2 + TAU * t, 32, Color("#FF2BD6"), 3.0)
		if revive_progress > 0.0:
			draw_arc(Vector2.ZERO, 32.0, -PI / 2, -PI / 2 + TAU * revive_progress, 32, Color("#7CFFB2"), 4.0)
		draw_string(UI.font(), Vector2(-40, -36), "CẦN CỨU", HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color("#FF2BD6"))
		return
	if selected:
		draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 32, Color("#B4FF39"), 2.0)
	draw_arc(Vector2.ZERO, 20.0, PI * 0.15, PI * 0.85, 12, _role_color, 3.0)
	# Thanh máu & năng lượng
	draw_rect(Rect2(-18, -32, 36, 4), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-18, -32, 36 * hp / stats.max_hp, 4), Color("#7CFFB2") if hp > stats.max_hp * 0.4 else Color("#FF5A5A"))
	draw_rect(Rect2(-18, -27, 36 * energy / maxf(1.0, stats.max_energy), 2), Color("#00E5FF"))
	if _beam_time > 0.0:
		draw_line(Vector2.ZERO, to_local(_beam_target), _beam_color, 3.0)
		draw_line(Vector2.ZERO, to_local(_beam_target), Color(1, 1, 1, 0.6), 1.0)
