class_name CameraRig
extends Camera2D
## Swipe = scroll the room, pinch = smooth zoom (clamped). Also mouse drag / wheel on desktop.
## A short touch without movement is reported as `tapped(world_position)`.

signal tapped(world_position: Vector2)

@export var max_zoom_factor: float = 4.0
@export var zoom_smoothing: float = 12.0
@export var fling_friction: float = 4.0

var room_size: Vector2 = Vector2(6600.0, 1024.0)

var _touches: Dictionary[int, Vector2] = {}
var _target_zoom: float = 1.0
var _zoom_anchor_screen: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
var _tap_start_time: float = 0.0
var _tap_start_pos: Vector2 = Vector2.ZERO
var _tap_candidate: bool = false
var _last_pinch_dist: float = 0.0


func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_target_zoom = min_zoom()
	zoom = Vector2.ONE * _target_zoom
	get_viewport().size_changed.connect(_on_viewport_resized)


## Initial view: zoom = factor x "whole room height", bottom of the room at the screen bottom.
func start_view(zoom_factor: float, focus_x: float) -> void:
	_target_zoom = clampf(min_zoom() * zoom_factor, min_zoom(), max_zoom())
	zoom = Vector2.ONE * _target_zoom
	var half: Vector2 = get_viewport_rect().size * 0.5 / _target_zoom
	position = Vector2(focus_x, room_size.y - half.y)
	_clamp_position()


func _on_viewport_resized() -> void:
	_target_zoom = clampf(_target_zoom, min_zoom(), max_zoom())
	zoom = Vector2.ONE * clampf(zoom.x, min_zoom(), max_zoom())
	_clamp_position()


## The whole room height always fits the screen at minimal zoom.
func min_zoom() -> float:
	return get_viewport_rect().size.y / room_size.y


func max_zoom() -> float:
	return min_zoom() * max_zoom_factor


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
			_velocity = Vector2.ZERO
			if _touches.size() == 1:
				_tap_candidate = true
				_tap_start_pos = t.position
				_tap_start_time = Time.get_ticks_msec() / 1000.0
			else:
				_tap_candidate = false
				_last_pinch_dist = _pinch_distance()
		else:
			if _touches.has(t.index):
				_touches.erase(t.index)
			if _tap_candidate and _touches.is_empty():
				var dt: float = Time.get_ticks_msec() / 1000.0 - _tap_start_time
				if dt < 0.4 and t.position.distance_to(_tap_start_pos) < 24.0:
					tapped.emit(screen_to_world(t.position))
					_velocity = Vector2.ZERO
			_tap_candidate = false
			if _touches.size() >= 2:
				_last_pinch_dist = _pinch_distance()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = d.position
		if _tap_candidate and d.position.distance_to(_tap_start_pos) >= 24.0:
			_tap_candidate = false
		if _touches.size() == 1 and not _tap_candidate:
			var world_delta: Vector2 = d.relative / zoom.x
			position -= world_delta
			_velocity = -d.velocity / zoom.x
			_clamp_position()
		elif _touches.size() >= 2:
			var dist: float = _pinch_distance()
			if _last_pinch_dist > 1.0:
				_target_zoom = clampf(_target_zoom * dist / _last_pinch_dist, min_zoom(), max_zoom())
				_zoom_anchor_screen = _pinch_center()
			_last_pinch_dist = dist
			# two-finger pan follows the pinch centre
			position -= d.relative / zoom.x * 0.5
			_velocity = Vector2.ZERO
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var f: float = 1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			_target_zoom = clampf(_target_zoom * f, min_zoom(), max_zoom())
			_zoom_anchor_screen = mb.position
			get_viewport().set_input_as_handled()


func _pinch_distance() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	return a.distance_to(b)


func _pinch_center() -> Vector2:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return get_viewport_rect().size * 0.5
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	return (a + b) * 0.5


func screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos


func _process(delta: float) -> void:
	# smooth zoom around the pinch/wheel anchor
	if absf(zoom.x - _target_zoom) > 0.0001:
		var anchor_world_before: Vector2 = _screen_to_world_with(_zoom_anchor_screen, zoom.x)
		var z: float = lerpf(zoom.x, _target_zoom, 1.0 - exp(-zoom_smoothing * delta))
		if absf(z - _target_zoom) < 0.0005:
			z = _target_zoom
		zoom = Vector2.ONE * z
		var anchor_world_after: Vector2 = _screen_to_world_with(_zoom_anchor_screen, z)
		position += anchor_world_before - anchor_world_after
	# fling inertia after a swipe
	if _touches.is_empty() and _velocity.length() > 5.0:
		position += _velocity * delta
		_velocity *= exp(-fling_friction * delta)
	_clamp_position()


func _screen_to_world_with(screen_pos: Vector2, z: float) -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	return position + (screen_pos - vp * 0.5) / z


func _clamp_position() -> void:
	var half: Vector2 = get_viewport_rect().size * 0.5 / zoom.x
	var min_p: Vector2 = half
	var max_p: Vector2 = room_size - half
	if min_p.x > max_p.x:
		position.x = room_size.x * 0.5
	else:
		position.x = clampf(position.x, min_p.x, max_p.x)
	if min_p.y > max_p.y:
		position.y = room_size.y * 0.5
	else:
		position.y = clampf(position.y, min_p.y, max_p.y)
