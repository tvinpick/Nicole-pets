class_name CatRig
extends Node2D
## Cut-out side-view cat built from separate parts + finished poses (sit / lie / sleep).
##
## Rig space = pixel space of the parts sheet (side/*.png keep their source size),
## origin on the floor under the body, +x = forward (towards the nose), +y = down.
## Every body part is drawn twice: original sprite in the "outline pass" and a
## fill-only copy (tools/process_cat.py) in the "fill pass" of its group. The fill pass
## covers inner contours, so there are no visible lines at the knees, neck or tail base.

signal pose_changed(pose: StringName)

const SIDE_DIR := "res://assets/characters/cat/side/"
const FILL_DIR := "res://assets/characters/cat/rig/"
const POSE_DIR := "res://assets/characters/cat/pose/"

const OUTLINE_COLOR := Color8(88, 62, 62)
const FUR_COLOR := Color8(166, 144, 148)
const STRIPE_COLOR := Color8(124, 104, 110)
const CREAM_COLOR := Color8(248, 226, 214)

## rig px -> local px. The node itself is additionally scaled by the room depth.
@export var rig_scale: float = 0.33

const POSE_STAND := &"stand"
const POSE_SIT := &"sit"
const POSE_LIE := &"lie"
const POSE_SLEEP := &"sleep"
const POSE_ORDER: Array[StringName] = [&"stand", &"sit", &"lie", &"sleep"]


class Part:
	var outline: Sprite2D
	var fill: Sprite2D
	var pivot: Vector2
	var xf: Transform2D = Transform2D.IDENTITY

	## Converts a texture pixel of this part to rig space.
	func to_rig(tex_point: Vector2) -> Vector2:
		return xf * (tex_point - pivot)


class Leg:
	var upper: Part
	var paw: Part
	var joint_tex: Vector2          # joint position in the texture of the torso part
	var on_chest: bool
	var upper_attach: Vector2       # texture point of the upper part where the paw hangs
	var paw_sole: Vector2           # texture point of the paw touching the floor
	var phase_offset: float
	var rest_foot: Vector2          # rig-space foot position when standing
	var foot: Vector2               # current foot (sole) position, rig space
	var paw_rot: float = 0.0
	var settle_from: Vector2
	var settle_delay: float = 0.0


# --- layout (texture pixels of each part) ------------------------------------------
const HIPS_PIVOT := Vector2(165, 165)
const CHEST_PIVOT := Vector2(140, 160)
const HEAD_PIVOT := Vector2(170, 300)        # neck point on the head texture
const HIPS_POS := Vector2(-132, -272)
const CHEST_POS := Vector2(96, -268)
const HIPS_ROT := 0.09
const NECK_ON_CHEST := Vector2(196, 64)
const HEAD_OFFSET := Vector2(10, 10)         # head pivot relative to neck point (rig px)
const TAIL_BASE_ON_HIPS := Vector2(40, 72)

var _hips: Part
var _chest: Part
var _head: Part
var _ear_near: Part
var _ear_far: Part
var _legs: Array[Leg] = []
var _face_sprites: Array[Sprite2D] = []
var _eye: Sprite2D
var _mouth: Sprite2D
var _nose: Sprite2D
var _whiskers: Sprite2D
var _blush: Sprite2D
var _eye_tex: Dictionary[StringName, Texture2D] = {}
var _mouth_tex: Dictionary[StringName, Texture2D] = {}

var _group: CanvasGroup
var _tail_outline: Line2D
var _tail_fill: Line2D
var _pose_sprites: Dictionary[StringName, Sprite2D] = {}
var _shadow: Sprite2D

# --- animation state ------------------------------------------------------------------
var facing: float = 1.0                    # +1 looks right, -1 looks left
var _body_flip: float = 1.0
var _head_flip: float = 1.0
var _turn_t: float = -1.0
var _turn_from: float = 1.0
const TURN_TIME := 0.55

var walk_speed: float = 0.0                # rig px / s, set by the controller
var _walk_weight: float = 0.0
var _gait_phase: float = 0.0
var _settling: float = -1.0
const STRIDE := 120.0
const DUTY := 0.6
const STEP_LIFT := 34.0

var _time: float = 0.0
var _blink_timer: float = 2.0
var _blink_t: float = -1.0
var _ear_timer: float = 3.0
var _ear_t: float = -1.0
var _ear_which: int = 0
var _tail_flick_timer: float = 4.0
var _tail_flick_t: float = -1.0
var _happy_t: float = -1.0
const HAPPY_TIME := 2.4
var _look_t: float = 0.0
var _crouch: float = 0.0
var _head_tilt: float = 0.0
var _tail_up: float = 0.0

# pose (finished pictures) state
var current_pose: StringName = POSE_STAND
var _pose_queue: Array[StringName] = []
var _trans_from: StringName = &""
var _trans_to: StringName = &""
var _trans_t: float = -1.0
var _trans_len: float = 0.8

## per pose: scale relative to rig px, offset of the picture's bottom-centre anchor
## (rig px, unflipped) and the texture anchor x (pixels) that sits on that offset
## The texture anchor is the centre of the head in the picture; it is placed at the
## rig head x (HEAD_X), so the head stays in place while the body changes pose.
## Scales make the heads in the pictures as big as the rig head.
const HEAD_X := 179.0
const POSE_SETUP: Dictionary[StringName, Array] = {
	&"sit": [1.15, Vector2(HEAD_X, 0), 351.0],
	&"lie": [1.13, Vector2(HEAD_X, 0), 605.0],
	&"sleep": [1.05, Vector2(HEAD_X, 0), 411.0],
}
## visible extents per pose (rig px, facing right): x0, x1, height
const POSE_EXTENTS: Dictionary[StringName, Vector3] = {
	&"stand": Vector3(-420, 330, 860),
	&"sit": Vector3(-213, 343, 673),
	&"lie": Vector3(-492, 448, 506),
	&"sleep": Vector3(-241, 388, 401),
}


func _ready() -> void:
	_build()
	_update_rig(0.0)


func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D


func _make_part(file: String, pivot: Vector2, with_fill: bool) -> Part:
	var p := Part.new()
	p.pivot = pivot
	p.outline = Sprite2D.new()
	p.outline.texture = _tex(SIDE_DIR + file + ".png")
	p.outline.centered = false
	p.outline.offset = -pivot
	p.outline.name = file
	if with_fill:
		p.fill = Sprite2D.new()
		p.fill.texture = _tex(FILL_DIR + file + "_fill.png")
		p.fill.centered = false
		p.fill.offset = -pivot
		p.fill.name = file + "_fill"
	return p


func _make_leg(prefix: String, upper_pivot: Vector2, attach: Vector2, paw_pivot: Vector2,
		sole: Vector2, joint_tex: Vector2, on_chest: bool, phase: float) -> Leg:
	var l := Leg.new()
	l.upper = _make_part(prefix + "_upper", upper_pivot, true)
	l.paw = _make_part(prefix + "_paw", paw_pivot, true)
	l.upper_attach = attach
	l.paw_sole = sole
	l.joint_tex = joint_tex
	l.on_chest = on_chest
	l.phase_offset = phase
	return l


func _add_group_pass(parent: Node, parts: Array[Part]) -> void:
	for p in parts:
		parent.add_child(p.outline)
	for p in parts:
		if p.fill:
			parent.add_child(p.fill)


func _build() -> void:
	# shadow (not part of the rig group, never flipped)
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

	# finished poses, drawn below the rig group
	for pose_name: StringName in POSE_SETUP.keys():
		var s := Sprite2D.new()
		s.name = "Pose_" + str(pose_name)
		s.texture = _tex(POSE_DIR + "pose_" + str(pose_name) + ".png")
		s.centered = false
		var anchor_x: float = POSE_SETUP[pose_name][2]
		s.offset = Vector2(-anchor_x, -float(s.texture.get_height()) + 10.0)
		s.visible = false
		add_child(s)
		_pose_sprites[pose_name] = s

	_group = CanvasGroup.new()
	_group.name = "Rig"
	_group.fit_margin = 4.0
	add_child(_group)

	_hips = _make_part("side_hips_alternate", HIPS_PIVOT, true)
	_chest = _make_part("side_chest_alternate", CHEST_PIVOT, true)
	_head = _make_part("side_head", HEAD_PIVOT, true)
	_ear_near = _make_part("side_ear_near", Vector2(60, 200), true)
	_ear_far = _make_part("side_ear_far", Vector2(120, 165), true)

	# legs: textures were measured by tools/process_cat.py (rig/anchors.json)
	var hind_far := _make_leg("side_hind_far", Vector2(112, 72), Vector2(64, 232),
			Vector2(66, 34), Vector2(96, 160), Vector2(78, 205), false, 0.5)
	var front_far := _make_leg("side_front_far", Vector2(88, 56), Vector2(60, 212),
			Vector2(60, 34), Vector2(95, 161), Vector2(200, 225), true, 0.75)
	var hind_near := _make_leg("side_hind_near", Vector2(118, 74), Vector2(70, 236),
			Vector2(72, 34), Vector2(92, 165), Vector2(118, 215), false, 0.0)
	var front_near := _make_leg("side_front_near", Vector2(96, 56), Vector2(64, 214),
			Vector2(62, 34), Vector2(93, 165), Vector2(150, 230), true, 0.25)
	_legs = [hind_near, front_near, hind_far, front_far]

	# tail: smooth bendable strip (two Line2D: contour + fill)
	_tail_outline = _make_tail_line(true)
	_tail_fill = _make_tail_line(false)

	# draw order (back -> front), each group = outline pass then fill pass
	_add_group_pass(_group, [hind_far.upper, hind_far.paw, front_far.upper, front_far.paw])
	_group.add_child(_tail_outline)
	_add_group_pass(_group, [_hips, _chest])
	# tail fill must be under the hips fill: put it right after the chest outline sprite
	_group.add_child(_tail_fill)
	_group.move_child(_tail_fill, _chest.outline.get_index() + 1)
	_add_group_pass(_group, [hind_near.upper, hind_near.paw])
	_add_group_pass(_group, [front_near.upper, front_near.paw])
	_add_group_pass(_group, [_ear_far, _ear_near, _head])

	# face
	for k: StringName in [&"open", &"half", &"closed", &"happy"]:
		_eye_tex[k] = _tex(SIDE_DIR + "side_eye_" + str(k) + "_near.png")
	for k: StringName in [&"closed", &"smile", &"open"]:
		_mouth_tex[k] = _tex(SIDE_DIR + "side_mouth_" + str(k) + ".png")
	_blush = _face_sprite("side_blush_near", Vector2(57, 48))
	_whiskers = _face_sprite("side_whiskers_near", Vector2(30, 40))
	_eye = _face_sprite("side_eye_open_near", Vector2(54, 52))
	_nose = _face_sprite("side_nose", Vector2(40, 32))
	_mouth = _face_sprite("side_mouth_closed", Vector2(46, 24))

	for l in _legs:
		l.foot = Vector2.ZERO
	_compute_rest_feet()


func _face_sprite(file: String, pivot: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _tex(SIDE_DIR + file + ".png")
	s.centered = false
	s.offset = -pivot
	s.name = file
	_group.add_child(s)
	_face_sprites.append(s)
	return s


func _make_tail_line(is_outline: bool) -> Line2D:
	var line := Line2D.new()
	line.name = "TailOutline" if is_outline else "TailFill"
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.texture_mode = Line2D.LINE_TEXTURE_NONE
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.4, 0.8))
	c.add_point(Vector2(0.78, 0.92))
	c.add_point(Vector2(0.92, 0.95))
	c.add_point(Vector2(1.0, 0.7))
	line.width_curve = c
	if is_outline:
		line.width = 74.0 + 13.0
		line.default_color = OUTLINE_COLOR
	else:
		line.width = 74.0
		var gr := Gradient.new()
		gr.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
		var stops: Array = [
			[0.0, FUR_COLOR], [0.14, FUR_COLOR], [0.17, STRIPE_COLOR], [0.23, STRIPE_COLOR],
			[0.26, FUR_COLOR], [0.36, FUR_COLOR], [0.39, STRIPE_COLOR], [0.45, STRIPE_COLOR],
			[0.48, FUR_COLOR], [0.57, FUR_COLOR], [0.60, STRIPE_COLOR], [0.65, STRIPE_COLOR],
			[0.68, FUR_COLOR], [0.76, FUR_COLOR], [0.83, CREAM_COLOR], [1.0, CREAM_COLOR],
		]
		gr.offsets = PackedFloat32Array()
		gr.colors = PackedColorArray()
		for st: Array in stops:
			gr.add_point(st[0], st[1])
		line.gradient = gr
	return line


func _compute_rest_feet() -> void:
	_pose_torso(0.0)
	for l in _legs:
		var j: Vector2 = _joint_rig(l)
		var v: Vector2 = l.upper_attach - l.upper.pivot
		var sole: Vector2 = l.paw_sole - l.paw.pivot
		l.rest_foot = Vector2(j.x + v.x + sole.x, 0.0)
		l.foot = l.rest_foot


func _joint_rig(l: Leg) -> Vector2:
	return (_chest if l.on_chest else _hips).to_rig(l.joint_tex)


# --- public API -------------------------------------------------------------------------

func is_busy() -> bool:
	return _turn_t >= 0.0 or _trans_t >= 0.0 or not _pose_queue.is_empty()


func is_turning() -> bool:
	return _turn_t >= 0.0


func turn_to(dir: float) -> void:
	if signf(dir) == facing or _turn_t >= 0.0:
		return
	_turn_from = facing
	facing = signf(dir)
	_turn_t = 0.0


func set_pose(target: StringName) -> void:
	## Goes through intermediate poses (stand <-> sit <-> lie <-> sleep).
	_pose_queue.clear()
	var from_i: int = POSE_ORDER.find(_trans_to if _trans_t >= 0.0 else current_pose)
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


func is_happy() -> bool:
	return _happy_t >= 0.0


func make_happy() -> void:
	_happy_t = 0.0


## Bounding box of the visible cat in this node's local space.
func hit_rect() -> Rect2:
	var e: Vector3 = POSE_EXTENTS[current_pose]
	var x0: float = e.x if facing > 0.0 else -e.y
	var x1: float = e.y if facing > 0.0 else -e.x
	return Rect2(x0 * rig_scale, -e.z * rig_scale, (x1 - x0) * rig_scale, e.z * rig_scale)


# --- per-frame update ---------------------------------------------------------------

func _process(delta: float) -> void:
	_update_rig(delta)


func _update_rig(delta: float) -> void:
	_time += delta
	_update_timers(delta)
	_update_pose_transition(delta)

	# walking blend
	var walking: bool = walk_speed > 1.0
	_walk_weight = move_toward(_walk_weight, 1.0 if walking else 0.0, delta * 5.0)
	if walking:
		_gait_phase = fposmod(_gait_phase + delta * DUTY * walk_speed / STRIDE, 1.0)
		_settling = -1.0
	elif _walk_weight <= 0.0 and _settling < 0.0 and _feet_need_settle():
		_start_settle()

	# turning: head leads, body follows
	if _turn_t >= 0.0:
		_turn_t += delta / TURN_TIME
		_head_flip = _flip_value(clampf(_turn_t / 0.55, 0.0, 1.0))
		_body_flip = _flip_value(clampf((_turn_t - 0.3) / 0.7, 0.0, 1.0))
		if _turn_t >= 1.0:
			_turn_t = -1.0
			_head_flip = facing
			_body_flip = facing
	else:
		_head_flip = facing
		_body_flip = facing

	var turn_squash: float = 0.0
	if _turn_t >= 0.0:
		turn_squash = sin(clampf(_turn_t, 0.0, 1.0) * PI)

	_pose_torso(turn_squash)
	_pose_head()
	_pose_legs(delta)
	_pose_tail()
	_apply()


## Turning: squash to a narrow silhouette, swap side, unsquash (never paper-thin).
func _flip_value(p: float) -> float:
	const NARROW := 0.3
	if p < 0.5:
		return _turn_from * lerpf(1.0, NARROW, _ease(p * 2.0))
	return facing * lerpf(NARROW, 1.0, _ease((p - 0.5) * 2.0))


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _update_timers(delta: float) -> void:
	# blinking
	_blink_timer -= delta
	if _blink_timer <= 0.0 and _blink_t < 0.0:
		_blink_t = 0.0
		_blink_timer = randf_range(2.0, 5.5)
	if _blink_t >= 0.0:
		_blink_t += delta / 0.18
		if _blink_t >= 1.0:
			_blink_t = -1.0
			if randf() < 0.2:
				_blink_timer = 0.25  # double blink
	# ear twitch
	_ear_timer -= delta
	if _ear_timer <= 0.0 and _ear_t < 0.0:
		_ear_t = 0.0
		_ear_which = randi() % 2
		_ear_timer = randf_range(3.0, 8.0)
	if _ear_t >= 0.0:
		_ear_t += delta / 0.45
		if _ear_t >= 1.0:
			_ear_t = -1.0
	# tail flick
	_tail_flick_timer -= delta
	if _tail_flick_timer <= 0.0 and _tail_flick_t < 0.0:
		_tail_flick_t = 0.0
		_tail_flick_timer = randf_range(4.0, 9.0)
	if _tail_flick_t >= 0.0:
		_tail_flick_t += delta / 0.9
		if _tail_flick_t >= 1.0:
			_tail_flick_t = -1.0
	# happy
	if _happy_t >= 0.0:
		_happy_t += delta / HAPPY_TIME
		if _happy_t >= 1.0:
			_happy_t = -1.0
	var happy_w: float = 0.0
	if _happy_t >= 0.0:
		happy_w = clampf(minf(_happy_t * 6.0, (1.0 - _happy_t) * 4.0), 0.0, 1.0)
	_tail_up = move_toward(_tail_up, happy_w, delta * 4.0)


func _pose_torso(turn_squash: float) -> void:
	var breath: float = sin(_time * TAU * 0.32)
	var walk_bob: float = 0.0
	if _walk_weight > 0.0:
		walk_bob = -absf(sin(_gait_phase * TAU * 2.0)) * 5.0 * _walk_weight
	var hop: float = 0.0
	if _happy_t >= 0.0:
		var ht: float = _happy_t * 2.0
		if ht < 1.0:
			hop = -absf(sin(ht * TAU)) * 26.0
	var crouch_y: float = _crouch * 40.0 + turn_squash * 14.0
	var hips_y: float = HIPS_POS.y + walk_bob + hop + crouch_y * 1.3
	var chest_y: float = CHEST_POS.y + walk_bob * 0.8 + hop + crouch_y * 0.7
	# breathing: torso slightly expands, hips/chest stay attached
	var bs: float = 1.0 + breath * 0.012
	var tilt: float = deg_to_rad(-3.0) * _crouch
	_hips.xf = Transform2D(tilt + HIPS_ROT, Vector2(1.0, bs), 0.0, Vector2(HIPS_POS.x, hips_y))
	_chest.xf = Transform2D(tilt * 0.5 + breath * 0.004, Vector2(1.0 + breath * 0.006, bs),
			0.0, Vector2(CHEST_POS.x, chest_y))


func _pose_head() -> void:
	var neck: Vector2 = _chest.to_rig(NECK_ON_CHEST)
	_look_t += get_process_delta_time()
	var idle_tilt: float = sin(_time * 0.7) * 0.03 + sin(_time * 0.23) * 0.04
	var target_tilt: float = idle_tilt * (1.0 - _walk_weight) + sin(_gait_phase * TAU * 2.0) * 0.015 * _walk_weight
	if _happy_t >= 0.0:
		target_tilt = -0.12 + sin(_time * 9.0) * 0.05
	_head_tilt = lerpf(_head_tilt, target_tilt, 0.15)
	_head.xf = Transform2D(_head_tilt, Vector2.ONE, 0.0, neck + HEAD_OFFSET)
	# ears
	var twitch: float = 0.0
	if _ear_t >= 0.0:
		twitch = sin(_ear_t * PI * 3.0) * (1.0 - _ear_t) * 0.35
	var perk: float = -0.08 * _tail_up
	var near_rot: float = (twitch if _ear_which == 0 else 0.0) + perk
	var far_rot: float = (twitch * 0.8 if _ear_which == 1 else 0.0) + perk
	_ear_near.xf = _head.xf * Transform2D(near_rot, Vector2.ONE, 0.0, Vector2(150, 72) - HEAD_PIVOT)
	_ear_far.xf = _head.xf * Transform2D(far_rot, Vector2.ONE, 0.0, Vector2(262, 58) - HEAD_PIVOT)


func _pose_legs(delta: float) -> void:
	if _settling >= 0.0:
		_settling += delta / 0.5
	for l in _legs:
		var target: Vector2 = l.rest_foot
		var paw_rot: float = 0.0
		if _walk_weight > 0.0:
			var ph: float = fposmod(_gait_phase + l.phase_offset, 1.0)
			var gait_foot: Vector2
			if ph < DUTY:
				var u: float = ph / DUTY
				gait_foot = Vector2(l.rest_foot.x + STRIDE * 0.5 - STRIDE * u, 0.0)
			else:
				var u2: float = (ph - DUTY) / (1.0 - DUTY)
				var e: float = _ease(u2)
				gait_foot = Vector2(l.rest_foot.x - STRIDE * 0.5 + STRIDE * e, -sin(u2 * PI) * STEP_LIFT)
				paw_rot = sin(u2 * PI) * 0.35
			target = l.rest_foot.lerp(gait_foot, _walk_weight)
			paw_rot *= _walk_weight
			l.foot = target
		elif _settling >= 0.0:
			var st: float = clampf((_settling - l.settle_delay) / 0.55, 0.0, 1.0)
			var e2: float = _ease(st)
			l.foot = l.settle_from.lerp(l.rest_foot, e2)
			if l.settle_from.distance_to(l.rest_foot) > 4.0:
				l.foot.y -= sin(st * PI) * STEP_LIFT * 0.6
				paw_rot = sin(st * PI) * 0.25
			if _settling >= 1.0:
				l.foot = l.rest_foot
		else:
			l.foot = l.foot.lerp(l.rest_foot, clampf(delta * 10.0, 0.0, 1.0)) if l.foot.y < -0.5 else l.foot
		l.paw_rot = paw_rot
		_solve_leg(l)
	if _settling >= 1.0:
		_settling = -1.0


func _feet_need_settle() -> bool:
	for l in _legs:
		if l.foot.distance_to(l.rest_foot) > 2.0:
			return true
	return false


func _start_settle() -> void:
	_settling = 0.0
	var order: int = 0
	for l in _legs:
		l.settle_from = l.foot
		l.settle_delay = 0.12 * order
		order += 1


func _solve_leg(l: Leg) -> void:
	var j: Vector2 = _joint_rig(l)
	var sole_off: Vector2 = (l.paw_sole - l.paw.pivot).rotated(l.paw_rot)
	var ankle: Vector2 = l.foot - sole_off
	var d: Vector2 = ankle - j
	var v: Vector2 = l.upper_attach - l.upper.pivot
	var s: float = sqrt(maxf(d.length_squared() - v.x * v.x, 1.0)) / absf(v.y)
	s = clampf(s, 0.72, 1.18)
	var vs := Vector2(v.x, v.y * s)
	var theta: float = d.angle() - vs.angle()
	l.upper.xf = Transform2D(theta, Vector2(1.0, s), 0.0, j)
	var attach: Vector2 = l.upper.xf * v
	l.paw.xf = Transform2D(l.paw_rot, Vector2.ONE, 0.0, attach)


func _pose_tail() -> void:
	var base: Vector2 = _hips.to_rig(TAIL_BASE_ON_HIPS)
	var n: int = 18
	var seg: float = 340.0 / float(n)
	var ang: float = deg_to_rad(-150.0)  # pointing back and up
	var sway: float = sin(_time * 1.3) * 0.5 + sin(_time * 0.53) * 0.5
	var flick: float = 0.0
	if _tail_flick_t >= 0.0:
		flick = sin(_tail_flick_t * TAU) * (1.0 - _tail_flick_t)
	var walk_w: float = _walk_weight
	var pts := PackedVector2Array()
	pts.append(base)
	var p: Vector2 = base
	for i in n:
		var t: float = float(i) / float(n - 1)
		# idle: tail rises then curls back towards the tip; wave travels to the tip
		var curl_idle: float = 0.10 + 0.05 * sin(_time * 1.1 - t * 3.0) * sway
		var curl_walk: float = 0.07 + 0.03 * sin(_gait_phase * TAU * 2.0 - t * 4.0)
		var curl_happy: float = 0.02 + (0.22 if t > 0.7 else 0.0) + 0.03 * sin(_time * 8.0 - t * 5.0)
		var curl: float = lerpf(curl_idle, curl_walk, walk_w)
		curl = lerpf(curl, curl_happy, _tail_up)
		curl += flick * 0.12 * t
		if i == 0:
			ang += lerpf(0.55, 0.85, _tail_up) * (1.0 - walk_w * 0.3)
		ang += curl
		p += Vector2.from_angle(ang) * seg
		pts.append(p)
	# points go from the base to the tip: the cream tip is at the gradient end
	_tail_outline.points = pts
	_tail_fill.points = pts


func _apply() -> void:
	var flip_body := Transform2D(Vector2(_body_flip, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	var neck: Vector2 = _head.xf.origin
	var head_xf := Transform2D(0.0, Vector2(_head_flip, 1.0), 0.0, flip_body * neck) \
			* Transform2D(0.0, Vector2.ONE, 0.0, -neck)
	var body_parts: Array[Part] = [_hips, _chest]
	for l in _legs:
		body_parts.append(l.upper)
		body_parts.append(l.paw)
	for p in body_parts:
		_set_part(p, flip_body * p.xf)
	for p: Part in [_head, _ear_near, _ear_far]:
		_set_part(p, head_xf * p.xf)
	# face features in head space
	var eye_key: StringName = &"open"
	if _happy_t >= 0.0:
		eye_key = &"happy"
	elif _blink_t >= 0.0:
		eye_key = &"half" if (_blink_t < 0.3 or _blink_t > 0.7) else &"closed"
	_eye.texture = _eye_tex[eye_key]
	_mouth.texture = _mouth_tex[&"smile" if _happy_t >= 0.0 else &"closed"]
	var hx: Transform2D = head_xf * _head.xf
	_eye.transform = hx * Transform2D(0.0, Vector2.ONE, 0.0, Vector2(286, 182) - HEAD_PIVOT)
	_nose.transform = hx * Transform2D(0.0, Vector2(0.9, 0.9), 0.0, Vector2(352, 214) - HEAD_PIVOT)
	_mouth.transform = hx * Transform2D(0.0, Vector2(0.85, 0.85), 0.0, Vector2(328, 256) - HEAD_PIVOT)
	_whiskers.transform = hx * Transform2D(0.0, Vector2(0.95, 0.95), 0.0, Vector2(300, 240) - HEAD_PIVOT)
	_blush.transform = hx * Transform2D(0.0, Vector2.ONE, 0.0, Vector2(276, 240) - HEAD_PIVOT)
	_blush.modulate.a = 0.55 + 0.45 * _tail_up
	# tail
	var tail_pts := PackedVector2Array()
	for q in _tail_fill.points:
		tail_pts.append(flip_body * q)
	_tail_outline.points = tail_pts
	_tail_fill.points = tail_pts
	_group.scale = Vector2.ONE * rig_scale
	# shadow follows the visible pose (blended during transitions)
	var e: Vector3 = POSE_EXTENTS[current_pose]
	if _trans_t >= 0.0:
		var e2: Vector3 = POSE_EXTENTS[_trans_to]
		e = e.lerp(e2, _ease(clampf(_trans_t, 0.0, 1.0)))
	var sw: float = (e.y - e.x) * 0.95
	var cx: float = (e.x + e.y) * 0.5 * facing
	_shadow.scale = Vector2(sw * rig_scale / 128.0, 70.0 * rig_scale / 128.0)
	_shadow.position = Vector2(cx * rig_scale, -4.0 * rig_scale)


func _set_part(p: Part, xf: Transform2D) -> void:
	p.outline.transform = xf
	if p.fill:
		p.fill.transform = xf


# --- finished poses: cross-fade with the rig ------------------------------------------

func _update_pose_transition(delta: float) -> void:
	if _trans_t < 0.0:
		if _pose_queue.is_empty() or _turn_t >= 0.0:
			_refresh_pose_visuals(current_pose, 1.0)
			return
		if current_pose == POSE_STAND and (_walk_weight > 0.0 or _settling >= 0.0):
			_refresh_pose_visuals(current_pose, 1.0)
			return
		_trans_from = current_pose
		_trans_to = _pose_queue.pop_front()
		_trans_t = 0.0
		_trans_len = 0.9 if (_trans_from == POSE_STAND or _trans_to == POSE_STAND) else 1.1
	_trans_t += delta / _trans_len
	var t: float = clampf(_trans_t, 0.0, 1.0)
	if _trans_t >= 1.0:
		current_pose = _trans_to
		_trans_t = -1.0
		_crouch = 1.0 if current_pose != POSE_STAND else 0.0
		_refresh_pose_visuals(current_pose, 1.0)
		pose_changed.emit(current_pose)
		return
	# rig crouches before fading into a picture, rises after fading out of it
	if _trans_from == POSE_STAND:
		_crouch = _ease(clampf(t / 0.5, 0.0, 1.0))
	elif _trans_to == POSE_STAND:
		_crouch = 1.0 - _ease(clampf((t - 0.45) / 0.55, 0.0, 1.0))
	_blend_poses(_trans_from, _trans_to, t)


func _blend_poses(a: StringName, b: StringName, t: float) -> void:
	# the incoming picture fades in BEHIND the outgoing one, then the outgoing fades out:
	# no moment where the cat becomes see-through.
	for k: StringName in _pose_sprites.keys():
		_pose_sprites[k].visible = false
	# fade windows: [in_start, in_end] for the incoming, [out_start, out_end] outgoing
	var w := Vector4(0.1, 0.5, 0.5, 0.9)
	if a == POSE_STAND:
		w = Vector4(0.3, 0.55, 0.55, 0.8)   # rig crouches first, then the picture
	elif b == POSE_STAND:
		w = Vector4(0.1, 0.35, 0.35, 0.6)   # rig appears crouched, then stands up
	var in_a: float = _ease(clampf((t - w.x) / (w.y - w.x), 0.0, 1.0))
	var out_b: float = 1.0 - _ease(clampf((t - w.z) / (w.w - w.z), 0.0, 1.0))
	_show_pose(b, in_a, t, true)
	_show_pose(a, out_b, t, false)
	# draw order: outgoing on top
	if a != POSE_STAND and b != POSE_STAND:
		move_child(_pose_sprites[a], _group.get_index() - 1)


func _show_pose(p: StringName, alpha: float, t: float, incoming: bool) -> void:
	if p == POSE_STAND:
		_group.visible = alpha > 0.0
		_group.modulate.a = alpha
		return
	var s: Sprite2D = _pose_sprites[p]
	s.visible = alpha > 0.0
	s.modulate.a = alpha
	_place_pose_sprite(p, t if incoming else 1.0 + t, incoming)


func _place_pose_sprite(p: StringName, t: float, incoming: bool) -> void:
	var s: Sprite2D = _pose_sprites[p]
	var setup: Array = POSE_SETUP[p]
	var sc: float = float(setup[0]) * rig_scale
	var off: Vector2 = setup[1]
	var breath: float = 1.0 + sin(_time * TAU * (0.22 if p == POSE_SLEEP else 0.3)) * 0.012
	# while fading in, the picture settles down a little (sinks into the pose)
	var settle: float = 1.0
	if incoming:
		settle = lerpf(1.04, 1.0, clampf(t, 0.0, 1.0))
	else:
		settle = lerpf(1.0, 0.97, clampf(t - 1.0, 0.0, 1.0))
	s.scale = Vector2(sc * facing, sc * breath * settle)
	s.position = Vector2(off.x * facing, off.y) * rig_scale


func _refresh_pose_visuals(p: StringName, _alpha: float) -> void:
	for k: StringName in _pose_sprites.keys():
		var s: Sprite2D = _pose_sprites[k]
		s.visible = k == p
		if s.visible:
			s.modulate.a = 1.0
			_place_pose_sprite(k, 1.0, true)
	_group.visible = p == POSE_STAND
	_group.modulate.a = 1.0
