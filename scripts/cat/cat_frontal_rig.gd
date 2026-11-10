class_name CatFrontalRig
extends Node2D
## Front view (cat walks towards the viewer) or back view (walks away, towards the wall).
## Uses the finished 4-frame walk drawings (cat_walk_front.png / cat_walk_back.png), cut
## and aligned by tools/process_cat.py into rig/walk_<view>_<n>.png:
## the paw line is at the canvas bottom, the head centre at the canvas centre x.
##
## Units = pixels of the frame images; the node origin is on the floor under the cat.
## The frame rate follows the walking speed (frame cycle = CYCLE_LEN of movement),
## standing = frame 1. The picture is never cut: sway = whole-sprite bob/roll only.

const FRAMES_DIR := "res://assets/characters/cat/rig/"
const FRAME_COUNT := 4
## canvas size and paw line of the aligned frames (see rig/anchors.json)
const CANVAS := {false: Vector2(420, 520), true: Vector2(420, 640)}
const PAW_LINE := {false: 512.0, true: 632.0}
## floor -> ear tips in frame 1 (used to match the side view size)
const HEIGHT := {false: 494.0, true: 608.0}
## body travel per full 4-frame cycle, as a part of the drawn cat height:
## one cycle = two steps (left front + right hind, then right front + left hind)
const CYCLE_PER_HEIGHT := 0.55

var is_back: bool = false
var stand_height: float = 494.0
var walk_speed: float = 0.0           ## px/s of movement in this node's units (set by CatRig)

var _sprite: Sprite2D
var _frames: Array[Texture2D] = []
var _phase: float = 0.0
var _walk_weight: float = 0.0
var _time: float = 0.0


func setup(back: bool) -> void:
	is_back = back
	stand_height = HEIGHT[back]
	var view: String = "back" if back else "front"
	for i in FRAME_COUNT:
		_frames.append(load(FRAMES_DIR + "walk_%s_%d.png" % [view, i + 1]) as Texture2D)
	_sprite = Sprite2D.new()
	_sprite.name = "Frame"
	_sprite.texture = _frames[0]
	_sprite.centered = false
	var canvas: Vector2 = CANVAS[back]
	_sprite.offset = Vector2(-canvas.x * 0.5, -float(PAW_LINE[back]))
	add_child(_sprite)


## Same signature for all views; face details are part of the drawings here.
func animate(delta: float, _eye: StringName, _ear_twitch: float, _ear_which: int,
		happy: float, _tail_flick: float) -> void:
	_time += delta
	var walking: bool = walk_speed > 1.0
	_walk_weight = move_toward(_walk_weight, 1.0 if walking else 0.0, delta * 6.0)
	if walking:
		var cycle: float = stand_height * CYCLE_PER_HEIGHT
		_phase = fposmod(_phase + delta * walk_speed / cycle, 1.0)
		_sprite.texture = _frames[int(_phase * FRAME_COUNT) % FRAME_COUNT]
	else:
		# stopping: finish on the standing frame
		_phase = 0.0
		_sprite.texture = _frames[0]
	var ww: float = _walk_weight
	# light sway of the whole picture: bob on each step, roll left/right per cycle
	var bob: float = -(0.5 - 0.5 * cos(_phase * TAU * 2.0)) * 7.0 * ww
	var roll: float = sin(_phase * TAU) * 0.022 * ww
	var breath: float = 1.0 + sin(_time * TAU * 0.32) * 0.008 * (1.0 - ww)
	var hop: float = 0.0
	if happy > 0.0:
		hop = -absf(sin(_time * 7.0)) * 14.0 * happy
	_sprite.position = Vector2(0.0, bob + hop)
	_sprite.rotation = roll
	_sprite.scale = Vector2(1.0, breath)
