class_name WorldScale
extends RefCounted
## One place for the size of characters in the room.
##
## The wall (floor line -> cornice) is the reference: a 6-year-old girl (~115 cm)
## is about 45% of it. All characters get their on-screen height from real-life
## centimetres through PX_PER_CM, so the girl, the cat and the dog stay consistent.
## Heights are for depth scale 1.0 (bottom edge of the screen); further back the
## perspective factor (see depth_scale) makes them up to 10% smaller.

## Global tweak for all characters at once (1.0 = the proportions below).
const CHARACTER_SCALE: float = 1.0

const FLOOR_Y: float = 701.0          ## wall/floor line in the room art
const CORNICE_Y: float = 54.0         ## bottom of the cornice
const WALL_HEIGHT_PX: float = FLOOR_Y - CORNICE_Y
const GIRL_HEIGHT_CM: float = 115.0
const GIRL_WALL_FRACTION: float = 0.45
const PX_PER_CM: float = WALL_HEIGHT_PX * GIRL_WALL_FRACTION / GIRL_HEIGHT_CM

## Standing cat up to the ear tips: ~13% of the wall, about a third of the girl.
const CAT_HEIGHT_CM: float = 33.0

## Perspective on the floor: 90% at the wall, 100% at the bottom of the room/screen.
const DEPTH_SCALE_AT_WALL: float = 0.9
const DEPTH_SCALE_AT_FRONT: float = 1.0
const ROOM_BOTTOM_Y: float = 1024.0


static func height_px(height_cm: float) -> float:
	return height_cm * PX_PER_CM * CHARACTER_SCALE


static func depth_scale(feet_y: float) -> float:
	var t: float = clampf((feet_y - FLOOR_Y) / (ROOM_BOTTOM_Y - FLOOR_Y), 0.0, 1.0)
	return lerpf(DEPTH_SCALE_AT_WALL, DEPTH_SCALE_AT_FRONT, t)
