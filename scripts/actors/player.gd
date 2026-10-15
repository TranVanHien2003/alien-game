class_name Player
extends CharacterBody2D
## Đội trưởng do người chơi điều khiển trong màn action.
##   WASD: di chuyển   Chuột trái: bắn   Shift: lướt   1/2 hoặc lăn chuột: đổi vũ khí
##   Q/R: kỹ năng chủ động   3/4: dùng vật phẩm   E: tương tác
## Chỉ số lấy từ CombatStats (kỹ năng + module + công nghệ) cộng buff tạm thời.

signal hp_changed(hp: float, max_hp: float)
signal energy_changed(energy: float, max_energy: float)
signal weapon_changed(item_id: String)
signal died
signal message(text: String)

const PROJECTILE := preload("res://scenes/actors/projectile.tscn")

var base_stats: Dictionary = {}
var stats: Dictionary = {}
var hp := 100.0
var energy := 100.0
var weapons: Array = []
var weapon_index := 0
var abilities: Array = []
var consumables: Array = []
var protected_hazards: Array = []
var interact_time := 2.0
## Hàm trả về số lượng vật phẩm còn lại & tiêu thụ: được MissionLevel gán.
var count_item: Callable
var consume_item: Callable

var _cooldowns: Dictionary = {}
var _buffs: Array = []  # [{mods, time_left}]
var _fire_timer := 0.0
var _dash_timer := 0.0
var _dash_left := 0.0
var _dash_dir := Vector2.ZERO
var _invuln := 0.0
var _dead := false
var _aim := Vector2.RIGHT
var _hurt_flash := 0.0
var _sprite_id := "survivor"
var _tint := Color.WHITE
var _muzzle_time := 0.0

@onready var body: Sprite2D = $Body
@onready var muzzle: Sprite2D = $Body/Muzzle
@onready var flashlight: PointLight2D = $Flashlight


func setup(leader: String, team: Array, loadout: Dictionary, hazards_protected: Array) -> void:
	var character := Content.get_entry("characters", leader)
	_sprite_id = character.get("sprite", "survivor")
	_tint = Color(character.get("tint", "#FFFFFF"))
	base_stats = CombatStats.compute(Game, leader, team)
	stats = base_stats.duplicate()
	hp = stats.max_hp
	energy = stats.max_energy
	weapons = loadout.get("weapons", []).duplicate()
	consumables = loadout.get("consumables", []).duplicate()
	abilities = Abilities.for_leader(Game, leader)
	protected_hazards = hazards_protected
	var cfg: Dictionary = Content.config.get("player", {})
	interact_time = maxf(0.4, float(cfg.get("interact_time", 2.0)) - CrewSystem.skill(Game, leader, "engineering") * float(cfg.get("interact_reduction_per_engineering", 0.15)))
	hp_changed.emit(hp, stats.max_hp)
	energy_changed.emit(energy, stats.max_energy)
	weapon_changed.emit(current_weapon())
	_update_sprite()


func _update_sprite() -> void:
	var pose: String = weapon_data().get("pose", "gun")
	var path := "res://assets/characters/%s_%s.png" % [_sprite_id, pose]
	if not ResourceLoader.exists(path):
		path = "res://assets/characters/%s_gun.png" % _sprite_id
	body.texture = load(path)
	body.modulate = _tint


func current_weapon() -> String:
	return weapons[weapon_index] if not weapons.is_empty() else ""


func weapon_data() -> Dictionary:
	return Content.get_entry("items", current_weapon()).get("weapon", {})


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_tick_timers(delta)
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_just_pressed("dash") and _dash_timer <= 0.0 and dir != Vector2.ZERO:
		var cfg: Dictionary = Content.config.get("player", {})
		_dash_dir = dir
		_dash_left = float(cfg.get("dash_time", 0.16))
		_dash_timer = stats.dash_cooldown
		_invuln = maxf(_invuln, _dash_left)
		Sfx.play("dash")
	if _dash_left > 0.0:
		velocity = _dash_dir * float(Content.config.player.get("dash_speed", 720))
	else:
		velocity = dir * stats.move_speed
	move_and_slide()

	_aim = (get_global_mouse_position() - global_position).normalized()
	if _aim == Vector2.ZERO:
		_aim = Vector2.RIGHT
	body.rotation = _aim.angle()
	flashlight.rotation = _aim.angle()
	if Input.is_action_pressed("fire") and _fire_timer <= 0.0 and current_weapon() != "":
		_shoot()
	if Input.is_action_just_pressed("weapon_next"):
		switch_weapon(weapon_index + 1)
	if Input.is_action_just_pressed("weapon_prev"):
		switch_weapon(weapon_index - 1)
	for i in weapons.size():
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			switch_weapon(i)
	for i in mini(abilities.size(), 2):
		if Input.is_action_just_pressed("ability_%d" % (i + 1)):
			use_ability(abilities[i])
	for i in mini(consumables.size(), 2):
		if Input.is_action_just_pressed("item_%d" % (i + 1)):
			use_consumable(consumables[i])


func _tick_timers(delta: float) -> void:
	_fire_timer -= delta
	_dash_timer -= delta
	_dash_left -= delta
	_invuln -= delta
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	_muzzle_time -= delta
	muzzle.visible = _muzzle_time > 0.0
	body.modulate = Color(3, 1.2, 1.2) if _hurt_flash > 0.0 else (Color(_tint, 0.55) if _dash_left > 0.0 else _tint)
	for id in _cooldowns.keys():
		_cooldowns[id] = maxf(0.0, _cooldowns[id] - delta)
	var buffs_changed := false
	for buff in _buffs.duplicate():
		buff.time_left -= delta
		if buff.time_left <= 0.0:
			_buffs.erase(buff)
			buffs_changed = true
	if buffs_changed:
		_recompute_stats()
	energy = minf(stats.max_energy, energy + stats.energy_regen * delta)
	energy_changed.emit(energy, stats.max_energy)


func _shoot() -> void:
	var w := weapon_data()
	_fire_timer = float(w.get("fire_interval", 0.25)) / maxf(0.1, stats.fire_rate_mult)
	var pellets := int(w.get("pellets", 1))
	var spread := float(w.get("spread", 0.0))
	var speed := float(w.get("projectile_speed", 700))
	var projectile_texture: String = w.get("projectile", "laser_blue")
	Sfx.play(w.get("sound", "shoot"), 0.1, -4.0)
	_muzzle_time = 0.05
	for i in pellets:
		var angle := randf_range(-spread, spread) * 0.5 if pellets == 1 else lerpf(-spread, spread, float(i) / (pellets - 1)) * 0.5
		var dir := _aim.rotated(angle)
		var dmg: float = float(w.get("damage", 10)) * stats.damage_mult
		var crit: bool = randf() < stats.crit_chance + float(w.get("crit_bonus", 0.0))
		if crit:
			dmg *= stats.crit_mult
		var p := PROJECTILE.instantiate()
		p.setup(global_position + dir * 30.0, dir * speed, dmg, "enemies", Color(w.get("color", "#00E5FF")))
		p.texture_name = projectile_texture
		p.crit = crit
		p.pierce = int(w.get("pierce", 0))
		p.lifetime = float(w.get("range", 600)) / speed
		p.mining_damage = dmg * float(w.get("mining_mult", 0.5)) * stats.mining_power
		get_parent().add_child(p)


func switch_weapon(index: int) -> void:
	if weapons.size() <= 1:
		return
	weapon_index = posmod(index, weapons.size())
	_fire_timer = 0.15
	weapon_changed.emit(current_weapon())
	_update_sprite()


func cooldown_left(ability_id: String) -> float:
	return _cooldowns.get(ability_id, 0.0)


func use_ability(ability_id: String) -> void:
	var a := Content.get_entry("abilities", ability_id)
	if a.is_empty() or cooldown_left(ability_id) > 0.0:
		return
	if energy < float(a.get("energy", 0)):
		message.emit("Không đủ năng lượng")
		return
	energy -= float(a.get("energy", 0))
	Sfx.play("ability")
	_cooldowns[ability_id] = float(a.get("cooldown", 10))
	match a.get("type", ""):
		"heal":
			heal(float(a.get("amount", 30)))
		"slow_enemies":
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if global_position.distance_to(enemy.global_position) < 700.0:
					enemy.apply_slow(float(a.get("factor", 0.4)), float(a.get("duration", 5)))
		"time_slow":
			Engine.time_scale = float(a.get("time_scale", 0.4))
			# Timer bỏ qua time_scale để hiệu lực tính theo giây thật
			get_tree().create_timer(float(a.get("duration", 4)), true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
		"aoe":
			var target := global_position + (get_global_mouse_position() - global_position).limit_length(float(a.get("range", 400)))
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if enemy.global_position.distance_to(target) <= float(a.get("radius", 120)):
					enemy.take_damage(float(a.get("damage", 50)) * stats.damage_mult)
			get_parent().add_child(Explosion.create(target, float(a.get("radius", 120)), Color("#FFC94D")))
		"buff":
			add_buff(a.get("buff", {}), float(a.get("duration", 5)))
	message.emit(a.get("name", ability_id))


func use_consumable(item_id: String) -> void:
	if count_item.is_null() or count_item.call(item_id) <= 0:
		message.emit("Hết " + Content.get_entry("items", item_id).get("name", item_id))
		return
	var use: Dictionary = Content.get_entry("items", item_id).get("use", {})
	consume_item.call(item_id)
	if use.has("heal"):
		heal(float(use.heal))
	if use.has("energy"):
		energy = minf(stats.max_energy, energy + float(use.energy))
	if use.has("buff"):
		add_buff(use.buff, float(use.get("duration", 5)))
	message.emit("Dùng " + Content.get_entry("items", item_id).get("name", item_id))


func add_buff(mods: Dictionary, duration: float) -> void:
	_buffs.append({"mods": mods, "time_left": duration})
	_recompute_stats()


func _recompute_stats() -> void:
	stats = base_stats.duplicate()
	for buff in _buffs:
		for stat in buff.mods:
			stats[stat] = float(stats.get(stat, 0.0)) + float(buff.mods[stat])
	stats = CombatStats.clamp_stats(stats)


func take_damage(amount: float) -> void:
	if _dead or _invuln > 0.0:
		return
	# Giáp giảm sát thương theo tỉ lệ 100 / (100 + giáp)
	hp = maxf(0.0, hp - amount * 100.0 / (100.0 + maxf(0.0, stats.armor)))
	_invuln = float(Content.config.get("player", {}).get("hurt_invuln", 0.35))
	_hurt_flash = 0.15
	Sfx.play("hurt")
	hp_changed.emit(hp, stats.max_hp)
	if hp <= 0.0:
		_dead = true
		died.emit()


## Sát thương môi trường: bỏ qua thời gian bất tử sau khi trúng đòn và giáp.
func take_hazard_damage(amount: float) -> void:
	if _dead:
		return
	hp = maxf(0.0, hp - amount)
	hp_changed.emit(hp, stats.max_hp)
	if hp <= 0.0:
		_dead = true
		died.emit()


func heal(amount: float) -> void:
	hp = minf(stats.max_hp, hp + amount)
	hp_changed.emit(hp, stats.max_hp)


func is_protected(hazard: String) -> bool:
	return hazard in protected_hazards
