class_name CatHearts
extends Node2D
## Small hearts floating up above the cat while it is happy (drawn, no texture needed).

var emitting: bool = false
var cat_height: float = 160.0

var _hearts: Array[Vector4] = []   # x, y, age, size
var _spawn: float = 0.0


func _process(delta: float) -> void:
	if emitting:
		_spawn -= delta
		if _spawn <= 0.0:
			_spawn = randf_range(0.28, 0.45)
			_hearts.append(Vector4(randf_range(-0.25, 0.25) * cat_height,
					-0.85 * cat_height, 0.0, randf_range(0.07, 0.1) * cat_height))
	for i in range(_hearts.size() - 1, -1, -1):
		var h: Vector4 = _hearts[i]
		h.z += delta
		h.y -= delta * 0.35 * cat_height
		h.x += sin(h.z * 5.0 + float(i)) * delta * 0.1 * cat_height
		_hearts[i] = h
		if h.z > 1.4:
			_hearts.remove_at(i)
	visible = not _hearts.is_empty()
	queue_redraw()


func _draw() -> void:
	for h in _hearts:
		var a: float = clampf(minf(h.z * 5.0, (1.4 - h.z) * 2.5), 0.0, 1.0)
		_draw_heart(Vector2(h.x, h.y), h.w, Color(0.95, 0.35, 0.5, a))


func _draw_heart(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var t: float = TAU * float(i) / 24.0
		# classic heart curve, y flipped for screen space
		var x: float = 16.0 * pow(sin(t), 3)
		var y: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(c + Vector2(x, -y) * s / 32.0)
	draw_colored_polygon(pts, col)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0.55, 0.15, 0.25, col.a), maxf(1.0, s * 0.06), true)
