class_name CatFrontalRig
extends CanvasGroup
## Front view (cat walks towards the viewer) or back view (walks away, towards the wall),
## built from front/ or back/ parts the same way as the side rig: every part is drawn
## in an outline pass and a fill pass per group, so joints have no seams.
##
## Rig units = pixels of the parts sheet; origin on the floor under the body; y down.
## Gait: diagonal pairs (left front + right hind), paws planted on the floor while
## the body moves in depth, i.e. a planted paw moves on screen by exactly the body speed.

const FRONT_DIR := "res://assets/characters/cat/front/"
const BACK_DIR := "res://assets/characters/cat/back/"
const FILL_DIR := "res://assets/characters/cat/rig/"

const STRIDE := 120.0      # rig px a planted paw travels (relative to the body) per cycle
const DUTY := 0.56
const STEP_LIFT := 34.0


class Piece:
	var outline: Sprite2D
	var fill: Sprite2D
	var rest: Vector2           # rig position of the pivot
	var size: Vector2

	func set_xf(xf: Transform2D) -> void:
		outline.transform = xf
		if fill:
			fill.transform = xf


class Leg:
	var upper: Piece             # may be null (hidden upper part)
	var paw: Piece
	var upper_len: float
	var overlap: float
	var phase: float
	var lift_scale: float        # paw grows (front view) when it swings towards the viewer
	var foot: Vector2            # paw pivot (top centre) relative to rest, rig px
	var paw_rot: float = 0.0


var is_back: bool = false
var stand_height: float = 860.0
var walk_speed: float = 0.0           ## rig px/s of depth movement (set by CatRig)
var _walk_weight: float = 0.0
var _phase: float = 0.0
var _time: float = 0.0

var _body: Array[Piece] = []          # pieces that follow the body sway
var _head: Array[Piece] = []          # head + ears + tufts (extra head motion)
var _ears: Array[Piece] = []
var _legs: Array[Leg] = []
var _face: Array[Sprite2D] = []
var _face_rest: Array[Vector2] = []
var _eyes: Sprite2D
var _mouth: Sprite2D
var _blush: Array[Sprite2D] = []
var _eye_tex: Dictionary[StringName, Texture2D] = {}
var _mouth_tex: Dictionary[StringName, Texture2D] = {}
var _tail_outline: Line2D
var _tail_fill: Line2D
var _tail_base: Vector2
var _dir: String


func setup(back: bool, tail_outline: Line2D, tail_fill: Line2D) -> void:
	is_back = back
	_dir = BACK_DIR if back else FRONT_DIR
	_tail_outline = tail_outline
	_tail_fill = tail_fill
	fit_margin = 4.0
	if back:
		_build_back()
	else:
		_build_front()


func _piece(file: String, centre: Vector2, pivot_mode: int = 0, flip: bool = false) -> Piece:
	## pivot_mode: 0 = centre, 1 = top centre, 2 = bottom centre
	var p := Piece.new()
	var tex: Texture2D = load(_dir + file + ".png")
	p.size = tex.get_size()
	var pivot := p.size * 0.5
	if pivot_mode == 1:
		pivot.y = 0.0
	elif pivot_mode == 2:
		pivot.y = p.size.y
	p.rest = centre + (pivot - p.size * 0.5)
	p.outline = Sprite2D.new()
	p.outline.texture = tex
	p.outline.centered = false
	p.outline.offset = -pivot
	p.outline.flip_h = flip
	var fill_path: String = FILL_DIR + file + "_fill.png"
	if ResourceLoader.exists(fill_path):
		p.fill = Sprite2D.new()
		p.fill.texture = load(fill_path)
		p.fill.centered = false
		p.fill.offset = -pivot
		p.fill.flip_h = flip
	return p


func _group_pass(parts: Array[Piece]) -> void:
	for p in parts:
		add_child(p.outline)
	for p in parts:
		if p.fill:
			add_child(p.fill)


func _leg(upper: Piece, paw: Piece, phase: float, lift_scale: float) -> Leg:
	var l := Leg.new()
	l.upper = upper
	l.paw = paw
	l.phase = phase
	l.lift_scale = lift_scale
	if upper:
		l.upper_len = upper.size.y
		l.overlap = (upper.rest.y + upper.size.y) - paw.rest.y
	_legs.append(l)
	return l


func _face_sprite(file: String, centre: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(_dir + file + ".png")
	add_child(s)
	s.position = centre
	_face.append(s)
	_face_rest.append(centre)
	return s


# --- front view: positions measured on the front/ sheet (see tools/process_cat.py) ---------

func _build_front() -> void:
	stand_height = 859.0
	_tail_base = Vector2(70, -330)
	var hind_l := _piece("front_hind_near_paw", Vector2(-132, -104), 1)
	var hind_r := _piece("front_hind_far_paw", Vector2(132, -103), 1, true)
	var up_l := _piece("front_front_near_upper", Vector2(-58, -284), 1)
	var up_r := _piece("front_front_far_upper", Vector2(58, -284), 1)
	var paw_l := _piece("front_front_near_paw", Vector2(-64, -88), 1)
	var paw_r := _piece("front_front_far_paw", Vector2(64, -88), 1)
	var chest := _piece("front_chest", Vector2(0, -369.5))
	var ear_l := _piece("front_ear_near", Vector2(-112, -756), 2)
	var ear_r := _piece("front_ear_far", Vector2(112, -757), 2)
	var head := _piece("front_head", Vector2(0, -641.5))

	add_child(_tail_outline)
	add_child(_tail_fill)
	_group_pass([hind_l, hind_r])
	_group_pass([up_l, up_r, paw_l, paw_r, chest])
	_group_pass([ear_l, ear_r, head])
	# diagonal pairs: left front + right hind, right front + left hind
	_leg(up_l, paw_l, 0.0, 0.07)
	_leg(null, hind_r, 0.03, 0.04)
	_leg(up_r, paw_r, 0.5, 0.07)
	_leg(null, hind_l, 0.53, 0.04)
	_body = [chest]
	_head = [head, ear_l, ear_r]
	_ears = [ear_l, ear_r]

	_blush.append(_face_sprite("front_blush_near", Vector2(-95, -555)))
	_blush.append(_face_sprite("front_blush_far", Vector2(95, -555)))
	_eyes = _face_sprite("front_eyes_open", Vector2(0, -650.5))
	_face_sprite("front_whiskers_near", Vector2(-125, -556))
	_face_sprite("front_whiskers_far", Vector2(125, -556.5))
	_face_sprite("front_nose", Vector2(0, -584.5))
	_mouth = _face_sprite("front_mouth_closed", Vector2(0, -546))
	for k: StringName in [&"open", &"half", &"closed", &"happy"]:
		_eye_tex[k] = load(FRONT_DIR + "front_eyes_" + str(k) + ".png")
	for k: StringName in [&"closed", &"smile"]:
		_mouth_tex[k] = load(FRONT_DIR + "front_mouth_" + str(k) + ".png")


# --- back view -------------------------------------------------------------------------

func _build_back() -> void:
	stand_height = 905.0
	_tail_base = Vector2(0, -585)
	var fpaw_l := _piece("back_front_near_paw", Vector2(-58, -150), 1)
	var fpaw_r := _piece("back_front_far_paw", Vector2(58, -150), 1)
	var ear_l := _piece("back_ear_near", Vector2(-112, -800), 2)
	var ear_r := _piece("back_ear_far", Vector2(112, -800), 2)
	var tuft_l := _piece("back_cheek_tuft_near", Vector2(-175, -560))
	var tuft_r := _piece("back_cheek_tuft_far", Vector2(175, -560))
	var head := _piece("back_head", Vector2(0, -640))
	var thigh_l := _piece("back_hind_near_upper", Vector2(-108, -400), 1)
	var thigh_r := _piece("back_hind_far_upper", Vector2(108, -400), 1)
	var hpaw_l := _piece("back_hind_near_paw", Vector2(-100, -138), 1)
	var hpaw_r := _piece("back_hind_far_paw", Vector2(100, -138), 1)
	var hips := _piece("back_hips", Vector2(0, -420))

	_group_pass([fpaw_l, fpaw_r])
	_group_pass([ear_l, ear_r, tuft_l, tuft_r, head])
	# tail rises from the rump in front of the back/head; merged with the hips group
	add_child(_tail_outline)
	for p: Piece in [thigh_l, thigh_r, hpaw_l, hpaw_r, hips]:
		add_child(p.outline)
	add_child(_tail_fill)
	for p: Piece in [thigh_l, thigh_r, hpaw_l, hpaw_r, hips]:
		add_child(p.fill)
	# from behind: left hind pairs with right front
	_leg(thigh_l, hpaw_l, 0.0, -0.05)
	_leg(null, fpaw_r, 0.03, -0.03)
	_leg(thigh_r, hpaw_r, 0.5, -0.05)
	_leg(null, fpaw_l, 0.53, -0.03)
	_body = [hips]
	_head = [head, ear_l, ear_r, tuft_l, tuft_r]
	_ears = [ear_l, ear_r]


# --- animation ---------------------------------------------------------------------------

## eye: &"open"/&"half"/&"closed"/&"happy"; ear_twitch: radians; happy 0..1
func animate(delta: float, eye: StringName, ear_twitch: float, ear_which: int, happy: float,
		tail_flick: float) -> void:
	_time += delta
	var walking: bool = walk_speed > 1.0
	_walk_weight = move_toward(_walk_weight, 1.0 if walking else 0.0, delta * 5.0)
	if walking:
		_phase = fposmod(_phase + delta * DUTY * walk_speed / STRIDE, 1.0)
	var ww: float = _walk_weight
	var breath: float = sin(_time * TAU * 0.32)
	# body sway: one roll per cycle (alternating steps), bob twice per cycle
	var roll: float = sin(_phase * TAU) * 0.035 * ww
	var bob: float = -(0.5 - 0.5 * cos(_phase * TAU * 2.0)) * 9.0 * ww
	var shift: float = sin(_phase * TAU) * 6.0 * ww
	var hop: float = -absf(sin(happy * PI * 2.0)) * 22.0 if happy > 0.0 else 0.0
	var pivot := Vector2(0, -300)
	var body_xf := Transform2D(roll, Vector2(1.0, 1.0 + breath * 0.01), 0.0,
			pivot + Vector2(shift, bob + hop)) * Transform2D(0.0, Vector2.ONE, 0.0, -pivot)
	for p in _body:
		p.set_xf(body_xf * Transform2D(0.0, p.rest))
	var head_roll: float = -roll * 0.6 + sin(_time * 0.7) * 0.03 * (1.0 - ww)
	var head_bob: float = cos(_phase * TAU * 2.0 + 0.9) * 5.0 * ww
	var neck: Vector2 = body_xf * Vector2(0, -520)
	var head_xf := Transform2D(head_roll, Vector2.ONE, 0.0, neck + Vector2(0, head_bob)) \
			* Transform2D(0.0, Vector2.ONE, 0.0, -Vector2(0, -520))
	for p in _head:
		var extra: float = 0.0
		var ei: int = _ears.find(p)
		if ei >= 0:
			var side: float = -1.0 if ei == 0 else 1.0
			extra = (ear_twitch if ei == ear_which else 0.0) * side
			extra += sin(_phase * TAU * 2.0 + float(ei)) * 0.05 * ww * side
			extra += -0.1 * happy * side
		p.set_xf(head_xf * Transform2D(extra, p.rest))
	for i in _face.size():
		_face[i].transform = head_xf * Transform2D(0.0, _face_rest[i])
	if _eyes:
		_eyes.texture = _eye_tex[eye]
		_mouth.texture = _mouth_tex[&"smile" if happy > 0.0 else &"closed"]
		for b in _blush:
			b.modulate.a = 0.55 + 0.45 * happy
	_animate_legs(body_xf, ww)
	_animate_tail(body_xf, ww, happy, tail_flick)


func _animate_legs(body_xf: Transform2D, ww: float) -> void:
	# walking towards the viewer the body moves down the screen, so a planted paw
	# moves up relative to the body; walking away it is the other way round
	var dir: float = -1.0 if is_back else 1.0
	for l in _legs:
		var ph: float = fposmod(_phase + l.phase, 1.0)
		var off := Vector2.ZERO
		var sc: float = 1.0
		if ph < DUTY:
			off.y = dir * (STRIDE * 0.5 - STRIDE * ph / DUTY)
		else:
			var u: float = (ph - DUTY) / (1.0 - DUTY)
			var e: float = u * u * (3.0 - 2.0 * u)
			off.y = dir * (-STRIDE * 0.5 + STRIDE * e) - sin(u * PI) * STEP_LIFT
			sc = 1.0 + l.lift_scale * sin(u * PI)
		off *= ww
		sc = lerpf(1.0, sc, ww)
		l.foot = off
		var paw_pos: Vector2 = l.paw.rest + off
		l.paw.set_xf(Transform2D(0.0, Vector2(sc, sc), 0.0, paw_pos))
		if l.upper:
			# the upper leg hangs from the body and stretches to reach the paw
			var top: Vector2 = body_xf * l.upper.rest
			var need: float = (paw_pos.y + l.overlap) - top.y
			var s: float = clampf(need / l.upper_len, 0.7, 1.3)
			var lean: float = (paw_pos.x - top.x - (l.paw.rest.x - l.upper.rest.x)) / maxf(need, 1.0)
			l.upper.set_xf(Transform2D(-lean, Vector2(1.0, s), 0.0, top))


func _animate_tail(body_xf: Transform2D, ww: float, happy: float, flick: float) -> void:
	var base: Vector2 = body_xf * _tail_base
	var pts := PackedVector2Array()
	pts.append(base)
	var n: int = 16
	var seg: float = (300.0 if is_back else 250.0) / float(n)
	var sway: float = sin(_time * 1.4) * (1.0 - ww) + sin(_phase * TAU) * ww
	var ang: float
	if is_back:
		ang = deg_to_rad(-90.0) + sway * 0.25
	else:
		ang = deg_to_rad(-40.0) + sway * 0.12
	var p: Vector2 = base
	for i in n:
		var t: float = float(i) / float(n - 1)
		var curl: float
		if is_back:
			curl = 0.03 * sway + (0.12 if t > 0.65 else 0.0) * (1.0 - happy)
		else:
			curl = -0.06 - 0.04 * sin(_time * 1.1 - t * 3.0)
		curl = lerpf(curl, 0.015 + (0.2 if t > 0.75 else 0.0), happy)
		curl += flick * 0.1 * t
		ang += curl
		p += Vector2.from_angle(ang) * seg
		pts.append(p)
	_tail_outline.points = pts
	_tail_fill.points = pts


func ear_tip_height() -> float:
	return stand_height
