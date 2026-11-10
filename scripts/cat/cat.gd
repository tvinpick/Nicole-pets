class_name Cat
extends Node2D
## Cat behaviour: wanders on the floor, sits, lies down, sleeps, wakes up.
## Tap on the floor -> walks there (debug), tap on the cat -> happy.

enum Mode { IDLE, WALK, SIT, LIE, SLEEP }

@export var walk_speed: float = 70.0           ## world px / s at depth scale 1
## Max angle of a walk segment against the horizontal: the cat has only side views,
## so depth (screen y) changes only along gentle diagonals.
const MAX_SLOPE_DEG: float = 25.0
@export var room_path: NodePath

var room: Room
var rig: CatRig
var mode: Mode = Mode.IDLE
var _target: Vector2
var _has_target: bool = false
var _path: Array[Vector2] = []
var _mode_timer: float = 3.0
var _speed_now: float = 0.0
var _after_stand: Callable = Callable()
var _happy_after_stand: bool = false


func _ready() -> void:
	room = get_node(room_path) as Room
	rig = CatRig.new()
	rig.name = "Rig"
	add_child(rig)
	_apply_depth()
	_mode_timer = randf_range(2.0, 4.0)


func _apply_depth() -> void:
	var s: float = room.depth_scale(position.y)
	scale = Vector2(s, s)


# --- input from the game ---------------------------------------------------------------

func contains_point(world_pos: Vector2) -> bool:
	var local: Vector2 = to_local(world_pos)
	return rig.hit_rect().grow(14.0).has_point(local)


func on_tapped() -> void:
	if rig.current_pose != CatRig.POSE_STAND or mode in [Mode.SIT, Mode.LIE, Mode.SLEEP]:
		_happy_after_stand = true
		_stand_up()
		return
	_stop_walking()
	rig.make_happy()
	mode = Mode.IDLE
	_mode_timer = randf_range(3.0, 5.0)


func walk_to(world_pos: Vector2) -> void:
	var p: Vector2 = room.clamp_walk_point(world_pos)
	if rig.current_pose != CatRig.POSE_STAND:
		_target = p
		_has_target = true
		_stand_up()
		return
	_begin_walk(p)


# --- behaviour ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	match mode:
		Mode.IDLE:
			_process_idle(delta)
		Mode.WALK:
			_process_walk(delta)
		Mode.SIT, Mode.LIE, Mode.SLEEP:
			_process_rest(delta)
	if mode != Mode.WALK:
		_speed_now = move_toward(_speed_now, 0.0, delta * 400.0)
		rig.walk_speed = 0.0
	_apply_depth()


func _process_idle(delta: float) -> void:
	if rig.is_busy():
		return
	if _happy_after_stand and rig.current_pose == CatRig.POSE_STAND:
		_happy_after_stand = false
		rig.make_happy()
		_mode_timer = randf_range(3.0, 5.0)
		return
	if _has_target and rig.current_pose == CatRig.POSE_STAND:
		_has_target = false
		_begin_walk(_target)
		return
	if rig.is_happy():
		return
	_mode_timer -= delta
	if _mode_timer > 0.0:
		return
	var r: float = randf()
	if r < 0.55:
		_begin_walk(_random_floor_point())
	elif r < 0.85:
		_rest(Mode.SIT)
	else:
		_mode_timer = randf_range(2.0, 4.0)  # just stand and look around


func _process_rest(delta: float) -> void:
	if rig.is_busy():
		return
	_mode_timer -= delta
	if _mode_timer > 0.0:
		return
	var r: float = randf()
	match mode:
		Mode.SIT:
			if r < 0.45:
				_rest(Mode.LIE)
			else:
				_stand_up()
		Mode.LIE:
			if r < 0.55:
				_rest(Mode.SLEEP)
			elif r < 0.8:
				_rest(Mode.SIT)
			else:
				_stand_up()
		Mode.SLEEP:
			# wakes up: first sits, the next decision decides what to do
			_rest(Mode.SIT)


func _rest(m: Mode) -> void:
	mode = m
	match m:
		Mode.SIT:
			rig.set_pose(CatRig.POSE_SIT)
			_mode_timer = randf_range(6.0, 12.0)
		Mode.LIE:
			rig.set_pose(CatRig.POSE_LIE)
			_mode_timer = randf_range(7.0, 14.0)
		Mode.SLEEP:
			rig.set_pose(CatRig.POSE_SLEEP)
			_mode_timer = randf_range(16.0, 30.0)


func _stand_up() -> void:
	mode = Mode.IDLE
	rig.set_pose(CatRig.POSE_STAND)
	_mode_timer = randf_range(2.0, 5.0)


func _random_floor_point() -> Vector2:
	# mostly along the room; depth changes a little (always reachable by one diagonal)
	var slope: float = tan(deg_to_rad(MAX_SLOPE_DEG)) * 0.9
	for i in 10:
		var dx: float = randf_range(200.0, 900.0) * (1.0 if randf() < 0.5 else -1.0)
		var dy: float = randf_range(-1.0, 1.0) * absf(dx) * slope * randf()
		var p: Vector2 = room.clamp_walk_point(position + Vector2(dx, dy))
		if absf(p.x - position.x) > 150.0:
			return p
	return room.clamp_walk_point(Vector2(Room.ROOM_WIDTH * 0.5, position.y))


## Splits a walk into segments not steeper than MAX_SLOPE_DEG. If the target is
## too deep for the horizontal distance, the cat walks a longer diagonal first and
## then comes back along the room.
func _plan_path(from: Vector2, to: Vector2) -> Array[Vector2]:
	var slope: float = tan(deg_to_rad(MAX_SLOPE_DEG))
	var dx: float = to.x - from.x
	var dy: float = to.y - from.y
	if absf(dy) <= absf(dx) * slope + 1.0:
		return [to]
	var run: float = absf(dy) / slope
	var dir: float = signf(dx) if absf(dx) > 1.0 else rig.facing
	var x1: float = from.x + dir * run
	if x1 < Room.WALK_X_MARGIN or x1 > Room.ROOM_WIDTH - Room.WALK_X_MARGIN:
		dir = -dir
		x1 = from.x + dir * run
	x1 = clampf(x1, Room.WALK_X_MARGIN, Room.ROOM_WIDTH - Room.WALK_X_MARGIN)
	var mid := Vector2(x1, from.y + signf(dy) * absf(x1 - from.x) * slope)
	if absf(to.x - mid.x) < 30.0:
		return [mid]
	return [mid, Vector2(to.x, mid.y)]


func _begin_walk(p: Vector2) -> void:
	_path = _plan_path(position, p)
	if absf(_path[0].x - position.x) < 25.0 and _path.size() == 1:
		if absf(_path[0].x - position.x) > 2.0:
			rig.turn_to(signf(_path[0].x - position.x))
		_path.clear()
		return
	_target = _path.pop_front()
	mode = Mode.WALK


func _stop_walking() -> void:
	_path.clear()
	if mode == Mode.WALK:
		mode = Mode.IDLE
		_mode_timer = randf_range(2.0, 5.0)


func _process_walk(delta: float) -> void:
	var to_target: Vector2 = _target - position
	var dir_x: float = signf(to_target.x)
	if dir_x != 0.0 and dir_x != rig.facing:
		# stop, turn around, then continue
		_speed_now = move_toward(_speed_now, 0.0, delta * 600.0)
		if _speed_now <= 0.0:
			rig.turn_to(dir_x)
		_drive_rig(delta)
		return
	if rig.is_turning():
		_drive_rig(delta)
		return
	var dist: float = to_target.length()
	var depth: float = room.depth_scale(position.y)
	var max_speed: float = walk_speed * depth
	# smooth start and arrival
	var remaining: float = dist
	var prev: Vector2 = _target
	for q in _path:
		remaining += prev.distance_to(q)
		prev = q
	var desired: float = minf(max_speed, remaining * 2.2)
	if not _path.is_empty():
		var next_dir: float = signf(_path[0].x - _target.x)
		if next_dir != 0.0 and next_dir != rig.facing:
			desired = minf(max_speed, dist * 2.2)   # will turn there: slow down
	_speed_now = move_toward(_speed_now, desired, delta * 260.0)
	if not _path.is_empty() and dist < 2.0:
		# corner of the route: continue with the next segment (may need a turn)
		position = _target
		_target = _path.pop_front()
		_drive_rig(delta)
		return
	if dist < 2.0 or (_speed_now < 4.0 and dist < 6.0):
		position = _target
		_speed_now = 0.0
		mode = Mode.IDLE
		_mode_timer = randf_range(2.5, 6.0)
		rig.walk_speed = 0.0
		return
	position += to_target / dist * minf(_speed_now * delta, dist)
	_drive_rig(delta)


func _drive_rig(_delta: float) -> void:
	# legs are driven by the horizontal speed in rig units -> feet do not slide
	var s: float = room.depth_scale(position.y) * rig.rig_scale
	var horiz: float = _speed_now
	var to_target: Vector2 = _target - position
	if to_target.length() > 0.001:
		horiz = _speed_now * absf(to_target.x) / to_target.length()
	rig.walk_speed = horiz / s
