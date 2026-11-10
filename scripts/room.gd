class_name Room
extends Node2D
## Kids room: tiled wall + floor, window in the middle of the wall with a sky placeholder.

const WALL_TEX: Texture2D = preload("res://assets/rooms/kids/wall_tile.png")
const FLOOR_TEX: Texture2D = preload("res://assets/rooms/kids/floor_tile.png")
const WINDOW_TEX: Texture2D = preload("res://assets/rooms/kids/window.png")
const GLASS_MASK_TEX: Texture2D = preload("res://assets/rooms/kids/window_glass_mask.png")
const SKY_SHADER: Shader = preload("res://scripts/sky_placeholder.gdshader")

## Room size in world pixels (1 world px = 1 px of the source room art).
const ROOM_WIDTH: float = 6600.0
const ROOM_HEIGHT: float = 1024.0
const FLOOR_TOP: float = 701.0
## Window crop data (see tools/process_room.py -> window_placement.txt).
const WINDOW_TOP: float = 44.0
const WINDOW_CENTER_IN_TEX: float = 381.5
## Where the cat may walk (feet y).
const WALK_Y_MIN: float = 740.0
const WALK_Y_MAX: float = 1005.0
const WALK_X_MARGIN: float = 120.0

## PLACEHOLDER food bowl (created by main.gd inside the y-sorted Actors node).
const FOOD_BOWL_POS := Vector2(4050.0, 860.0)
var food_bowl: Node2D
var window_sprite: Sprite2D
var sky_sprite: Sprite2D


func _ready() -> void:
	var wall := _make_strip(WALL_TEX, 0.0, WALL_TEX.get_height())
	wall.name = "Wall"
	var floor_strip := _make_strip(FLOOR_TEX, FLOOR_TOP, FLOOR_TEX.get_height())
	floor_strip.name = "Floor"

	var window_x: float = ROOM_WIDTH * 0.5 - WINDOW_CENTER_IN_TEX
	sky_sprite = Sprite2D.new()
	sky_sprite.name = "SkyPlaceholder"
	sky_sprite.texture = GLASS_MASK_TEX
	sky_sprite.centered = false
	sky_sprite.position = Vector2(window_x, WINDOW_TOP)
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	sky_sprite.material = mat
	add_child(sky_sprite)

	window_sprite = Sprite2D.new()
	window_sprite.name = "Window"
	window_sprite.texture = WINDOW_TEX
	window_sprite.centered = false
	window_sprite.position = Vector2(window_x, WINDOW_TOP)
	add_child(window_sprite)


func _make_strip(tex: Texture2D, y: float, h: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = Vector2(0.0, y)
	s.region_enabled = true
	s.region_rect = Rect2(0.0, 0.0, ROOM_WIDTH, h)
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(s)
	return s


func clamp_walk_point(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, WALK_X_MARGIN, ROOM_WIDTH - WALK_X_MARGIN),
			clampf(p.y, WALK_Y_MIN, WALK_Y_MAX))


func is_floor_point(p: Vector2) -> bool:
	return p.y >= FLOOR_TOP + 20.0 and p.y <= ROOM_HEIGHT and p.x >= 0.0 and p.x <= ROOM_WIDTH


## Perspective scale for things standing on the floor (see WorldScale).
func depth_scale(y: float) -> float:
	return WorldScale.depth_scale(y)
