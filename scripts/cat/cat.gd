class_name Cat
extends Node2D
## Cat behaviour: wanders on the floor, sits, lies down, sleeps, wakes up, sometimes
## goes to the food bowl and eats. Tap on the floor -> walks there (debug),
## tap on the cat -> stops, sits and purrs, then continues what it was doing.

enum Mode { IDLE, WALK, SIT, LIE, SLEEP, EAT }

@export var walk_speed: float = 120.0          ## world px / s at depth scale 1
## View choice by the main direction of movement (with hysteresis against flicker):
## side view when walking along the room, front view towards the viewer, back view
## towards the wall.
const FRONTAL_ENTER_RATIO: float = 1.15   ## |dy|/|dx| above this -> front/back view
const FRONTAL_EXIT_RATIO: float = 0.87    ## |dy|/|dx| below this -> side view
@export var room_path: NodePath
## Placeholder food bowl (see Room.food_bowl); the cat eats there 3-5 s.
const EAT_TIME_MIN: float = 3.0
const EAT_TIME_MAX: float = 5.0
const EAT_CHANCE: float = 0.18

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
var _going_to_eat: bool = false
var _resume_walk: bool = false
var _resume_target: Vector2
var _resume_eat: float = 0.0
var _eat_pending: float = 0.0


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
	if rig.is_happy():
		return
	if rig.current_pose != CatRig.POSE_STAND or mode in [Mode.SIT, Mode.LIE, Mode.SLEEP]:
		_happy_after_stand = true
		_stand_up()
		return
	# remember what the cat was doing, to continue after purring
	if mode == Mode.WALK:
		_resume_walk = true
		_resume_target = _target
	elif mode == Mode.EAT:
		_resume_eat = rig.stop_eating()
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
		Mode.EAT:
			if _eat_pending > 0.0:
				# wait for the turn towards the bowl, then eat
				if not rig.is_busy():
					rig.start_eating(_eat_pending)
					_eat_pending = 0.0
			elif not rig.is_eating() and not rig.is_happy():
				# done: step away from the bowl
				mode = Mode.IDLE
				var away: float = -rig.facing
				_begin_walk(room.clamp_walk_point(position + Vector2(away * randf_range(250.0, 500.0),
						randf_range(-40.0, 40.0))))
	if mode != Mode.WALK:
		_speed_now = move_toward(_speed_now, 0.0, delta * 400.0)
		rig.walk_velocity = Vector2.ZERO
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
	# continue after purring
	if _resume_eat > 0.0:
		mode = Mode.EAT
		rig.start_eating(_resume_eat)
		_resume_eat = 0.0
		return
	if _resume_walk:
		_resume_walk = false
		_begin_walk(_resume_target, _going_to_eat)
		return
	_mode_timer -= delta
	if _mode_timer > 0.0:
		return
	var r: float = randf()
	if r < EAT_CHANCE and room.food_bowl:
		_go_eat()
	elif r < 0.6:
		_begin_walk(_random_floor_point())
	elif r < 0.87:
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
		var p: Vector2
		if randf() < 0.65:
			# along the room, with a little depth change
			var dx: float = randf_range(200.0, 900.0) * (1.0 if randf() < 0.5 else -1.0)
			p = position + Vector2(dx, randf_range(-0.3, 0.3) * absf(dx))
		else:
			# anywhere: also straight to the wall or towards the viewer
			p = position + Vector2(randf_range(-350.0, 350.0),
					randf_range(Room.WALK_Y_MIN, Room.WALK_Y_MAX) - position.y)
		p = room.clamp_walk_point(p)
		if p.distance_to(position) > 120.0:
			return p
	return room.clamp_walk_point(Vector2(Room.ROOM_WIDTH * 0.5, position.y))


## Walks to the bowl and eats there (placeholder bowl, see Room).
func _go_eat() -> void:
	var bowl: Vector2 = room.food_bowl.position
	# stand beside the bowl so that the lowered head is above it
	var side: float = -1.0 if position.x < bowl.x else 1.0
	var spot := Vector2(bowl.x + side * 0.42 * rig.cat_height * room.depth_scale(bowl.y), bowl.y - 3.0)
	_begin_walk(spot, true)


## The cat walks straight to the point (any direction).
func _begin_walk(p: Vector2, to_eat: bool = false) -> void:
	_going_to_eat = to_eat
	_path.clear()
	if p.distance_to(position) < 12.0:
		if absf(p.x - position.x) > 2.0 and rig.view == CatRig.View.SIDE:
			rig.turn_to(signf(p.x - position.x))
		return
	_target = p
	mode = Mode.WALK


func _view_for(d: Vector2) -> CatRig.View:
	var ratio: float = absf(d.y) / maxf(absf(d.x), 0.001)
	var frontal: bool
	if rig.view == CatRig.View.SIDE:
		frontal = ratio > FRONTAL_ENTER_RATIO
	else:
		frontal = ratio > FRONTAL_EXIT_RATIO
	if not frontal:
		return CatRig.View.SIDE
	return CatRig.View.FRONT if d.y > 0.0 else CatRig.View.BACK


func _start_eating() -> void:
	var bowl: Vector2 = room.food_bowl.position
	var dir: float = signf(bowl.x - position.x)
	if dir != 0.0 and dir != rig.facing:
		rig.turn_to(dir)
	mode = Mode.EAT
	_eat_pending = randf_range(EAT_TIME_MIN, EAT_TIME_MAX)


func _stop_walking() -> void:
	_path.clear()
	rig.walk_velocity = Vector2.ZERO
	if mode == Mode.WALK:
		mode = Mode.IDLE
		_mode_timer = randf_range(2.0, 5.0)


func _process_walk(delta: float) -> void:
	var to_target: Vector2 = _target - position
	var dist: float = to_target.length()
	if rig.is_turning():
		_drive_rig()
		return
	var want: CatRig.View = _view_for(to_target)
	if want == CatRig.View.SIDE:
		var dir_x: float = signf(to_target.x)
		if rig.view != CatRig.View.SIDE:
			# from front/back straight to the side sheet, facing the walking direction
			rig.set_view(CatRig.View.SIDE, dir_x)
		elif dir_x != 0.0 and dir_x != rig.facing:
			# the other way along the room: instant mirror
			rig.turn_to(dir_x)
	elif rig.view != want:
		rig.set_view(want)
	if rig.is_turning():
		_drive_rig()
		return
	var depth: float = room.depth_scale(position.y)
	var max_speed: float = walk_speed * depth
	var desired: float = minf(max_speed, dist * 2.2)   # smooth start and arrival
	_speed_now = move_toward(_speed_now, desired, delta * 300.0)
	if dist < 2.0 or (_speed_now < 4.0 and dist < 6.0):
		position = _target
		_speed_now = 0.0
		mode = Mode.IDLE
		_mode_timer = randf_range(2.5, 6.0)
		rig.walk_velocity = Vector2.ZERO
		# keeps standing in the view it walked in (front after walking down, etc.)
		if _going_to_eat:
			_going_to_eat = false
			_start_eating()
		return
	position += to_target / dist * minf(_speed_now * delta, dist)
	_drive_rig()


## Legs follow the speed in the cat's local (depth-scaled) pixels -> planted paws do not slide.
func _drive_rig() -> void:
	var to_target: Vector2 = _target - position
	var v := Vector2.ZERO
	if to_target.length() > 0.001:
		v = to_target.normalized() * _speed_now
	rig.walk_velocity = v / room.depth_scale(position.y)
