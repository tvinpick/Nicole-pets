class_name BallPlaceholder
extends Node2D
## PLACEHOLDER toy ball: a simple drawn circle until there is ball art.
## TODO(art): replace the drawing with a sprite; keep the origin at the floor contact
## point (the node is y-sorted with the characters).

const RADIUS: float = 15.0
const DECEL: float = 260.0            ## rolling friction, world px/s^2

var room: Room
var velocity: Vector2 = Vector2.ZERO
var _spin: float = 0.0


func is_rolling() -> bool:
	return velocity.length() > 2.0


## Push the ball (e.g. the cat's pounce).
func kick(v: Vector2) -> void:
	velocity = v


## Roll so that the ball stops at `p` (constant deceleration).
func roll_to(p: Vector2) -> void:
	var d: Vector2 = room.clamp_walk_point(p) - position
	if d.length() < 1.0:
		return
	velocity = d.normalized() * sqrt(2.0 * DECEL * d.length())


func _process(delta: float) -> void:
	if is_rolling():
		var sp: float = velocity.length()
		var step: Vector2 = velocity * delta
		position += step
		_spin += step.x / RADIUS
		var ns: float = maxf(sp - DECEL * delta, 0.0)
		velocity = velocity / sp * ns
		# stay on the walkable floor (soft bounce at the edges)
		var c: Vector2 = room.clamp_walk_point(position)
		if c.x != position.x:
			velocity.x = -velocity.x * 0.5
		if c.y != position.y:
			velocity.y = -velocity.y * 0.5
		position = c
		queue_redraw()
	scale = Vector2.ONE * room.depth_scale(position.y)


func _draw() -> void:
	var r: float = RADIUS
	# soft shadow
	draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, r * 1.1, Color(0.25, 0.12, 0.05, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var c := Vector2(0, -r)
	draw_circle(c, r, Color(0.93, 0.3, 0.32))
	# a band that turns while rolling
	var a: float = _spin
	var p1: Vector2 = c + Vector2(cos(a), sin(a)) * r * 0.95
	var p2: Vector2 = c - Vector2(cos(a), sin(a)) * r * 0.95
	draw_line(p1, p2, Color(1.0, 0.85, 0.3), r * 0.35, true)
	draw_circle(c + Vector2(-r * 0.35, -r * 0.35), r * 0.22, Color(1, 1, 1, 0.45))
	draw_arc(c, r, 0.0, TAU, 32, Color(0.45, 0.12, 0.15), 1.6, true)
