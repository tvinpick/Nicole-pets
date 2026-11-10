class_name Cat
extends Node2D
## Cat behaviour: wanders on the floor, sits, lies down, sleeps, wakes up.
## Tap on the floor -> walks there (debug), tap on the cat -> happy.

enum Mode { IDLE, WALK, SIT, LIE, SLEEP }

@export var walk_speed: float = 125.0          ## world px / s at depth scale 1
@export var room_path: NodePath

var room: Room
var rig: CatRig
var mode: Mode = Mode.IDLE
var _target: Vector2
var _has_target: bool = false
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
	return rig.hit_rect().grow(10.0).has_point(local)


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
	for i in 10:
		var dx: float = randf_range(350.0, 1300.0) * (1.0 if randf() < 0.5 else -1.0)
		var p: Vector2 = room.clamp_walk_point(Vector2(position.x + dx,
				randf_range(Room.WALK_Y_MIN, Room.WALK_Y_MAX)))
		if absf(p.x - position.x) > 250.0:
			return p
	return room.clamp_walk_point(Vector2(Room.ROOM_WIDTH * 0.5, position.y))


func _begin_walk(p: Vector2) -> void:
	var dx: float = p.x - position.x
	# the body is side-view only: depth changes slowly relative to the horizontal walk
	var max_dy: float = maxf(absf(dx) * 0.35, 0.0)
	p.y = position.y + clampf(p.y - position.y, -max_dy, max_dy)
	if absf(dx) < 25.0:
		if absf(dx) > 2.0:
			rig.turn_to(signf(dx))
		return
	_target = p
	mode = Mode.WALK


func _stop_walking() -> void:
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
	var desired: float = minf(max_speed, dist * 2.2)
	_speed_now = move_toward(_speed_now, desired, delta * 260.0)
	if dist < 3.0 or (_speed_now < 6.0 and dist < 12.0):
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
