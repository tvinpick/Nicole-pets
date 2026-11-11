class_name Dog
extends Node2D
## Puppy behaviour: walks, sometimes runs; while standing wags its tail, barks, sits
## down to scratch an ear; sits, lies down, falls asleep and stretches after waking;
## eats and drinks at its own (placeholder) bowls; calls to play (play bow), runs to
## the ball and jumps on it. Tap on the puppy -> sits and is happy for a moment.
## Goes round the cat (PetSpace) and never plays with the ball at the same time.

enum Mode { IDLE, WALK, SIT, LIE, SLEEP, ACT, EAT, PLAY }

@export var room_path: NodePath
@export var walk_speed: float = 130.0        ## world px/s at depth 1
const RUN_MULT: float = 2.3
const RUN_CHANCE: float = 0.3
const FRONTAL_ENTER_RATIO: float = 1.15
const FRONTAL_EXIT_RATIO: float = 0.87
const JUMP_START_DIST: float = 1.4           ## x puppy height from the ball
const BALL_KICK: Vector2 = Vector2(280.0, 460.0)

var room: Room
var rig: DogRig
var mode: Mode = Mode.IDLE
var _target: Vector2
var _speed_now: float = 0.0
var _running: bool = false
var _mode_timer: float = 2.0
var _after_walk: StringName = &""          # &"eat", &"drink", &"play"
var _stretch_after_stand: bool = false
var _walk_after_stretch: bool = false
var _happy_after_stand: bool = false
var _resume_walk: bool = false
var _resume_target: Vector2
var _play_step: int = 0
var _play_t: float = 0.0
var _jump: Vector2 = Vector2.ZERO
var _jump_from: float = 0.0
var _jump_to: float = 0.0
var _kicked: bool = false


func _ready() -> void:
	room = get_node(room_path) as Room
	rig = DogRig.new()
	rig.name = "Rig"
	add_child(rig)
	room.pets.append(self)
	_apply_depth()
	_mode_timer = randf_range(1.5, 3.0)


func _apply_depth() -> void:
	var s: float = room.depth_scale(position.y)
	scale = Vector2(s, s)


func footprint() -> Vector2:
	var h: float = rig.dog_height * scale.x
	return Vector2(0.42 * h, 0.12 * h)


func contains_point(world_pos: Vector2) -> bool:
	return rig.hit_rect().grow(14.0).has_point(to_local(world_pos))


## Tap on the puppy: sits and is happy, then continues.
func on_tapped() -> void:
	if rig.is_happy():
		return
	if rig.current_pose != DogRig.POSE_STAND or mode in [Mode.SIT, Mode.LIE, Mode.SLEEP]:
		_happy_after_stand = true
		_stand_up()
		return
	if mode == Mode.WALK and _after_walk == &"":
		_resume_walk = true
		_resume_target = _target
	_quit_play()
	rig.stop_action()
	_halt()
	rig.play(&"happy")
	mode = Mode.ACT


## The cat takes the ball (PetSpace.take_ball): stop playing.
func yield_ball() -> void:
	if mode == Mode.PLAY or _after_walk == &"play":
		_quit_play()
		rig.stop_action()
		_halt()
		mode = Mode.IDLE
		_mode_timer = randf_range(1.0, 2.5)


# --- update ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	match mode:
		Mode.IDLE:
			_process_idle(delta)
		Mode.WALK:
			_process_walk(delta)
		Mode.SIT, Mode.LIE, Mode.SLEEP:
			_process_rest(delta)
		Mode.ACT, Mode.EAT:
			if rig.current_action() == &"" and not rig.is_busy():
				mode = Mode.IDLE
				_mode_timer = randf_range(1.5, 4.0)
				if _walk_after_stretch:
					_walk_after_stretch = false
					_begin_walk(_random_floor_point(), false)
		Mode.PLAY:
			_process_play(delta)
	if mode != Mode.WALK and mode != Mode.PLAY:
		rig.walk_velocity = Vector2.ZERO
	_apply_depth()


func _process_idle(delta: float) -> void:
	if rig.is_busy():
		return
	if _happy_after_stand and rig.current_pose == DogRig.POSE_STAND:
		_happy_after_stand = false
		rig.play(&"happy")
		mode = Mode.ACT
		return
	if _stretch_after_stand and rig.current_pose == DogRig.POSE_STAND:
		_stretch_after_stand = false
		_walk_after_stretch = true
		rig.play(&"stretch")
		mode = Mode.ACT
		return
	if _resume_walk:
		_resume_walk = false
		_begin_walk(_resume_target, false)
		return
	_mode_timer -= delta
	if _mode_timer > 0.0:
		return
	var r: float = randf()
	if r < 0.12:
		_go_bowl(&"eat")
	elif r < 0.2:
		_go_bowl(&"drink")
	elif r < 0.32 and room.ball and room.ball_user == null:
		rig.play(&"playbow")       # "let's play!"
		mode = Mode.ACT
		_after_walk = &"play_pending"
	elif r < 0.62:
		_begin_walk(_random_floor_point(), randf() < RUN_CHANCE)
	elif r < 0.72:
		rig.play(&"wag")
		mode = Mode.ACT
	elif r < 0.8:
		rig.play(&"bark")
		mode = Mode.ACT
	elif r < 0.87:
		rig.play(&"scratch")
		mode = Mode.ACT
	else:
		_rest(Mode.SIT)


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
			else:
				_stand_up()
		Mode.SLEEP:
			_stretch_after_stand = true
			_stand_up()


func _rest(m: Mode) -> void:
	mode = m
	match m:
		Mode.SIT:
			rig.set_pose(DogRig.POSE_SIT)
			_mode_timer = randf_range(5.0, 10.0)
		Mode.LIE:
			rig.set_pose(DogRig.POSE_LIE)
			_mode_timer = randf_range(6.0, 12.0)
		Mode.SLEEP:
			rig.set_pose(DogRig.POSE_SLEEP)
			_mode_timer = randf_range(15.0, 28.0)


func _stand_up() -> void:
	mode = Mode.IDLE
	rig.set_pose(DogRig.POSE_STAND)
	_mode_timer = randf_range(1.5, 4.0)


# --- walking ------------------------------------------------------------------------

func _random_floor_point() -> Vector2:
	for i in 10:
		var p: Vector2
		if randf() < 0.65:
			var dx: float = randf_range(250.0, 1000.0) * (1.0 if randf() < 0.5 else -1.0)
			p = position + Vector2(dx, randf_range(-0.3, 0.3) * absf(dx))
		else:
			p = position + Vector2(randf_range(-350.0, 350.0),
					randf_range(Room.WALK_Y_MIN, Room.WALK_Y_MAX) - position.y)
		p = room.clamp_walk_point(p)
		if p.distance_to(position) > 140.0:
			return p
	return room.clamp_walk_point(Vector2(Room.ROOM_WIDTH * 0.4, position.y))


func _begin_walk(p: Vector2, run: bool) -> void:
	if p.distance_to(position) < 12.0:
		_arrived()
		return
	_target = room.clamp_walk_point(p)
	_running = run
	mode = Mode.WALK


func _view_for(d: Vector2) -> DogRig.View:
	var ratio: float = absf(d.y) / maxf(absf(d.x), 0.001)
	var frontal: bool = ratio > (FRONTAL_ENTER_RATIO if rig.view == DogRig.View.SIDE else FRONTAL_EXIT_RATIO)
	if not frontal:
		return DogRig.View.SIDE
	return DogRig.View.FRONT if d.y > 0.0 else DogRig.View.BACK


func _process_walk(delta: float) -> void:
	if rig.current_pose != DogRig.POSE_STAND or rig.is_busy():
		# never slides along sitting/lying: gets up first (or finishes the current action)
		if rig.current_pose != DogRig.POSE_STAND:
			rig.set_pose(DogRig.POSE_STAND)
		rig.walk_velocity = Vector2.ZERO
		return
	var to_target: Vector2 = _target - position
	var dist: float = to_target.length()
	var depth: float = room.depth_scale(position.y)
	var max_speed: float = walk_speed * depth * (RUN_MULT if _running else 1.0)
	_speed_now = move_toward(_speed_now, minf(max_speed, dist * 2.2), delta * (600.0 if _running else 300.0))
	if dist < 2.0 or (_speed_now < 4.0 and dist < 6.0):
		position = _target
		_halt()
		_arrived()
		return
	var dir: Vector2 = PetSpace.steer(room, self, to_target / dist)
	var want: DogRig.View = _view_for(dir)
	if want == DogRig.View.SIDE:
		rig.set_view(DogRig.View.SIDE, signf(dir.x) if absf(dir.x) > 0.05 else rig.facing)
	else:
		rig.set_view(want)
	rig.running = _running
	position += dir * minf(_speed_now * delta, dist)
	PetSpace.separate(room, self)
	rig.walk_velocity = dir * _speed_now / depth


func _halt() -> void:
	_speed_now = 0.0
	_running = false
	rig.running = false
	rig.walk_velocity = Vector2.ZERO


func _arrived() -> void:
	mode = Mode.IDLE
	_mode_timer = randf_range(1.5, 4.0)
	rig.set_view(DogRig.View.SIDE)
	var next: StringName = _after_walk
	_after_walk = &""
	match next:
		&"eat", &"drink":
			var bowl: Node2D = room.dog_food_bowl if next == &"eat" else room.dog_water_bowl
			rig.turn_to(signf(bowl.position.x - position.x))
			rig.play(&"eat", randf_range(3.0, 5.0))   # dog_eat frames for eating and drinking
			mode = Mode.EAT
		&"play":
			_start_jump()


# --- bowls ---------------------------------------------------------------------------

func _go_bowl(what: StringName) -> void:
	var bowl: Node2D = room.dog_food_bowl if what == &"eat" else room.dog_water_bowl
	if bowl == null:
		return
	var side: float = -1.0 if position.x < bowl.position.x else 1.0
	var h: float = rig.dog_height * room.depth_scale(bowl.position.y)
	_after_walk = what
	_begin_walk(Vector2(bowl.position.x + side * 0.45 * h, bowl.position.y - 3.0), false)


# --- play with the ball (placeholder) ------------------------------------------------

func _process_play(delta: float) -> void:
	_play_t += delta
	var ball: BallPlaceholder = room.ball
	var u: float = clampf((_play_t - _jump.x) / _jump.y, 0.0, 1.0)
	position.x = lerpf(_jump_from, _jump_to, u)
	if not _kicked and u > 0.85:
		_kicked = true
		ball.kick(Vector2(rig.facing * randf_range(BALL_KICK.x, BALL_KICK.y), randf_range(-60.0, 60.0)))
	if rig.current_action() == &"" and not rig.is_busy():
		_quit_play()
		mode = Mode.IDLE
		_mode_timer = randf_range(1.5, 3.0)
	rig.walk_velocity = Vector2.ZERO


func _run_to_ball() -> void:
	if not PetSpace.take_ball(room, self, false):
		mode = Mode.IDLE
		_mode_timer = randf_range(1.0, 2.0)
		return
	var b: Vector2 = room.ball.position
	var h: float = rig.dog_height * room.depth_scale(b.y)
	var side: float = signf(position.x - b.x)
	if side == 0.0:
		side = -rig.facing
	var spot := Vector2(b.x + side * JUMP_START_DIST * h, b.y - 2.0)
	if spot.x < Room.WALK_X_MARGIN or spot.x > Room.ROOM_WIDTH - Room.WALK_X_MARGIN:
		spot.x = b.x - side * JUMP_START_DIST * h
	_after_walk = &"play"
	_begin_walk(spot, true)


func _start_jump() -> void:
	var ball: BallPlaceholder = room.ball
	if room.ball_user != self or ball.is_rolling():
		_quit_play()
		return
	var depth: float = room.depth_scale(position.y)
	var h: float = rig.dog_height * depth
	rig.turn_to(signf(ball.position.x - position.x))
	_jump_from = position.x
	_jump_to = ball.position.x - rig.facing * 0.2 * h
	_jump = rig.jump(absf(_jump_to - _jump_from) / depth)
	_play_t = 0.0
	_kicked = false
	mode = Mode.PLAY


func _quit_play() -> void:
	if _after_walk == &"play" or _after_walk == &"play_pending":
		_after_walk = &""
	PetSpace.release_ball(room, self)


func _physics_process(_delta: float) -> void:
	# after the play bow the puppy runs to the ball
	if _after_walk == &"play_pending" and mode == Mode.IDLE and not rig.is_busy():
		_after_walk = &""
		_run_to_ball()
	elif _after_walk == &"play_pending" and mode == Mode.ACT and rig.current_action() == &"" \
			and not rig.is_busy():
		_after_walk = &""
		_run_to_ball()
