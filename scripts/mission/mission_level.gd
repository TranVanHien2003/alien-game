extends Node2D
## Màn khai phá của một nhiệm vụ. Người chơi là chỉ huy, ra lệnh cho đội (SquadController).
## Luồng: đổ bộ -> khám phá / chiến đấu / khai thác / làm mục tiêu -> rút lui về tàu con thoi.
##   - Giới hạn thời gian (missions[].time_limit): hết giờ thì tự động rút lui với đồng hồ đếm ngược.
##   - Quái kéo đến theo đợt (levels[].waves), mạnh dần theo thời gian và độ khó.
##   - Ai gục mà không được cứu, hoặc không về kịp tàu khi rút lui -> mất tích (sinh nhiệm vụ Giải cứu).
##
## Chạy thẳng scene này (F6) để test: script tự tạo ván mới và chọn nhiệm vụ đầu tiên.

const UNIT := preload("res://scenes/actors/unit.tscn")
const ENEMY := preload("res://scenes/actors/enemy.tscn")
const RESOURCE_NODE := preload("res://scenes/actors/resource_node.tscn")
const PICKUP := preload("res://scenes/actors/pickup.tscn")
const OBJECTIVE := preload("res://scenes/actors/objective.tscn")
const HAZARD := preload("res://scenes/actors/hazard_zone.tscn")
const EXIT := preload("res://scenes/actors/exit_zone.tscn")
const HUB_SCENE := "res://scenes/hub/hub.tscn"

@onready var world: Node2D = $World
@onready var hud: MissionHud = $HUD

var entry: Dictionary
var mission: Dictionary
var objective: Dictionary
var params: Dictionary
var location: Dictionary
var difficulty := 1.0
var rng := RandomNumberGenerator.new()
var gen: LevelGenerator
var map: LevelMap
var camera: Camera2D
var controller: SquadController
var pathgrid: PathGrid
var autopilot: AutoPilot
var exit_zone: ExitZone
var units: Array = []
var run_loot: Dictionary = {}
var run_research := 0.0
var progress := 0
var goal := 1
var elapsed := 0.0
var time_limit := 0.0
var evac_active := false
var evac_left := 0.0
var wave_index := 0
var next_wave := 0.0
var _revealed_until := 0.0
var game_speed := 1.0
var _finished := false
## Người lạ gia nhập trong màn (chờ quyết định thu nhận) & ghi chú kỳ ngộ
var guests: Array = []
var relic_texts: Array = []
var growth_texts: Dictionary = {}


func _ready() -> void:
	if Game.action_mission.is_empty():
		_debug_setup()
	entry = Game.action_mission
	mission = Content.get_entry("missions", entry.mission)
	objective = mission.get("objective", {})
	location = Content.get_entry("locations", entry.location)
	difficulty = float(entry.get("difficulty", 1.0))
	params = Content.get_entry("levels", location.get("type", ""))
	if params.is_empty():
		params = Content.get_entry("levels", "default")
	goal = int(objective.get("count", 1))
	time_limit = float(mission.get("time_limit", 480))
	var waves: Dictionary = params.get("waves", {})
	next_wave = float(waves.get("first", 60))
	rng.seed = Game.rng.randi()

	var outdoor: bool = params.get("layout", "interior") == "terrain"
	gen = TerrainGenerator.generate(rng, params) if outdoor else LevelGenerator.generate(rng, params)
	world.y_sort_enabled = true
	map = LevelMap.new()
	add_child(map)
	move_child(map, 0)
	map.build(gen, params, rng, world)
	pathgrid = PathGrid.new()
	pathgrid.setup(gen, map.cell_size)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 10.0
	camera.zoom = Vector2.ONE * (0.42 if outdoor else 0.85)
	add_child(camera)

	_spawn_exit()
	_spawn_squad()
	_spawn_resource_nodes()
	_spawn_enemies()
	_spawn_hazards()
	_spawn_caches()
	_spawn_extras()
	_spawn_objectives()

	controller = SquadController.new()
	world.add_child(controller)
	controller.setup(self, camera, units, map.world_size())
	autopilot = AutoPilot.new()
	add_child(autopilot)
	autopilot.setup(self)
	camera.global_position = exit_zone.global_position

	hud.setup(self)
	hud.resume_pressed.connect(_toggle_pause)
	hud.abort_pressed.connect(_abort)
	hud.return_pressed.connect(func(): get_tree().change_scene_to_file(HUB_SCENE))
	_update_objective()


func _debug_setup() -> void:
	if Game.crew.is_empty():
		Game.new_game(1)
		Game.pending_event = ""
	for option in MissionSystem.available(Game):
		if option.mission.get("auto_only", false):
			continue
		var free := CrewSystem.available(Game)
		var size := mini(free.size(), int(option.mission.team_size[1]))
		if size >= int(option.mission.team_size[0]) and MissionSystem.start_action(Game, option, free.slice(0, size)):
			return


# --- Sinh màn -----------------------------------------------------------------------

func _random_room(exclude_spawn: bool = true) -> int:
	return rng.randi_range(1 if exclude_spawn and gen.rooms.size() > 1 else 0, gen.rooms.size() - 1)


func _spawn_exit() -> void:
	exit_zone = EXIT.instantiate()
	exit_zone.position = map.cell_to_world(gen.room_center(0))
	world.add_child(exit_zone)


func _protected_hazards() -> Array:
	var protected := []
	for hazard in location.get("hazards", []):
		if MissionSystem.is_protected(Game, hazard, entry.team):
			protected.append(hazard)
	return protected


func _spawn_squad() -> void:
	for i in entry.team.size():
		_make_unit(entry.team[i], exit_zone.position + Vector2.from_angle(TAU * i / entry.team.size()) * 70.0)


func _make_unit(char_id: String, pos: Vector2) -> Unit:
	var unit: Unit = UNIT.instantiate()
	unit.position = pos
	world.add_child(unit)
	unit.setup(char_id, self, _protected_hazards())
	# Ngoài trời ban ngày không cần đèn tầm nhìn
	unit.sight_light.visible = not map.outdoor
	unit.downed.connect(func(u): hud.show_message("⚠ %s bị hạ gục! Ra lệnh cứu (chuột phải vào người đó)." % u.display_name()))
	unit.lost.connect(_on_unit_lost)
	units.append(unit)
	return unit


## Người được cứu / người lạ gia nhập đội ngay trên bản đồ.
func _join_unit(char_id: String, pos: Vector2, guest: bool) -> void:
	var unit := _make_unit(char_id, pos)
	unit.guest = guest
	unit.hp = unit.stats.max_hp * 0.4
	if hud.has_method("add_unit_card"):
		hud.add_unit_card(unit)
	hud.show_message("%s gia nhập đội! Đưa họ về tàu con thoi." % unit.display_name())
	Sfx.play("pickup")


## Kỳ ngộ (cổ vật) và người sống sót lạ rải ngẫu nhiên trên bản đồ.
func _spawn_extras() -> void:
	var cfg: Dictionary = Content.config.get("lifecycle", {})
	for i in int(params.get("relics", 0)):
		if rng.randf() > float(cfg.get("mission_relic_chance", 0.5)):
			continue
		var relic: Objective = OBJECTIVE.instantiate()
		relic.setup("relic", "Cổ vật", map.accent)
		relic.position = map.cell_to_world(gen.random_cell_in_room(rng, _random_room()))
		relic.completed.connect(_on_relic)
		world.add_child(relic)
	for i in int(params.get("strangers", 0)):
		if rng.randf() > float(cfg.get("stranger_chance", 0.5)):
			continue
		var survivor: Objective = OBJECTIVE.instantiate()
		var gender_sprite := "survivor" if rng.randf() < 0.5 else "man_brown"
		survivor.setup("stranger", "Người sống sót", map.accent, "res://assets/characters/%s_stand.png" % gender_sprite)
		survivor.position = map.cell_to_world(gen.random_cell_in_room(rng, _random_room()))
		survivor.completed.connect(_on_stranger)
		world.add_child(survivor)


func _on_relic(obj: Objective) -> void:
	if not obj.finisher is Unit:
		return
	var unit: Unit = obj.finisher
	var text := Lifecycle.resolve_encounter(Game, unit.char_id, "enc_relic")
	unit.refresh_stats()
	relic_texts.append(text)
	hud.show_message("✦ " + text)


func _on_stranger(obj: Objective) -> void:
	var person := CharacterFactory.stranger(Game, rng, location.get("name", ""))
	CrewSystem.add_member(Game, person.id)
	Game.crew[person.id].guest = true
	Game.crew[person.id].status = CrewSystem.MISSION
	Roles.auto_equip(Game, person.id)
	guests.append(person.id)
	_join_unit(person.id, obj.global_position, true)


func _scaled(count: float, kind: String) -> int:
	return int(round(count * Difficulty.scale(kind, difficulty)))


func _spawn_resource_nodes() -> void:
	var nodes: Dictionary = params.get("resource_nodes", {}).duplicate()
	# Nhiệm vụ khai thác: đảm bảo đủ mỏ chứa đúng loại nguyên liệu cần
	if objective.get("type", "") == "mine":
		for node in Content.all("resource_nodes"):
			if node.get("drops", {}).has(objective.item):
				var per_node := float(node.drops[objective.item][0])
				nodes[node.id] = maxi(int(nodes.get(node.id, 0)), ceili(goal / per_node) + 4)
				break
	for node_id in nodes:
		for i in _scaled(float(nodes[node_id]), "reward"):
			var node: ResourceNode = RESOURCE_NODE.instantiate()
			node.position = map.cell_to_world(gen.random_cell_in_room(rng, _random_room()))
			node.setup(node_id)
			node.depleted.connect(_on_node_depleted)
			world.add_child(node)
			pathgrid.set_obstacle(node.position, true)


## Quái đứng theo bầy (levels[].pack_size) tại các điểm khám phá, tránh xa bãi đáp.
func _spawn_enemies() -> void:
	var pack := maxi(1, int(params.get("pack_size", 1)))
	var far := gen.rooms_by_distance_desc()
	var safe_rooms: Array = far.slice(0, maxi(1, far.size() - 2)) if far.size() > 2 else far
	for enemy_id in params.get("enemies", {}):
		var total := _scaled(float(params.enemies[enemy_id]), "enemy_count")
		var room := 0
		for i in total:
			if i % pack == 0:
				room = safe_rooms[rng.randi() % safe_rooms.size()] if not safe_rooms.is_empty() else _random_room()
			spawn_enemy(enemy_id, map.cell_to_world(gen.random_cell_in_room(rng, room)))


func spawn_enemy(enemy_id: String, pos: Vector2) -> Enemy:
	var enemy: Enemy = ENEMY.instantiate()
	enemy.position = pos
	world.add_child(enemy)
	enemy.setup(enemy_id, difficulty)
	enemy.mover.grid = pathgrid
	enemy.died.connect(_on_enemy_died)
	enemy.summon_requested.connect(func(id, p): spawn_enemy(id, p))
	return enemy


func _spawn_hazards() -> void:
	var hazards: Array = location.get("hazards", [])
	if hazards.is_empty():
		return
	var dps := float(Content.config.get("player", {}).get("hazard_dps", 8)) * Difficulty.scale("enemy_damage", difficulty)
	for i in int(params.get("hazard_zones", 0)):
		var room := gen.rooms[_random_room()]
		var zone: HazardZone = HAZARD.instantiate()
		zone.setup(hazards[rng.randi() % hazards.size()], Vector2(room.size) * map.cell_size * 0.8, dps)
		zone.position = (Vector2(room.position) + Vector2(room.size) / 2.0) * map.cell_size
		world.add_child(zone)


func _spawn_caches() -> void:
	for i in _scaled(float(params.get("caches", 0)), "reward"):
		var cache: Objective = OBJECTIVE.instantiate()
		cache.setup("cache", "Tủ tiếp tế", map.accent)
		cache.position = map.cell_to_world(gen.random_cell_in_room(rng, _random_room()))
		cache.completed.connect(func(c): _drop_loot(Loot.roll(rng, "lt_cache"), c.global_position))
		world.add_child(cache)


func _spawn_objectives() -> void:
	var far_rooms := gen.rooms_by_distance_desc()
	match objective.get("type", ""):
		"collect", "interact", "rescue":
			for i in goal:
				var obj: Objective = OBJECTIVE.instantiate()
				var sprite := ""
				if objective.type == "rescue" and entry.target != "":
					sprite = "res://assets/characters/%s_stand.png" % Content.get_entry("characters", entry.target).get("sprite", "survivor")
				obj.setup(objective.type, objective.get("label", ""), map.accent, sprite)
				# Rải mục tiêu ở nửa xa của bản đồ để buộc phải khám phá
				var room: int = far_rooms[(i * 2) % maxi(1, far_rooms.size() / 2 + 1)] if not far_rooms.is_empty() else 0
				obj.position = map.cell_to_world(gen.random_cell_in_room(rng, room))
				obj.completed.connect(func(o):
					_add_progress(1)
					if objective.type == "rescue" and entry.target != "":
						_join_unit(entry.target, o.global_position, false))
				world.add_child(obj)
		"boss":
			var boss := spawn_enemy(objective.boss, map.cell_to_world(gen.room_center(far_rooms[0] if not far_rooms.is_empty() else 0)))
			hud.call_deferred("track_boss", boss)


# --- Kỹ năng gọi từ Unit ------------------------------------------------------------------

func spawn_turret(pos: Vector2, ability: Dictionary, power: float) -> void:
	var turret := AllyTurret.new()
	turret.position = pos
	turret.collision_layer = 0
	turret.setup(ability, power)
	world.add_child(turret)


func spawn_flare(pos: Vector2, radius: float, duration: float) -> void:
	var flare := PointLight2D.new()
	flare.texture = preload("res://assets/fx/light.png")
	flare.texture_scale = radius / 128.0
	flare.color = Color("#FFE0B0")
	flare.energy = 1.0
	flare.position = pos
	add_child(flare)
	world.add_child(Explosion.create(pos, 60.0, Color("#FFE0B0"), "spark"))
	var tween := create_tween()
	tween.tween_interval(duration * 0.7)
	tween.tween_property(flare, "energy", 0.0, duration * 0.3)
	tween.tween_callback(flare.queue_free)


func reveal(duration: float) -> void:
	_revealed_until = elapsed + duration
	hud.show_message("Quét địa hình: hiện toàn bộ quái và mỏ trên minimap")


func is_revealed() -> bool:
	return elapsed < _revealed_until


func use_consumable(unit: Unit, slot: int) -> void:
	var list: Array = Game.loadout.get("consumables", [])
	if slot >= list.size() or not unit.is_active():
		return
	var item_id: String = list[slot]
	if item_count(item_id) <= 0:
		hud.show_message("Hết " + Content.get_entry("items", item_id).get("name", item_id))
		return
	if int(run_loot.get(item_id, 0)) > 0:
		run_loot[item_id] -= 1
		if run_loot[item_id] <= 0:
			run_loot.erase(item_id)
	else:
		Game.add_item(item_id, -1)
	unit.apply_consumable(Content.get_entry("items", item_id).get("use", {}))
	Sfx.play("pickup")
	hud.show_message("%s dùng %s" % [unit.display_name(), Content.get_entry("items", item_id).get("name", "")])


func item_count(item_id: String) -> int:
	return Game.item_count(item_id) + int(run_loot.get(item_id, 0))


# --- Tiến trình -----------------------------------------------------------------------

func _on_enemy_died(enemy: Enemy) -> void:
	if enemy.data.has("loot"):
		for i in maxi(1, _scaled(1.0, "reward")):
			_drop_loot(Loot.roll(rng, enemy.data.loot), enemy.global_position)
	if enemy.is_boss and objective.get("type", "") == "boss" and enemy.enemy_id == objective.boss:
		_add_progress(1)
		hud.show_message("%s đã bị hạ!" % enemy.data.get("name", ""))


func _on_node_depleted(node: ResourceNode, by: Node) -> void:
	pathgrid.set_obstacle(node.global_position, false)
	_drop_loot(Loot.roll_drops(rng, node.data.get("drops", {})), node.global_position)
	if node.data.has("loot"):
		_drop_loot(Loot.roll(rng, node.data.loot), node.global_position)
	# Nhà khoa học / máy quét phân tích vật chất lạ -> điểm nghiên cứu
	if node.node_id in ["crystal_vein", "xeno_pod"] and units.any(func(u): return u.is_active() and u.tool_data().get("type", "") == "scanner"):
		run_research += 2.0


func _drop_loot(loot: Dictionary, pos: Vector2) -> void:
	for item_id in loot:
		if int(loot[item_id]) <= 0:
			continue
		var pickup: Pickup = PICKUP.instantiate()
		pickup.position = pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, 26.0)
		pickup.setup(item_id, int(loot[item_id]))
		pickup.picked.connect(_on_picked)
		world.call_deferred("add_child", pickup)


func _on_picked(item_id: String, count: int) -> void:
	run_loot[item_id] = int(run_loot.get(item_id, 0)) + count
	hud.show_message("+%d %s" % [count, Content.get_entry("items", item_id).get("name", item_id)])
	if objective.get("type", "") == "mine" and item_id == objective.item:
		_add_progress(count)
	hud.update_loot(run_loot)


func _add_progress(amount: int) -> void:
	progress = mini(goal, progress + amount)
	_update_objective()
	if objective_done():
		exit_zone.unlocked = true
		hud.show_message("Mục tiêu hoàn thành! Nhấn B (Rút lui) để đưa đội về tàu con thoi.")


func objective_done() -> bool:
	return progress >= goal


func _update_objective() -> void:
	hud.set_objective("%s: %d/%d" % [objective.get("label", "Mục tiêu"), progress, goal], objective_done())


func _on_unit_lost(unit: Unit) -> void:
	hud.show_message("✝ Mất liên lạc với %s." % unit.display_name())


func active_units() -> Array:
	return units.filter(func(u): return u.is_active())


# --- Thời gian, đợt quái, rút lui ------------------------------------------------------------

func _process(delta: float) -> void:
	if _finished:
		return
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()
	if get_tree().paused:
		return
	elapsed += delta
	if not evac_active and elapsed >= time_limit:
		hud.show_message("⚠ Hết thời gian! Tàu con thoi buộc phải cất cánh.")
		call_evac()
	if elapsed >= next_wave and not evac_active:
		_spawn_wave()
	if active_units().is_empty():
		# Cả đội gục / mất liên lạc: không ai mang được gì về
		_finish(false, false)
		return
	if evac_active:
		evac_left -= delta
		var outside := active_units().filter(func(u): return not u in exit_zone.units_inside())
		if outside.is_empty() or evac_left <= 0.0:
			_finish(objective_done(), true)


func _spawn_wave() -> void:
	var waves: Dictionary = params.get("waves", {})
	wave_index += 1
	next_wave = elapsed + float(waves.get("interval", 60))
	var far_rooms := gen.rooms_by_distance_desc()
	if far_rooms.is_empty():
		return
	var room: int = far_rooms[rng.randi() % maxi(1, far_rooms.size() / 2)]
	var growth := int(waves.get("growth", 1)) * (wave_index - 1)
	var count := 0
	for enemy_id in waves.get("enemies", {}):
		for i in _scaled(float(waves.enemies[enemy_id]) + growth, "wave_size"):
			var enemy := spawn_enemy(enemy_id, map.cell_to_world(gen.random_cell_in_room(rng, room)))
			enemy._awake = true
			count += 1
	hud.show_message("⚠ Đợt quái thứ %d (%d con) đang kéo đến!" % [wave_index, count])


func call_evac() -> void:
	if evac_active or _finished:
		return
	evac_active = true
	evac_left = float(Content.config.get("squad", {}).get("evac_countdown", 25))
	var group := active_units()
	for i in group.size():
		group[i].command({"type": "evac", "pos": exit_zone.global_position + Vector2.from_angle(TAU * i / maxf(1, group.size())) * 50.0})
	hud.show_message("RÚT LUI! Mọi người về tàu con thoi trong %d giây." % roundi(evac_left))


## Tốc độ trò chơi (×0.5 / ×1 / ×2). Tạm dừng dùng Esc.
func set_speed(speed: float) -> void:
	game_speed = speed
	Engine.time_scale = speed
	hud.show_message("Tốc độ ×%s" % str(speed))


func seconds_left() -> float:
	return maxf(0.0, time_limit - elapsed)


func next_wave_in() -> float:
	return maxf(0.0, next_wave - elapsed)


func _toggle_pause() -> void:
	if _finished:
		return
	get_tree().paused = not get_tree().paused
	hud.show_pause(get_tree().paused)


func _abort() -> void:
	# Bỏ nhiệm vụ: tàu con thoi đón ngay những ai còn đứng được, không mang đồ về
	for u in active_units():
		u.state = Unit.State.EVACUATED
	run_loot = {}
	_finish(false, false)


## evacuated: true nếu kết thúc bằng rút lui (người trong vùng tàu con thoi được đón).
func _finish(success: bool, evacuated: bool) -> void:
	if _finished:
		return
	_finished = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	var aboard := []
	var missing := []
	for u in units:
		var safe: bool = u.state == Unit.State.EVACUATED or (evacuated and u.is_active() and u in exit_zone.units_inside())
		if safe:
			aboard.append(u.char_id)
			# Khám phá -> tăng thuộc tính, XP, tài năng
			if Game.crew.has(u.char_id):
				growth_texts[u.char_id] = AttributeSystem.apply_mission_growth(Game, u.char_id, u.counters, success)
		elif u.char_id in entry.team:
			missing.append(u.char_id)
		u.set_physics_process(false)
	# Người mất tích đã được đưa về tàu
	if entry.target != "" and entry.target in aboard:
		CrewSystem.rescue(Game, entry.target)
	# Người lạ bị bỏ lại -> không còn nữa
	for guest_id in guests.duplicate():
		if not guest_id in aboard:
			_release_guest(guest_id)
	var keep_loot := not aboard.is_empty()
	if keep_loot:
		Loot.give(Game, run_loot)
		if success and run_research > 0.0:
			ResearchSystem.add_points(Game, run_research)
	var report := MissionSystem.finish_action(Game, success, missing)
	SaveManager.save_game()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	hud.show_result(report, run_loot if keep_loot else {}, aboard)
	if hud.has_method("show_growth"):
		hud.show_growth(growth_texts, relic_texts, guests.filter(func(g): return g in aboard))


## Quyết định với người lạ sau màn: thu nhận vào phi hành đoàn hay để họ đi.
func decide_recruit(char_id: String, accept: bool) -> void:
	if not char_id in guests:
		return
	if accept:
		Game.crew[char_id].guest = false
		Game.crew[char_id].status = CrewSystem.IDLE
		Roles.auto_equip(Game, char_id)
		Game.add_log("🤝 %s gia nhập phi hành đoàn Âu Cơ." % CrewSystem.display_name(char_id))
		guests.erase(char_id)
	else:
		Game.add_log("%s được tiếp tế và tiễn đi tại %s." % [CrewSystem.display_name(char_id), location.get("name", "")])
		_release_guest(char_id)
	SaveManager.save_game()


func _release_guest(char_id: String) -> void:
	Game.crew.erase(char_id)
	CharacterFactory.unregister(Game, char_id)
	guests.erase(char_id)
