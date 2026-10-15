class_name PathFollower
extends RefCounted
## Đi theo đường A* (PathGrid) + tự gỡ kẹt.
##   - Tự tìm lại đường khi đích dịch chuyển xa hoặc định kỳ.
##   - Phát hiện kẹt: mỗi STUCK_CHECK giây mà gần như không nhích được -> tìm lại đường + né sang ngang;
##     kẹt liên tục thì bỏ qua điểm mốc hiện tại.

const STUCK_CHECK := 0.4
const STUCK_DISTANCE := 6.0
const WAYPOINT_RADIUS := 22.0
const REPATH_INTERVAL := 2.5

var grid: PathGrid
var arrive_radius := 20.0
var path := PackedVector2Array()
var index := 0
var goal := Vector2.INF
var stuck_events := 0

var _repath := 0.0
var _check := 0.0
var _last_pos := Vector2.INF
var _sidestep := Vector2.ZERO
var _sidestep_left := 0.0
var _stuck_streak := 0


func clear() -> void:
	goal = Vector2.INF
	path = PackedVector2Array()
	index = 0


func set_goal(from: Vector2, to: Vector2, force: bool = false) -> void:
	if not force and goal != Vector2.INF and goal.distance_to(to) < 48.0 and not path.is_empty():
		return
	goal = to
	_recompute(from)


func _recompute(from: Vector2) -> void:
	path = grid.find_path(from, goal) if grid else PackedVector2Array([goal])
	index = 0
	_repath = REPATH_INTERVAL


func arrived(pos: Vector2) -> bool:
	return goal == Vector2.INF or pos.distance_to(goal) <= arrive_radius


## Hướng đi (đã chuẩn hóa) cho khung này; Vector2.ZERO nếu đã tới.
func next_direction(pos: Vector2, delta: float) -> Vector2:
	if arrived(pos):
		return Vector2.ZERO
	_repath -= delta
	if _repath <= 0.0:
		_recompute(pos)
	while index < path.size() - 1 and pos.distance_to(path[index]) < WAYPOINT_RADIUS:
		index += 1
	var target: Vector2 = path[index] if index < path.size() else goal
	var dir := (target - pos).normalized()
	_detect_stuck(pos, delta, dir)
	if _sidestep_left > 0.0:
		_sidestep_left -= delta
		dir = (dir * 0.35 + _sidestep).normalized()
	return dir


func _detect_stuck(pos: Vector2, delta: float, dir: Vector2) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = STUCK_CHECK
	if _last_pos != Vector2.INF and pos.distance_to(_last_pos) < STUCK_DISTANCE:
		stuck_events += 1
		_stuck_streak += 1
		# Né sang ngang (đổi bên mỗi lần) rồi tìm lại đường từ chỗ hiện tại
		_sidestep = dir.orthogonal() * (1.0 if _stuck_streak % 2 == 1 else -1.0)
		_sidestep_left = 0.35
		_recompute(pos)
		if _stuck_streak >= 3 and index < path.size() - 1:
			index += 1
	else:
		_stuck_streak = 0
	_last_pos = pos
