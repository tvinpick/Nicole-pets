class_name CatRig
extends Node2D
## The cat drawn from finished, whole pictures only (no cut-out parts):
##   walk_side  4 frames (cat_walk_side.png), mirrored for walking left, frame 1 = standing
##   walk_front 4 frames (cat_walk_front.png), towards the viewer, frame 1 = standing
##   walk_back  4 frames (cat_walk_back.png), away from the viewer, frame 1 = standing
##   eat_side   4 frames (cat_eat_side.png), eating from the floor, 2 and 4 = chewing
##   happy_sit  2 frames (cat_happy_sit.png), sitting half-turned, purring
##   pose_sit / pose_lie / pose_sleep (pose/*.png)
## Frames are cut and aligned by tools/process_cat.py (paw line + body centre) and listed
## in CatFrames.SETS. There is never semi-transparent mixing of two pictures: smoothness
## comes from motion, tilt and squash/stretch of the single visible picture. A change of
## action is a short "dip": the old picture sinks (or crouches), the new one settles in.
##
## This node's origin is on the floor under the cat's body; +x = the side it faces.

signal pose_changed(pose: StringName)

enum View { SIDE, FRONT, BACK }

const POSE_STAND := &"stand"
const POSE_SIT := &"sit"
const POSE_LIE := &"lie"
const POSE_SLEEP := &"sleep"
const POSE_ORDER: Array[StringName] = [&"stand", &"sit", &"lie", &"sleep"]
const POSE_LOOK: Dictionary[StringName, StringName] = {
	&"stand": &"walk_side", &"sit": &"pose_sit", &"lie": &"pose_lie", &"sleep": &"pose_sleep",
}

const FRAMES_DIR := "res://assets/characters/cat/rig/"
## Walk-side frame 1 (floor -> ear tips) in sheet px: the reference for all sizes.
const WALK_SIDE_HEIGHT := 525.0
## Looks drawn sideways (mirrored when facing left).
const SIDE_LOOKS: Array[StringName] = [&"walk_side", &"eat_side", &"happy_sit",
		&"pose_sit", &"pose_lie", &"pose_sleep", &"stretch", &"hunt", &"pounce"]
## Frame rhythm (s): key frames are held longer, in-betweens are quicker.
const STRETCH_TIMES: Array[float] = [0.9, 1.7, 1.4]      # sleepy, long stretch, yawn
const EAT_TIMES: Array[float] = [0.42, 0.3, 0.42, 0.3]   # head down / chewing (2, 4)
## walk frames 2 and 4 (a paw in the air) last longer than the contact frames 1 and 3
const WALK_WEIGHTS: Array[float] = [0.2, 0.3, 0.2, 0.3]
const HUNT_CREEP_FRAME := 0.42      # frames 1-2 while sneaking
const HUNT_WIGGLE_FRAME := 0.17     # frames 3-4 = one wiggle of the bottom
const HUNT_PAUSE := 0.32            # still for a moment before the jump
## Pounce: stand, crouch (held, squashing = getting ready), flight, landing.
const POUNCE_STAND := 0.1
const POUNCE_CROUCH := 0.3
const POUNCE_LAND_HOLD := 0.75
const POUNCE_SQUASH := 0.1
## Body travel per 4-frame walk cycle (two steps), as a part of the cat height.
## Front/back keep the values that already looked right.
const CYCLE_SIDE := 0.75
const CYCLE_FRONTAL := 0.55
## Change of action ("dip") lengths (s); 0 = instant (walk sheet switches, turning).
const DIP_VIEW := 0.0
const DIP_POSE := 0.5
const DIP_HAPPY := 0.42
const DIP_EAT := 0.5
const DIP_ACTION := 0.34
const DIP_OUT := 0.4                # part of the dip spent on the outgoing picture
const HAPPY_TIME := 2.6
## How "high" a picture is: going lower = sink, going higher = rise.
const LOOK_RANK: Dictionary[StringName, float] = {
	&"walk_side": 3.0, &"walk_front": 3.0, &"walk_back": 3.0, &"stretch": 3.0, &"pounce": 3.0,
	&"eat_side": 2.0, &"happy_sit": 2.2, &"pose_sit": 2.0, &"hunt": 1.5, &"pose_lie": 1.0,
	&"pose_sleep": 0.5,
}
## Shadow width per look, as a part of the cat height.
const SHADOW_W: Dictionary[StringName, float] = {
	&"walk_side": 0.95, &"walk_front": 0.6, &"walk_back": 0.6, &"eat_side": 0.9,
	&"happy_sit": 0.65, &"pose_sit": 0.7, &"pose_lie": 1.35, &"pose_sleep": 1.0,
	&"stretch": 1.05, &"hunt": 1.0, &"pounce": 0.95,
}


class Look:
	var holder: Node2D
	var sprite: Sprite2D
	var frames: Array[Texture2D] = []
	var scale: float = 1.0
	var height: float = 0.0        # frame-1 height in sheet px
	var canvas: Vector2
	var centre_x: float
	var paw_line: float


var facing: float = 1.0                      ## +1 looks right, -1 looks left
var view: View = View.SIDE
var current_pose: StringName = POSE_STAND
## walking velocity in this node's local px/s (world velocity / depth scale)
var walk_velocity: Vector2 = Vector2.ZERO
## height of the standing cat (floor -> ear tips) in local px
var cat_height: float = 160.0

var _looks: Dictionary[StringName, Look] = {}
var _look: StringName = &"walk_side"
var _look_from: StringName = &""
var _fade_t: float = -1.0           # progress of the current dip (0..1), -1 = none
var _fade_len: float = DIP_POSE

var _time: float = 0.0
var _phase: float = 0.0
var _walk_weight: float = 0.0
var _pose_queue: Array[StringName] = []
var _pose_target: StringName = &""
var _happy_t: float = -1.0
var _eat_left: float = -1.0
## current one-shot / hunting action: &"stretch", &"hunt", &"pounce" or &""
var _action: StringName = &""
var _act_t: float = 0.0
var _hunt_stage: int = 0            # 1 = sneaking, 2 = wiggling, 3 = wiggles done
var _wiggles: int = 0
var _jump_time: float = 0.45        # flight duration
var _jump_height: float = 0.0       # local px
var _air_height: float = 0.0        # current height above the floor (for the shadow)
var _shadow: Sprite2D
var _hearts: CatHearts


func _ready() -> void:
	cat_height = WorldScale.height_px(WorldScale.CAT_HEIGHT_CM)
	_build_shadow()
	for set_name: String in CatFrames.SETS.keys():
		_build_look(StringName(set_name))
	_hearts = CatHearts.new()
	_hearts.name = "Hearts"
	_hearts.cat_height = cat_height
	add_child(_hearts)
	_show_only(_look)
	_update(0.0)


func _build_look(look_name: StringName) -> void:
	var d: Array = CatFrames.SETS[String(look_name)]
	var l := Look.new()
	var count: int = d[0]
	l.canvas = d[1]
	l.paw_line = d[2]
	l.centre_x = d[3]
	l.height = d[4]
	var k: float = d[5]
	var walk_scale: float = cat_height / WALK_SIDE_HEIGHT
	# body-matched sets use k; front/back are matched by their own ear height
	l.scale = walk_scale * k if k > 0.0 else cat_height / l.height
	for i in count:
		l.frames.append(load(FRAMES_DIR + "%s_%d.png" % [look_name, i + 1]) as Texture2D)
	l.holder = Node2D.new()
	l.holder.name = "Look_" + String(look_name)
	l.sprite = Sprite2D.new()
	l.sprite.texture = l.frames[0]
	l.sprite.centered = false
	l.sprite.offset = Vector2(-l.centre_x, -l.paw_line)
	l.holder.add_child(l.sprite)
	l.holder.visible = false
	add_child(l.holder)
	_looks[look_name] = l


func _build_shadow() -> void:
	_shadow = Sprite2D.new()
	_shadow.name = "Shadow"
	var g := Gradient.new()
	g.set_color(0, Color(0.25, 0.12, 0.05, 0.42))
	g.set_color(1, Color(0.25, 0.12, 0.05, 0.0))
	g.add_point(0.55, Color(0.25, 0.12, 0.05, 0.26))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	_shadow.texture = gt
	add_child(_shadow)


# --- public API ----------------------------------------------------------------------

func is_busy() -> bool:
	return _fade_t >= 0.0 or not _pose_queue.is_empty() or _action != &"" \
			or _pose_target != &"" or _happy_t >= 0.0 or _eat_left >= 0.0


func is_turning() -> bool:
	return false   # turning is an instant mirror


func is_view_changing() -> bool:
	return _fade_t >= 0.0


func is_happy() -> bool:
	return _happy_t >= 0.0


func is_eating() -> bool:
	return _eat_left >= 0.0


## Walking views: side / front (towards the viewer) / back (towards the wall).
## new_facing: side to face when the side view comes back from front/back (0 = keep).
func set_view(v: View, new_facing: float = 0.0) -> void:
	if new_facing != 0.0 and v == View.SIDE and view != View.SIDE:
		facing = signf(new_facing)
	if v == view and _look == _view_look(v):
		return
	view = v
	# switching between walk sheets is immediate (no intermediate front picture)
	_set_look(_view_look(v), 0.0)


## Left <-> right: an instant mirror of the side pictures (no pause, no front picture).
func turn_to(dir: float) -> void:
	if dir != 0.0:
		facing = signf(dir)


## Goes through intermediate poses (stand <-> sit <-> lie <-> sleep).
func set_pose(target: StringName) -> void:
	_pose_queue.clear()
	var from_i: int = POSE_ORDER.find(_pose_target if _pose_target != &"" else current_pose)
	var to_i: int = POSE_ORDER.find(target)
	if from_i == to_i:
		return
	var step: int = 1 if to_i > from_i else -1
	var i: int = from_i + step
	while true:
		_pose_queue.append(POSE_ORDER[i])
		if i == to_i:
			break
		i += step


## Sits down smoothly and purrs for a moment (cat_happy_sit), then stands again.
func make_happy() -> void:
	if current_pose != POSE_STAND or _happy_t >= 0.0:
		return
	view = View.SIDE
	_action = &""
	_happy_t = 0.0
	_set_look(&"happy_sit", DIP_HAPPY)


## Eats from the floor for `seconds` (cat_eat_side), then stands again.
func start_eating(seconds: float) -> void:
	if current_pose != POSE_STAND:
		return
	view = View.SIDE
	_eat_left = seconds
	_set_look(&"eat_side", DIP_EAT)


## Wakes up properly: sleepy standing, big stretch, yawn (cat_stretch), then stands.
func stretch() -> void:
	if current_pose != POSE_STAND:
		return
	view = View.SIDE
	_start_action(&"stretch")


## Hunting: sneaks low (frames 1-2) until hunt_wiggle(); see is_hunt_ready().
func start_hunt() -> void:
	if current_pose != POSE_STAND:
		return
	view = View.SIDE
	_start_action(&"hunt")
	_hunt_stage = 1


## Wiggles the bottom `times` times (frames 3-4), then is_hunt_ready() becomes true.
func hunt_wiggle(times: int) -> void:
	if _action != &"hunt":
		return
	_hunt_stage = 2
	_wiggles = times
	_act_t = 0.0


func is_hunt_ready() -> bool:
	return _action == &"hunt" and _hunt_stage == 3


## Jump (cat_pounce): stand, crouch (held ~0.3 s), flight along a parabola, landing.
## distance: horizontal jump length in local px; flight time and height follow it.
## Returns (time until take-off, flight time) for the controller, which moves the cat
## forward linearly during the flight (the rig adds the vertical arc).
func pounce(distance: float) -> Vector2:
	_jump_time = clampf(0.4 + distance / cat_height * 0.08, 0.4, 0.5)
	_jump_height = clampf(distance * 0.35, cat_height * 0.12, cat_height * 0.4)
	var from_hunt: bool = _action == &"hunt"
	_action = &"pounce"
	# from the crouched hunt straight into the crouch frame (no standing flash)
	_act_t = POUNCE_STAND if from_hunt else 0.0
	_set_look(&"pounce", 0.0)
	return Vector2(POUNCE_STAND + POUNCE_CROUCH - _act_t, _jump_time)


func current_action() -> StringName:
	return _action


func cancel_action() -> void:
	if _action != &"":
		_action = &""
		_set_look(&"walk_side", DIP_ACTION)


func _start_action(look_name: StringName, fade: float = DIP_ACTION) -> void:
	_action = look_name
	_act_t = 0.0
	_set_look(look_name, fade)


func _action_frame(times: Array[float], t: float) -> int:
	var acc: float = 0.0
	for i in times.size():
		acc += times[i]
		if t < acc:
			return i
	return times.size() - 1


func _update_action(delta: float) -> void:
	if _action == &"":
		return
	_act_t += delta
	var total: float = -1.0
	match _action:
		&"stretch":
			total = _sum(STRETCH_TIMES)
		&"pounce":
			total = POUNCE_STAND + POUNCE_CROUCH + _jump_time + POUNCE_LAND_HOLD
		&"hunt":
			if _hunt_stage == 2 and _act_t >= HUNT_WIGGLE_FRAME * 2.0 * float(_wiggles) + HUNT_PAUSE:
				_hunt_stage = 3
	if total > 0.0 and _act_t >= total:
		_action = &""
		_set_look(&"walk_side", DIP_ACTION)


func _sum(a: Array[float]) -> float:
	var t: float = 0.0
	for v in a:
		t += v
	return t


## Interrupts eating; returns the remaining eating time.
func stop_eating() -> float:
	if _eat_left < 0.0:
		return 0.0
	var left: float = _eat_left
	_eat_left = -1.0
	if _look == &"eat_side":
		_set_look(&"walk_side", DIP_EAT)
	return maxf(left, 0.0)


## Bounding box of the visible cat in this node's local space.
func hit_rect() -> Rect2:
	var l: Look = _looks[_look]
	var w: float = (l.canvas.x - 16.0) * l.scale
	var h: float = l.height * l.scale
	return Rect2(-w * 0.5, -h, w, h)


# --- update ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	_time += delta
	_update_happy_and_eat(delta)
	_update_action(delta)
	_update_poses()
	if _fade_t >= 0.0:
		_fade_t += delta / _fade_len
		if _fade_t >= 1.0:
			_fade_t = -1.0
			_show_only(_look)
			if _pose_target != &"" and POSE_LOOK[_pose_target] == _look:
				current_pose = _pose_target
				_pose_target = &""
				pose_changed.emit(current_pose)
	_animate(delta)


func _update_happy_and_eat(delta: float) -> void:
	if _happy_t >= 0.0:
		_happy_t += delta
		_hearts.emitting = _happy_t > DIP_HAPPY and _happy_t < DIP_HAPPY + HAPPY_TIME - 0.4
		if _happy_t >= DIP_HAPPY + HAPPY_TIME and _look == &"happy_sit":
			_set_look(&"walk_side", DIP_HAPPY)
		elif _look == &"walk_side" and _fade_t < 0.0:
			_happy_t = -1.0
	else:
		_hearts.emitting = false
	if _eat_left >= 0.0:
		if _look == &"eat_side":
			_eat_left -= delta
			if _eat_left <= 0.0:
				_set_look(&"walk_side", DIP_EAT)
		elif _fade_t < 0.0:
			_eat_left = -1.0


func _update_poses() -> void:
	if _pose_queue.is_empty() or _pose_target != &"" or _fade_t >= 0.0 \
			or _happy_t >= 0.0 or _eat_left >= 0.0 or _action != &"":
		return
	if current_pose == POSE_STAND and walk_velocity.length() > 1.0:
		return
	view = View.SIDE   # resting poses are side pictures (cross-fade from any view)
	_pose_target = _pose_queue.pop_front()
	_set_look(POSE_LOOK[_pose_target], DIP_POSE)


func _view_look(v: View) -> StringName:
	match v:
		View.FRONT:
			return &"walk_front"
		View.BACK:
			return &"walk_back"
	return &"walk_side"


func _set_look(look_name: StringName, dip: float) -> void:
	if look_name == _look and _fade_t < 0.0:
		return
	if dip <= 0.0:
		_look = look_name
		_look_from = &""
		_fade_t = -1.0
		_show_only(look_name)
		return
	# a dip that starts during another one keeps the picture that is visible now
	var visible_now: StringName = _visible_look()
	_look_from = visible_now
	_look = look_name
	_fade_len = dip
	_fade_t = 0.0


func _visible_look() -> StringName:
	if _fade_t >= 0.0 and _fade_t < DIP_OUT and _look_from != &"":
		return _look_from
	return _look


func _show_only(look_name: StringName) -> void:
	for k: StringName in _looks.keys():
		var l: Look = _looks[k]
		l.holder.visible = k == look_name
		l.holder.modulate.a = 1.0


func _animate(delta: float) -> void:
	# walking: frame rate follows the speed along the view's main axis
	var speed: float = 0.0
	match _look:
		&"walk_side":
			speed = absf(walk_velocity.x)
		&"walk_front", &"walk_back":
			speed = absf(walk_velocity.y)
	var walking: bool = speed > 1.0
	_walk_weight = move_toward(_walk_weight, 1.0 if walking else 0.0, delta * 4.0)
	if walking:
		var cycle: float = cat_height * (CYCLE_SIDE if _look == &"walk_side" else CYCLE_FRONTAL)
		_phase = fposmod(_phase + delta * speed / cycle, 1.0)
	elif _walk_weight <= 0.0:
		_phase = 0.0   # standing = frame 1
	# only one picture is ever visible
	var shown: StringName = _visible_look()
	for k: StringName in _looks.keys():
		_looks[k].holder.visible = k == shown
	var dip_sx: float = 1.0
	var dip_sy: float = 1.0
	var dip_rot: float = 0.0
	if _fade_t >= 0.0 and _look_from != &"":
		var rank_d: float = LOOK_RANK[_look] - LOOK_RANK[_look_from]
		if _fade_t < DIP_OUT:
			# the outgoing picture sinks (going down) or crouches to push off (going up)
			var e: float = _ease(_fade_t / DIP_OUT)
			dip_sy = 1.0 - (0.08 if rank_d < 0.0 else 0.05) * e
			dip_sx = 1.0 + 0.03 * e
			if _look_from == &"eat_side":
				dip_rot = -0.08 * e           # head comes up from the bowl
		else:
			var e2: float = _ease((_fade_t - DIP_OUT) / (1.0 - DIP_OUT))
			if rank_d > 0.0:
				# rising: starts a little stretched up, settles
				dip_sy = 1.0 + 0.05 * (1.0 - e2)
				dip_sx = 1.0 - 0.02 * (1.0 - e2)
			else:
				# sinking: starts a little squashed, settles
				dip_sy = 1.0 - 0.05 * (1.0 - e2)
				dip_sx = 1.0 + 0.02 * (1.0 - e2)
			if _look == &"eat_side":
				dip_rot = -0.08 * (1.0 - e2)  # head lowers softly to the bowl
	_air_height = 0.0
	_pose_look(shown, dip_sx, dip_sy, dip_rot)
	# shadow stays on the floor; smaller and paler when the cat is up in the air
	var sw: float = SHADOW_W[shown]
	var up: float = clampf(_air_height / (cat_height * 0.4), 0.0, 1.0)
	_shadow.scale = Vector2(sw * cat_height / 128.0, 0.11 * cat_height / 128.0) * (1.0 - 0.45 * up)
	_shadow.modulate.a = 1.0 - 0.5 * up
	_shadow.position = Vector2(0.0, -0.01 * cat_height)


func _pose_look(look_name: StringName, dip_sx: float, dip_sy: float, dip_rot: float) -> void:
	var l: Look = _looks[look_name]
	var flip: float = facing if look_name in SIDE_LOOKS else 1.0
	var sx: float = dip_sx
	var sy: float = dip_sy
	var rot: float = dip_rot
	var pos := Vector2.ZERO
	var frame: int = 0
	var breath: float = sin(_time * TAU * 0.3)
	var h: float = cat_height
	match look_name:
		&"walk_side", &"walk_front", &"walk_back":
			var ww: float = _ease(_walk_weight)
			if look_name == _look and _walk_weight > 0.0:
				frame = _weighted_frame(WALK_WEIGHTS, _phase)
			# bob: up while a paw is in the air, down on contact (two steps per cycle);
			# a barely visible tilt in time with the steps
			var half: float = fposmod(_phase * 2.0, 1.0)
			pos.y = -sin(half * PI) * 0.012 * h * ww
			rot += sin(_phase * TAU) * (0.012 if look_name == &"walk_side" else 0.02) * ww
			sy *= 1.0 + breath * 0.008 * (1.0 - ww)
		&"eat_side":
			frame = _weighted_frame(EAT_TIMES, fposmod(_time / _sum(EAT_TIMES), 1.0))
			if frame == 1 or frame == 3:
				# chewing: the head bobs a little
				rot += sin(_time * 18.0) * 0.008
			sy *= 1.0 + breath * 0.006
		&"stretch":
			var t: float = _act_t if _action == &"stretch" else 0.0
			frame = _action_frame(STRETCH_TIMES, t)
			sy *= 1.0 + breath * 0.008
			if frame == 1:
				# long stretch: the body reaches forward
				var u: float = _ease(clampf((t - STRETCH_TIMES[0]) / 0.6, 0.0, 1.0))
				sx *= 1.0 + 0.05 * u
				pos.x = 0.02 * h * u
			elif frame == 2:
				# yawn: head tips back, then comes back
				var u2: float = clampf((t - STRETCH_TIMES[0] - STRETCH_TIMES[1]) / STRETCH_TIMES[2], 0.0, 1.0)
				rot += -0.05 * sin(u2 * PI)
				sx *= 1.0 + 0.05 * (1.0 - _ease(u2))
				pos.x = 0.02 * h * (1.0 - _ease(u2))
		&"hunt":
			# pressed to the floor, swaying a little
			rot += sin(_time * 1.8) * 0.01
			pos.x = sin(_time * 1.8) * 0.006 * h
			if _hunt_stage >= 2:
				var wig_len: float = HUNT_WIGGLE_FRAME * 2.0 * float(_wiggles)
				if _act_t < wig_len:
					frame = 2 + int(_act_t / HUNT_WIGGLE_FRAME) % 2   # rhythmic wiggle
				else:
					frame = 0    # short still pause before the jump
					rot = 0.0
			else:
				frame = int(_act_t / HUNT_CREEP_FRAME) % 2        # sneaking
		&"pounce":
			var t: float = _act_t if _action == &"pounce" else 999.0
			var t_fly: float = POUNCE_STAND + POUNCE_CROUCH
			var t_land: float = t_fly + _jump_time
			if t < POUNCE_STAND:
				frame = 0
			elif t < t_fly:
				# crouch, held: squashes a little, getting ready
				frame = 1
				var c: float = _ease((t - POUNCE_STAND) / POUNCE_CROUCH)
				sy *= 1.0 - 0.08 * c
				sx *= 1.0 + 0.04 * c
			elif t < t_land:
				# flight: a parabola up and down, nose up, then down; stretched
				frame = 2
				var u: float = (t - t_fly) / _jump_time
				_air_height = 4.0 * _jump_height * u * (1.0 - u)
				pos.y = -_air_height
				rot += -0.16 * (1.0 - 2.0 * u)
				sx *= 1.05
				sy *= 0.97
			else:
				# landing exactly on touch-down: short squash, soft recovery
				frame = 3
				var lt: float = t - t_land
				var sq: float = 1.0 - _ease(clampf((lt - POUNCE_SQUASH) / 0.2, 0.0, 1.0))
				if lt < POUNCE_SQUASH:
					sq = _ease(lt / POUNCE_SQUASH)
				sy *= 1.0 - 0.12 * sq
				sx *= 1.0 + 0.07 * sq
		&"happy_sit":
			# slow purring sway; the two pictures swap at the ends of the sway
			var w: float = 2.0
			rot += sin(_time * w) * 0.035
			frame = int(floor((_time * w + PI * 0.5) / PI)) % 2
			sy *= 1.0 + breath * 0.012
		_:
			# finished poses: breathing only (slower when asleep)
			var b: float = sin(_time * TAU * (0.2 if look_name == &"pose_sleep" else 0.28))
			sy *= 1.0 + b * 0.012
	l.sprite.texture = l.frames[frame]
	l.holder.position = Vector2(pos.x * flip, pos.y)
	l.holder.rotation = rot * flip
	l.holder.scale = Vector2(l.scale * sx * flip, l.scale * sy)


## Frame for a cycle phase 0..1 with per-frame durations (weights).
func _weighted_frame(weights: Array[float], phase: float) -> int:
	var total: float = _sum(weights)
	var acc: float = 0.0
	for i in weights.size():
		acc += weights[i] / total
		if phase < acc:
			return i
	return weights.size() - 1


func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
