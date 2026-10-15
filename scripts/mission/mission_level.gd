extends Node2D
## Màn action của một nhiệm vụ. Đọc Game.action_mission, sinh bản đồ, quái, mỏ, mục tiêu.
## Kết thúc khi: về tàu con thoi (thành công nếu xong mục tiêu, rút lui nếu chưa),
## đội trưởng gục (mất đồ đã nhặt, có thể mất tích), hoặc bỏ nhiệm vụ từ menu tạm dừng.
##
## Chạy thẳng scene này (F6) để test: script tự tạo ván mới và chọn nhiệm vụ đầu tiên.

const CELL := 40.0
const PLAYER := preload("res://scenes/actors/player.tscn")
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
var rng := RandomNumberGenerator.new()
var gen: LevelGenerator
var map: LevelMap
var player: Player
var exit_zone: ExitZone
var run_loot: Dictionary = {}
var progress := 0
var goal := 1
var _in_exit := false
## Người chơi xuất phát trong vùng tàu con thoi: chỉ cho rút lui sau khi đã rời khỏi đó một lần
var _left_spawn := false
var _finished := false


func _ready() -> void:
	if Game.action_mission.is_empty():
		_debug_setup()
	entry = Game.action_mission
	mission = Content.get_entry("missions", entry.mission)
	objective = mission.get("objective", {})
	goal = int(objective.get("count", 1))
	var location := Content.get_entry("locations", entry.location)
	var params := Content.get_entry("levels", location.get("type", ""))
	if params.is_empty():
		params = Content.get_entry("levels", "default")
	rng.seed = Game.rng.randi()

	gen = LevelGenerator.generate(rng, params)
	map = LevelMap.new()
	world.add_child(map)
	map.build(gen, params, CELL)

	_spawn_player(location)
	_spawn_resource_nodes(params)
	_spawn_enemies(params)
	_spawn_hazards(params, location)
	_spawn_objectives()

	hud.setup(self, player, mission, entry)
	hud.resume_pressed.connect(_toggle_pause)
	hud.abort_pressed.connect(func(): _finish(false, false, false))
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
		var size := int(option.mission.team_size[0])
		if free.size() >= size and MissionSystem.start_action(Game, option, free.slice(0, size), free[0]):
			return


# --- Sinh màn -------------------------------------------------------------------

func _spawn_player(location: Dictionary) -> void:
	var protected := []
	for hazard in location.get("hazards", []):
		if MissionSystem.is_protected(Game, hazard, entry.team):
			protected.append(hazard)
	player = PLAYER.instantiate()
	player.position = map.cell_to_world(gen.room_center(0))
	world.add_child(player)
	player.count_item = func(id): return Game.item_count(id) + int(run_loot.get(id, 0))
	player.consume_item = _consume_item
	player.setup(entry.leader, entry.team, Game.loadout, protected)
	player.died.connect(func(): _finish(false, true, false))

	exit_zone = EXIT.instantiate()
	exit_zone.position = player.position
	world.add_child(exit_zone)
	exit_zone.body_entered.connect(func(b): if b == player: _on_exit_entered())
	exit_zone.body_exited.connect(_on_exit_left)


func _spawn_resource_nodes(params: Dictionary) -> void:
	var nodes: Dictionary = params.get("resource_nodes", {}).duplicate()
	# Nhiệm vụ khai thác: đảm bảo đủ mỏ chứa đúng loại nguyên liệu cần
	if objective.get("type", "") == "mine":
		for node in Content.all("resource_nodes"):
			if node.get("drops", {}).has(objective.item):
				var per_node := float(node.drops[objective.item][0])
				nodes[node.id] = maxi(int(nodes.get(node.id, 0)), ceili(goal / per_node) + 2)
				break
	for node_id in nodes:
		for i in int(nodes[node_id]):
			var node: ResourceNode = RESOURCE_NODE.instantiate()
			node.position = map.cell_to_world(gen.random_cell_in_room(rng, rng.randi_range(1, gen.rooms.size() - 1)))
			node.setup(node_id)
			node.depleted.connect(_on_node_depleted)
			world.add_child(node)


func _spawn_enemies(params: Dictionary) -> void:
	var bonus := Game.year / 5
	for enemy_id in params.get("enemies", {}):
		for i in int(params.enemies[enemy_id]) + bonus:
			spawn_enemy(enemy_id, map.cell_to_world(gen.random_cell_in_room(rng, rng.randi_range(1, gen.rooms.size() - 1))))


func spawn_enemy(enemy_id: String, pos: Vector2) -> Enemy:
	var enemy: Enemy = ENEMY.instantiate()
	enemy.position = pos
	world.add_child(enemy)
	enemy.setup(enemy_id, player)
	enemy.died.connect(_on_enemy_died)
	enemy.summon_requested.connect(func(id, p): spawn_enemy(id, p))
	return enemy


func _spawn_hazards(params: Dictionary, location: Dictionary) -> void:
	var hazards: Array = location.get("hazards", [])
	if hazards.is_empty():
		return
	var dps := float(Content.config.get("player", {}).get("hazard_dps", 8))
	for i in int(params.get("hazard_zones", 0)):
		var room := gen.rooms[rng.randi_range(1, gen.rooms.size() - 1)]
		var zone: HazardZone = HAZARD.instantiate()
		zone.setup(hazards[rng.randi() % hazards.size()], Vector2(room.size) * CELL * 0.8, dps)
		zone.position = (Vector2(room.position) + Vector2(room.size) / 2.0) * CELL
		world.add_child(zone)


func _spawn_objectives() -> void:
	var far_rooms := gen.rooms_by_distance_desc()
	match objective.get("type", ""):
		"collect", "interact", "rescue":
			for i in goal:
				var obj: Objective = OBJECTIVE.instantiate()
				obj.setup(objective.type, objective.get("label", ""), map.accent)
				obj.position = map.cell_to_world(gen.random_cell_in_room(rng, far_rooms[i % far_rooms.size()]))
				obj.completed.connect(func(_o): _add_progress(1))
				world.add_child(obj)
		"boss":
			var boss := spawn_enemy(objective.boss, map.cell_to_world(gen.room_center(far_rooms[0])))
			hud.track_boss(boss)


# --- Tiến trình -----------------------------------------------------------------

func _on_enemy_died(enemy: Enemy) -> void:
	if enemy.data.has("loot"):
		_drop_loot(Loot.roll(rng, enemy.data.loot), enemy.global_position)
	if enemy.is_boss and objective.get("type", "") == "boss" and enemy.enemy_id == objective.boss:
		_add_progress(1)
		hud.show_message("%s đã bị hạ!" % enemy.data.get("name", ""))


func _on_node_depleted(node: ResourceNode) -> void:
	_drop_loot(Loot.roll_drops(rng, node.data.get("drops", {})), node.global_position)
	if node.data.has("loot"):
		_drop_loot(Loot.roll(rng, node.data.loot), node.global_position)


func _drop_loot(loot: Dictionary, pos: Vector2) -> void:
	for item_id in loot:
		if int(loot[item_id]) <= 0:
			continue
		var pickup: Pickup = PICKUP.instantiate()
		pickup.position = pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, 22.0)
		pickup.setup(item_id, int(loot[item_id]), player)
		pickup.picked.connect(_on_picked)
		world.call_deferred("add_child", pickup)


func _on_picked(item_id: String, count: int) -> void:
	run_loot[item_id] = int(run_loot.get(item_id, 0)) + count
	hud.show_message("+%d %s" % [count, Content.get_entry("items", item_id).get("name", item_id)])
	if objective.get("type", "") == "mine" and item_id == objective.item:
		_add_progress(count)
	hud.update_loot(run_loot)


func _consume_item(item_id: String) -> void:
	if int(run_loot.get(item_id, 0)) > 0:
		run_loot[item_id] -= 1
		if run_loot[item_id] <= 0:
			run_loot.erase(item_id)
		hud.update_loot(run_loot)
	else:
		Game.add_item(item_id, -1)


func _add_progress(amount: int) -> void:
	progress = mini(goal, progress + amount)
	_update_objective()
	if objective_done():
		exit_zone.unlocked = true
		hud.show_message("Mục tiêu hoàn thành! Quay về tàu con thoi.")


func objective_done() -> bool:
	return progress >= goal


func _update_objective() -> void:
	hud.set_objective("%s: %d/%d" % [objective.get("label", "Mục tiêu"), progress, goal], objective_done())


func _on_exit_left(body: Node) -> void:
	if body == player:
		_in_exit = false
		_left_spawn = true


func _on_exit_entered() -> void:
	_in_exit = true
	if not _left_spawn and not objective_done():
		return
	if objective_done():
		_finish(true, false, true)
	else:
		hud.show_message("Nhấn E để rút lui (nhiệm vụ thất bại, giữ đồ đã nhặt)")


func _process(_delta: float) -> void:
	if _finished:
		return
	if _in_exit and _left_spawn and Input.is_action_just_pressed("interact") and not objective_done():
		_finish(false, false, true)
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()


func _toggle_pause() -> void:
	if _finished:
		return
	get_tree().paused = not get_tree().paused
	hud.show_pause(get_tree().paused)


func _finish(success: bool, leader_down: bool, keep_loot: bool) -> void:
	if _finished:
		return
	_finished = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	player.set_physics_process(false)
	if keep_loot:
		Loot.give(Game, run_loot)
	var report := MissionSystem.finish_action(Game, success, leader_down)
	SaveManager.save_game()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	hud.show_result(report, run_loot if keep_loot else {}, leader_down)
