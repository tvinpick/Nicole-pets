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
## in CatFrames.SETS. Every change of picture set is a short cross-fade of the whole cat.
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
		&"pose_sit", &"pose_lie", &"pose_sleep"]
## Body travel per 4-frame walk cycle (two steps), as a part of the cat height.
## Front/back keep the values that already looked right.
const CYCLE_SIDE := 0.75
const CYCLE_FRONTAL := 0.55
## Cross-fade lengths (s).
const FADE_VIEW := 0.24
const FADE_POSE := 0.45
const FADE_HAPPY := 0.35
const FADE_EAT := 0.3
const HAPPY_TIME := 2.6
## Shadow width per look, as a part of the cat height.
const SHADOW_W: Dictionary[StringName, float] = {
	&"walk_side": 0.95, &"walk_front": 0.6, &"walk_back": 0.6, &"eat_side": 0.9,
	&"happy_sit": 0.65, &"pose_sit": 0.7, &"pose_lie": 1.35, &"pose_sleep": 1.0,
}
## Head of the side picture relative to the body centre (part of the cat height):
## while mixing side and front/back pictures the frontal one is shifted towards it.
const HEAD_SHIFT := 0.21


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
var _fade_t: float = -1.0
var _fade_len: float = FADE_VIEW

var _time: float = 0.0
var _phase: float = 0.0
var _walk_weight: float = 0.0
var _pose_queue: Array[StringName] = []
var _pose_target: StringName = &""
var _happy_t: float = -1.0
var _eat_left: float = -1.0
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
	return _fade_t >= 0.0 or not _pose_queue.is_empty() \
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
	_happy_t = 0.0
	_set_look(&"happy_sit", FADE_HAPPY)


## Eats from the floor for `seconds` (cat_eat_side), then stands again.
func start_eating(seconds: float) -> void:
	if current_pose != POSE_STAND:
		return
	view = View.SIDE
	_eat_left = seconds
	_set_look(&"eat_side", FADE_EAT)


## Interrupts eating; returns the remaining eating time.
func stop_eating() -> float:
	if _eat_left < 0.0:
		return 0.0
	var left: float = _eat_left
	_eat_left = -1.0
	if _look == &"eat_side":
		_set_look(&"walk_side", FADE_EAT)
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
		_hearts.emitting = _happy_t > FADE_HAPPY and _happy_t < FADE_HAPPY + HAPPY_TIME - 0.4
		if _happy_t >= FADE_HAPPY + HAPPY_TIME and _look == &"happy_sit":
			_set_look(&"walk_side", FADE_HAPPY)
		elif _look == &"walk_side" and _fade_t < 0.0:
			_happy_t = -1.0
	else:
		_hearts.emitting = false
	if _eat_left >= 0.0:
		if _look == &"eat_side":
			_eat_left -= delta
			if _eat_left <= 0.0:
				_set_look(&"walk_side", FADE_EAT)
		elif _fade_t < 0.0:
			_eat_left = -1.0


func _update_poses() -> void:
	if _pose_queue.is_empty() or _pose_target != &"" or _fade_t >= 0.0 \
			or _happy_t >= 0.0 or _eat_left >= 0.0:
		return
	if current_pose == POSE_STAND and walk_velocity.length() > 1.0:
		return
	view = View.SIDE   # resting poses are side pictures (cross-fade from any view)
	_pose_target = _pose_queue.pop_front()
	_set_look(POSE_LOOK[_pose_target], FADE_POSE)


func _view_look(v: View) -> StringName:
	match v:
		View.FRONT:
			return &"walk_front"
		View.BACK:
			return &"walk_back"
	return &"walk_side"


func _set_look(look_name: StringName, fade: float) -> void:
	if look_name == _look and _fade_t < 0.0:
		return
	if fade <= 0.0:
		_look = look_name
		_look_from = &""
		_fade_t = -1.0
		_show_only(look_name)
		return
	if _fade_t >= 0.0 and _look_from != &"" and _look_from != look_name:
		_looks[_look_from].holder.visible = false
	_look_from = _look
	_look = look_name
	_fade_len = fade
	_fade_t = 0.0
	# the outgoing picture is drawn on top while it fades out
	move_child(_looks[_look_from].holder, -1)
	move_child(_hearts, -1)


func _show_only(look_name: StringName) -> void:
	for k: StringName in _looks.keys():
		var l: Look = _looks[k]
		l.holder.visible = k == look_name
		l.holder.modulate.a = 1.0


func _animate(delta: float) -> void:
	# cross-fade weights: the incoming picture appears underneath during the first 60%,
	# the outgoing one (on top) fades out during the last 60% -> no pop, never see-through
	var w_in: float = 1.0
	var w_out: float = 0.0
	if _fade_t >= 0.0:
		var t: float = clampf(_fade_t, 0.0, 1.0)
		w_in = _ease(clampf(t / 0.6, 0.0, 1.0))
		w_out = 1.0 - _ease(clampf((t - 0.4) / 0.6, 0.0, 1.0))
	# walking: frame rate follows the speed along the view's main axis
	var speed: float = 0.0
	match _look:
		&"walk_side":
			speed = absf(walk_velocity.x)
		&"walk_front", &"walk_back":
			speed = absf(walk_velocity.y)
	var walking: bool = speed > 1.0
	_walk_weight = move_toward(_walk_weight, 1.0 if walking else 0.0, delta * 6.0)
	if walking:
		var cycle: float = cat_height * (CYCLE_SIDE if _look == &"walk_side" else CYCLE_FRONTAL)
		_phase = fposmod(_phase + delta * speed / cycle, 1.0)
	else:
		_phase = 0.0   # standing = frame 1
	_pose_look(_look, w_in, true)
	if _fade_t >= 0.0 and _look_from != &"":
		_pose_look(_look_from, w_out, false)
	# shadow follows the picture's footprint
	var sw: float = SHADOW_W[_look]
	if _fade_t >= 0.0 and _look_from != &"":
		sw = lerpf(SHADOW_W[_look_from], sw, _ease(clampf(_fade_t, 0.0, 1.0)))
	_shadow.scale = Vector2(sw * cat_height / 128.0, 0.11 * cat_height / 128.0)
	_shadow.position = Vector2(0.0, -0.01 * cat_height)


func _pose_look(look_name: StringName, alpha: float, incoming: bool) -> void:
	var l: Look = _looks[look_name]
	l.holder.visible = alpha > 0.0
	l.holder.modulate.a = alpha
	var flip: float = facing if look_name in SIDE_LOOKS else 1.0
	var sy: float = l.scale
	var rot: float = 0.0
	var pos := Vector2.ZERO
	var frame: int = 0
	var breath: float = sin(_time * TAU * 0.3)
	match look_name:
		&"walk_side", &"walk_front", &"walk_back":
			var ww: float = _walk_weight if incoming else 0.0
			if ww > 0.0:
				frame = int(_phase * 4.0) % 4
			# light sway of the whole picture: bob on each step, roll per cycle
			var bob: float = -(0.5 - 0.5 * cos(_phase * TAU * 2.0)) * 7.0 * ww
			rot = sin(_phase * TAU) * (0.012 if look_name == &"walk_side" else 0.022) * ww
			pos.y = bob * l.scale
			sy *= 1.0 + breath * 0.008 * (1.0 - ww)
		&"eat_side":
			# 1-2-3-4: frames 2 and 4 are chewing
			frame = int(_time * 3.5) % 4
		&"happy_sit":
			# slow purring sway between the two pictures
			frame = int(_time / 0.7) % 2
			rot = sin(_time * 2.2) * 0.035
			sy *= 1.0 + breath * 0.01
		_:
			# finished poses: breathing only (slower when asleep)
			var b: float = sin(_time * TAU * (0.2 if look_name == &"pose_sleep" else 0.28))
			sy *= 1.0 + b * 0.012
	# keep the head roughly in place while mixing side and front/back pictures
	if _fade_t >= 0.0 and (look_name == &"walk_front" or look_name == &"walk_back"):
		var other: StringName = _look_from if incoming else _look
		if other in SIDE_LOOKS:
			var side_w: float = 1.0 - _ease(clampf(_fade_t, 0.0, 1.0))
			if not incoming:
				side_w = _ease(clampf(_fade_t, 0.0, 1.0))
			pos.x = facing * HEAD_SHIFT * cat_height * side_w
	l.sprite.texture = l.frames[frame]
	l.holder.position = pos
	l.holder.rotation = rot * flip
	l.holder.scale = Vector2(l.scale * flip, sy)


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
