class_name FoodBowlPlaceholder
extends Node2D
## PLACEHOLDER: a simple drawn food bowl until real bowl art exists.
## TODO(art): replace with the real bowl sprite; keep the node origin on the floor
## at the bowl's front-bottom centre (y-sorted with the characters).

@export var width: float = 64.0


func _draw() -> void:
	var w: float = width
	var h: float = w * 0.34
	# shadow
	draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, w * 0.62, Color(0.25, 0.12, 0.05, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# bowl body (trapezoid with rounded bottom)
	var body := PackedVector2Array([
		Vector2(-w * 0.5, -h), Vector2(w * 0.5, -h), Vector2(w * 0.38, -h * 0.15),
		Vector2(w * 0.3, 0), Vector2(-w * 0.3, 0), Vector2(-w * 0.38, -h * 0.15)])
	draw_colored_polygon(body, Color(0.36, 0.62, 0.86))
	var outline := body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, Color(0.2, 0.3, 0.45), 2.0, true)
	# rim and food
	draw_set_transform(Vector2(0, -h), 0.0, Vector2(1.0, 0.25))
	draw_circle(Vector2.ZERO, w * 0.5, Color(0.5, 0.75, 0.95))
	draw_circle(Vector2.ZERO, w * 0.42, Color(0.62, 0.42, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
