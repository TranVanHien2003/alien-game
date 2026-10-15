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
var _finished := false


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

	gen = LevelGenerator.generate(rng, params)
	world.y_sort_enabled = true
	map = LevelMap.new()
	add_child(map)
	move_child(map, 0)
	map.build(gen, params, rng, world)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 10.0
	add_child(camera)

	_spawn_exit()
	_spawn_squad()
	_spawn_resource_nodes()
	_spawn_enemies()
	_spawn_hazards()
	_spawn_caches()
	_spawn_objectives()

	controller = SquadController.new()
	world.add_child(controller)
	controller.setup(self, camera, units, map.world_size())
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


func _spawn_squad() -> void:
	var protected := []
	for hazard in location.get("hazards", []):
		if MissionSystem.is_protected(Game, hazard, entry.team):
			protected.append(hazard)
	for i in entry.team.size():
		var unit: Unit = UNIT.instantiate()
		unit.position = exit_zone.position + Vector2.from_angle(TAU * i / entry.team.size()) * 70.0
		world.add_child(unit)
		unit.setup(entry.team[i], self, protected)
		unit.downed.connect(func(u): hud.show_message("⚠ %s bị hạ gục! Ra lệnh cứu (chuột phải vào người đó)." % u.display_name()))
		unit.lost.connect(_on_unit_lost)
		units.append(unit)


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


func _spawn_enemies() -> void:
	for enemy_id in params.get("enemies", {}):
		for i in _scaled(float(params.enemies[enemy_id]), "enemy_count"):
			spawn_enemy(enemy_id, map.cell_to_world(gen.random_cell_in_room(rng, _random_room())))


func spawn_enemy(enemy_id: String, pos: Vector2) -> Enemy:
	var enemy: Enemy = ENEMY.instantiate()
	enemy.position = pos
	world.add_child(enemy)
	enemy.setup(enemy_id, difficulty)
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
				obj.completed.connect(func(_o): _add_progress(1))
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
		else:
			missing.append(u.char_id)
		u.set_physics_process(false)
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
