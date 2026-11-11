class_name DogRig
extends Node2D
## The puppy drawn from whole frames only (assets/characters/dog/frames, cut by
## tools/process_dog.py, table in DogFrames.SETS). Same rules as the cat (CatRig):
## one visible picture at a time, no semi-transparent mixing; smoothness from motion,
## tilt and squash/stretch; a change of action is a short "dip"; left/right is an
## instant mirror; walk sheets switch instantly; the shadow stays on the floor.
##
## Origin on the floor under the body; +x = the side the puppy faces.

signal pose_changed(pose: StringName)

enum View { SIDE, FRONT, BACK }

const POSE_STAND := &"stand"
const POSE_SIT := &"sit"
const POSE_LIE := &"lie"
const POSE_SLEEP := &"sleep"
const POSE_ORDER: Array[StringName] = [&"stand", &"sit", &"lie", &"sleep"]
const POSE_LOOK: Dictionary[StringName, StringName] = {
	&"stand": &"wag", &"sit": &"sit", &"lie": &"lie", &"sleep": &"sleep",
}
const FRAMES_DIR := "res://assets/characters/dog/frames/"
## Reference: dog_wag frame 1 (standing, side) height in sheet px.
const REF_HEIGHT := 375.0
## Safety net if a sheet is ever missing: walk_side -> the run frames at walking
## pace, walk_front -> no front view (walks down in the side view). Both sheets exist now.
const FALLBACK: Dictionary[StringName, StringName] = {&"walk_side": &"run"}
## Drawn sideways (mirrored when facing left).
const FRONTAL_LOOKS: Array[StringName] = [&"walk_front", &"walk_back"]

## Body travel per walk/run cycle as a part of the puppy height.
const CYCLE_WALK := 0.8
const CYCLE_RUN := 1.5
## Frame rhythms (s); key frames held longer.
const STRETCH_TIMES: Array[float] = [0.9, 1.6, 1.3]
const EAT_TIMES: Array[float] = [0.36, 0.22, 0.3, 0.22, 0.3, 0.26]
const WAG_FRAME := 0.09
const HAPPY_FRAME := 0.2
const PLAYBOW_FRAME := 0.13
const BARK_TIMES: Array[float] = [0.26, 0.16]
const SCRATCH_TIMES: Array[float] = [0.5]           # then frames 2-3 alternate
const SCRATCH_FRAME := 0.11
## Jump: stand, crouch, deep crouch (held, squash), flight (frames 4-5), landing (6).
const JUMP_STAND := 0.1
const JUMP_CROUCH := 0.14
const JUMP_LOAD := 0.3
const JUMP_LAND_HOLD := 0.6
const JUMP_SQUASH := 0.1
## Dip lengths (s); 0 = instant.
const DIP_POSE := 0.5
const DIP_ACTION := 0.34
const DIP_OUT := 0.4
const HAPPY_TIME := 2.6
const LOOK_RANK: Dictionary[StringName, float] = {
	&"wag": 3.0, &"walk_side": 3.0, &"walk_front": 3.0, &"walk_back": 3.0, &"run": 3.0,
	&"stretch": 3.0, &"jump": 3.0, &"bark": 3.0, &"eat": 2.2, &"playbow": 2.0,
	&"happy": 2.0, &"scratch": 2.0, &"sit": 2.0, &"lie": 1.0, &"sleep": 0.5,
}
const SHADOW_W: Dictionary[StringName, float] = {
	&"wag": 0.95, &"walk_side": 0.95, &"walk_front": 0.6, &"walk_back": 0.6, &"run": 1.0,
	&"eat": 0.95, &"happy": 0.7, &"sit": 0.75, &"lie": 1.35, &"sleep": 1.1,
	&"stretch": 1.1, &"playbow": 1.0, &"jump": 0.95, &"bark": 0.95, &"scratch": 0.8,
}


class Look:
	var holder: Node2D
	var sprite: Sprite2D
	var frames: Array[Texture2D] = []
	var scale: float = 1.0
	var height: float = 0.0
	var canvas: Vector2


var facing: float = 1.0
var view: View = View.SIDE
var current_pose: StringName = POSE_STAND
var walk_velocity: Vector2 = Vector2.ZERO   ## local px/s
var running: bool = false                   ## use the run sheet
var dog_height: float = 180.0               ## standing puppy height, local px

var _looks: Dictionary[StringName, Look] = {}
var _look: StringName = &"wag"
var _look_from: StringName = &""
var _fade_t: float = -1.0
var _fade_len: float = DIP_POSE
var _time: float = 0.0
var _phase: float = 0.0
var _walk_weight: float = 0.0
var _pose_queue: Array[StringName] = []
var _pose_target: StringName = &""
## one-shot / timed action on top of standing: wag, bark, scratch, stretch, happy,
## eat, playbow, jump
var _action: StringName = &""
var _act_t: float = 0.0
var _act_len: float = 0.0
var _jump_time: float = 0.45
var _jump_height: float = 0.0
var _air_height: float = 0.0
var _shadow: Sprite2D
var _hearts: CatHearts


func _ready() -> void:
	dog_height = WorldScale.height_px(WorldScale.DOG_HEIGHT_CM)
	_build_shadow()
	for set_name: String in DogFrames.SETS.keys():
		_build_look(StringName(set_name))
	for missing: StringName in FALLBACK.keys():
		if not _looks.has(missing):
			_looks[missing] = _looks[FALLBACK[missing]]
	_hearts = CatHearts.new()
	_hearts.name = "Hearts"
	_hearts.cat_height = dog_height
	add_child(_hearts)
	_show_only(_look)
	_update(0.0)


func _build_look(look_name: StringName) -> void:
	var d: Array = DogFrames.SETS[String(look_name)]
	var l := Look.new()
	var count: int = d[0]
	l.canvas = d[1]
	var paw_line: float = d[2]
	var centre_x: float = d[3]
	l.height = d[4]
	l.scale = dog_height / REF_HEIGHT * float(d[5])
	for i in count:
		l.frames.append(load(FRAMES_DIR + "%s_%d.png" % [look_name, i + 1]) as Texture2D)
	l.holder = Node2D.new()
	l.holder.name = "Look_" + String(look_name)
	l.sprite = Sprite2D.new()
	l.sprite.texture = l.frames[0]
	l.sprite.centered = false
	l.sprite.offset = Vector2(-centre_x, -paw_line)
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


# --- public API ------------------------------------------------------------------------

func has_front_view() -> bool:
	return DogFrames.SETS.has("walk_front")


func is_busy() -> bool:
	return _fade_t >= 0.0 or not _pose_queue.is_empty() or _pose_target != &"" \
			or _action != &""


func current_action() -> StringName:
	return _action


func set_view(v: View, new_facing: float = 0.0) -> void:
	if v == View.FRONT and not has_front_view():
		v = View.SIDE
	if new_facing != 0.0 and v == View.SIDE:
		facing = signf(new_facing)
	view = v
	var want: StringName = _move_look()
	if _action == &"" and _pose_target == &"" and current_pose == POSE_STAND and want != _look:
		_set_look(want, 0.0)


func turn_to(dir: float) -> void:
	if dir != 0.0:
		facing = signf(dir)


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


## Timed actions from standing. seconds <= 0 -> natural length of the action.
func play(action: StringName, seconds: float = 0.0) -> void:
	if current_pose != POSE_STAND:
		return
	view = View.SIDE
	_action = action
	_act_t = 0.0
	match action:
		&"wag":
			_act_len = seconds if seconds > 0.0 else 2.2
		&"bark":
			_act_len = seconds if seconds > 0.0 else 1.7
		&"scratch":
			_act_len = seconds if seconds > 0.0 else 2.4
		&"stretch":
			_act_len = _sum(STRETCH_TIMES)
		&"happy":
			_act_len = HAPPY_TIME
		&"eat":
			_act_len = seconds if seconds > 0.0 else 4.0
		&"playbow":
			_act_len = seconds if seconds > 0.0 else 1.6
	if action == &"wag":
		_set_look(&"wag", 0.0)
	else:
		_set_look(action, DIP_ACTION)


func is_happy() -> bool:
	return _action == &"happy"


## Jump on something `distance` local px ahead. Returns (time to take-off, flight time).
func jump(distance: float) -> Vector2:
	view = View.SIDE
	_jump_time = clampf(0.4 + distance / dog_height * 0.08, 0.4, 0.5)
	# frames 4-5 are already drawn in the air: the arc adds only a little height
	_jump_height = clampf(distance * 0.12, dog_height * 0.04, dog_height * 0.14)
	_action = &"jump"
	_act_t = 0.0
	_act_len = JUMP_STAND + JUMP_CROUCH + JUMP_LOAD + _jump_time + JUMP_LAND_HOLD
	_set_look(&"jump", DIP_ACTION if _look != &"playbow" else 0.0)
	return Vector2(JUMP_STAND + JUMP_CROUCH + JUMP_LOAD, _jump_time)


## Stops the current action; returns the time it still had left.
func stop_action() -> float:
	if _action == &"":
		return 0.0
	var left: float = maxf(_act_len - _act_t, 0.0)
	_action = &""
	_hearts.emitting = false
	_set_look(_move_look(), DIP_ACTION)
	return left


func hit_rect() -> Rect2:
	var l: Look = _looks[_visible_look()]
	var w: float = (l.canvas.x - 16.0) * l.scale
	var h: float = l.height * l.scale
	return Rect2(-w * 0.5, -h, w, h)


# --- update --------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	_time += delta
	if _action != &"":
		_act_t += delta
		_hearts.emitting = _action == &"happy" and _act_t > 0.3 and _act_t < _act_len - 0.4
		if _act_t >= _act_len:
			_action = &""
			_hearts.emitting = false
			_set_look(_move_look(), DIP_ACTION if _look != &"wag" else 0.0)
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
	# while walking the sheet follows the view / gait (instant switches)
	if _action == &"" and _pose_target == &"" and current_pose == POSE_STAND and _fade_t < 0.0:
		var want: StringName = _move_look()
		if want != _look:
			_set_look(want, 0.0)
	_animate(delta)


func _update_poses() -> void:
	if _pose_queue.is_empty() or _pose_target != &"" or _fade_t >= 0.0 or _action != &"":
		return
	if current_pose == POSE_STAND and walk_velocity.length() > 1.0:
		return
	view = View.SIDE
	_pose_target = _pose_queue.pop_front()
	_set_look(POSE_LOOK[_pose_target], DIP_POSE)


## Picture for standing / walking in the current view.
func _move_look() -> StringName:
	var moving: bool = walk_velocity.length() > 1.0 or _walk_weight > 0.05
	match view:
		View.FRONT:
			return &"walk_front"
		View.BACK:
			return &"walk_back"
	if not moving:
		return &"wag"
	return &"run" if running else &"walk_side"


func _set_look(look_name: StringName, dip: float) -> void:
	if look_name == _look and _fade_t < 0.0:
		return
	if dip <= 0.0:
		_look = look_name
		_look_from = &""
		_fade_t = -1.0
		_show_only(look_name)
		return
	_look_from = _visible_look()
	_look = look_name
	_fade_len = dip
	_fade_t = 0.0


func _visible_look() -> StringName:
	if _fade_t >= 0.0 and _fade_t < DIP_OUT and _look_from != &"":
		return _look_from
	return _look


func _show_only(look_name: StringName) -> void:
	var shown: Look = _looks[look_name]
	for k: StringName in _looks.keys():
		var l: Look = _looks[k]
		l.holder.visible = l == shown


func _animate(delta: float) -> void:
	var speed: float = 0.0
	match _look:
		&"walk_side", &"run":
			speed = absf(walk_velocity.x)
		&"walk_front", &"walk_back":
			speed = absf(walk_velocity.y)
	var walking: bool = speed > 1.0
	_walk_weight = move_toward(_walk_weight, 1.0 if walking else 0.0, delta * 4.0)
	if walking:
		var cyc: float = CYCLE_RUN if (_look == &"run" and running) else CYCLE_WALK
		_phase = fposmod(_phase + delta * speed / (dog_height * cyc), 1.0)
	elif _walk_weight <= 0.0:
		_phase = 0.0
	var shown: StringName = _visible_look()
	_show_only(shown)
	var dip_sx: float = 1.0
	var dip_sy: float = 1.0
	if _fade_t >= 0.0 and _look_from != &"":
		var rank_d: float = LOOK_RANK[_look] - LOOK_RANK[_look_from]
		if _fade_t < DIP_OUT:
			var e: float = _ease(_fade_t / DIP_OUT)
			dip_sy = 1.0 - (0.08 if rank_d < 0.0 else 0.05) * e
			dip_sx = 1.0 + 0.03 * e
		else:
			var e2: float = 1.0 - _ease((_fade_t - DIP_OUT) / (1.0 - DIP_OUT))
			dip_sy = 1.0 + (0.05 if rank_d > 0.0 else -0.05) * e2
			dip_sx = 1.0 + (-0.02 if rank_d > 0.0 else 0.02) * e2
	_air_height = 0.0
	_pose_look(shown, dip_sx, dip_sy)
	var sw: float = SHADOW_W[shown]
	var up: float = clampf(_air_height / (dog_height * 0.4), 0.0, 1.0)
	_shadow.scale = Vector2(sw * dog_height / 128.0, 0.11 * dog_height / 128.0) * (1.0 - 0.45 * up)
	_shadow.modulate.a = 1.0 - 0.5 * up
	_shadow.position = Vector2(0.0, -0.01 * dog_height)


func _pose_look(look_name: StringName, sx: float, sy: float) -> void:
	var l: Look = _looks[look_name]
	var flip: float = 1.0 if look_name in FRONTAL_LOOKS else facing
	var rot: float = 0.0
	var pos := Vector2.ZERO
	var frame: int = 0
	var n: int = l.frames.size()
	var breath: float = sin(_time * TAU * 0.3)
	var h: float = dog_height
	var t: float = _act_t if _action == look_name else 0.0
	match look_name:
		&"walk_side", &"walk_front", &"walk_back", &"run":
			var ww: float = _ease(_walk_weight)
			if _walk_weight > 0.0:
				frame = int(_phase * n) % n
			var half: float = fposmod(_phase * 2.0, 1.0)
			pos.y = -sin(half * PI) * (0.02 if running else 0.012) * h * ww
			rot = sin(_phase * TAU) * (0.02 if look_name in FRONTAL_LOOKS else 0.014) * ww
			sy *= 1.0 + breath * 0.008 * (1.0 - ww)
		&"wag":
			if _action == &"wag":
				frame = int(t / WAG_FRAME) % n
				rot = sin(t * 9.0) * 0.012 * minf(t * 3.0, 1.0)
			sy *= 1.0 + breath * 0.009
		&"bark":
			# a bark = open mouth with a little forward pop, then close
			frame = _weighted_frame(BARK_TIMES, fposmod(t / _sum(BARK_TIMES), 1.0))
			if frame == 1:
				sx *= 1.03
				sy *= 0.98
				rot = -0.03
		&"scratch":
			if t < SCRATCH_TIMES[0]:
				frame = 0
			else:
				frame = 1 + int((t - SCRATCH_TIMES[0]) / SCRATCH_FRAME) % 2
				rot = sin(t * 30.0) * 0.008
			sy *= 1.0 + breath * 0.008
		&"stretch":
			frame = _action_frame(STRETCH_TIMES, t)
			if frame == 1:
				var u: float = _ease(clampf((t - STRETCH_TIMES[0]) / 0.6, 0.0, 1.0))
				sx *= 1.0 + 0.05 * u
				pos.x = 0.02 * h * u
			elif frame == 2:
				var u2: float = clampf((t - STRETCH_TIMES[0] - STRETCH_TIMES[1]) / STRETCH_TIMES[2], 0.0, 1.0)
				rot = -0.05 * sin(u2 * PI)
				sx *= 1.0 + 0.05 * (1.0 - _ease(u2))
		&"happy":
			frame = int(_time / HAPPY_FRAME) % n
			rot = sin(_time * 2.0) * 0.035
			sy *= 1.0 + breath * 0.012
		&"eat":
			frame = _weighted_frame(EAT_TIMES, fposmod(_time / _sum(EAT_TIMES), 1.0))
			rot = sin(_time * 14.0) * 0.006
		&"playbow":
			frame = int(_time / PLAYBOW_FRAME) % n
			pos.y = -absf(sin(_time * 5.0)) * 0.01 * h
		&"jump":
			var t_load: float = JUMP_STAND + JUMP_CROUCH
			var t_fly: float = t_load + JUMP_LOAD
			var t_land: float = t_fly + _jump_time
			if _action != &"jump":
				frame = 5
			elif t < JUMP_STAND:
				frame = 0
			elif t < t_load:
				frame = 1
			elif t < t_fly:
				frame = 2
				var c: float = _ease((t - t_load) / JUMP_LOAD)
				sy *= 1.0 - 0.08 * c
				sx *= 1.0 + 0.04 * c
			elif t < t_land:
				var u3: float = (t - t_fly) / _jump_time
				frame = 3 if u3 < 0.35 else 4
				_air_height = 4.0 * _jump_height * u3 * (1.0 - u3) + 0.12 * h
				pos.y = -4.0 * _jump_height * u3 * (1.0 - u3)
				rot = -0.14 * (1.0 - 2.0 * u3)
				sx *= 1.04
				sy *= 0.97
			else:
				frame = 5
				var lt: float = t - t_land
				var sq: float = 1.0 - _ease(clampf((lt - JUMP_SQUASH) / 0.2, 0.0, 1.0))
				if lt < JUMP_SQUASH:
					sq = _ease(lt / JUMP_SQUASH)
				sy *= 1.0 - 0.12 * sq
				sx *= 1.0 + 0.07 * sq
		&"sleep":
			# two breathing frames, slow
			frame = int(_time / 1.6) % n
			sy *= 1.0 + sin(_time * TAU * 0.2) * 0.014
		_:
			sy *= 1.0 + sin(_time * TAU * 0.28) * 0.012
	l.sprite.texture = l.frames[mini(frame, n - 1)]
	l.holder.position = Vector2(pos.x * flip, pos.y)
	l.holder.rotation = rot * flip
	l.holder.scale = Vector2(l.scale * sx * flip, l.scale * sy)


func _action_frame(times: Array[float], t: float) -> int:
	var acc: float = 0.0
	for i in times.size():
		acc += times[i]
		if t < acc:
			return i
	return times.size() - 1


func _weighted_frame(weights: Array[float], phase: float) -> int:
	var total: float = _sum(weights)
	var acc: float = 0.0
	for i in weights.size():
		acc += weights[i] / total
		if phase < acc:
			return i
	return weights.size() - 1


func _sum(a: Array[float]) -> float:
	var s: float = 0.0
	for v in a:
		s += v
	return s


func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
