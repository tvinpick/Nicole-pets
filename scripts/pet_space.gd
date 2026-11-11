class_name PetSpace
extends RefCounted
## Shared floor space of the pets: they do not walk through each other but go round,
## and only one pet plays with the ball at a time (Room.ball_user).
## Each pet node has `footprint() -> Vector2`: half-size of its floor ellipse (world px).

const LOOK_AHEAD := 2.4     ## start steering when closer than this (in footprints)


## Bends a walking direction around the other pets that are ahead.
static func steer(room: Room, me: Node2D, dir: Vector2) -> Vector2:
	var out: Vector2 = dir
	for o: Node2D in room.pets:
		if o == me or not o.is_inside_tree():
			continue
		var r: Vector2 = o.position - me.position
		var e: Vector2 = me.call("footprint") + o.call("footprint")
		var d: float = Vector2(r.x / e.x, r.y / e.y).length()
		if d > LOOK_AHEAD or dir.dot(r) <= 0.0:
			continue
		# go round on the side with more floor (or the side we are already on)
		var side: float = signf(me.position.y - o.position.y)
		if absf(me.position.y - o.position.y) < 2.0:
			var mid: float = (Room.WALK_Y_MIN + Room.WALK_Y_MAX) * 0.5
			side = -1.0 if o.position.y > mid else 1.0
		if (side < 0.0 and me.position.y - Room.WALK_Y_MIN < e.y) \
				or (side > 0.0 and Room.WALK_Y_MAX - me.position.y < e.y):
			side = -side
		var w: float = clampf((LOOK_AHEAD - d) / (LOOK_AHEAD - 0.8), 0.0, 1.0)
		out = (out + Vector2(0.0, side) * w * 1.4).normalized()
	return out


## Pushes `me` out of any overlap with the other pets (only the moving pet is pushed).
static func separate(room: Room, me: Node2D) -> void:
	for o: Node2D in room.pets:
		if o == me or not o.is_inside_tree():
			continue
		var r: Vector2 = me.position - o.position
		var e: Vector2 = me.call("footprint") + o.call("footprint")
		var n := Vector2(r.x / e.x, r.y / e.y)
		var d: float = n.length()
		if d >= 1.0:
			continue
		if d < 0.001:
			n = Vector2(0.0, 1.0)
			d = 0.0
		var push: Vector2 = n.normalized() * (1.0 - d)
		me.position = room.clamp_walk_point(me.position + Vector2(push.x * e.x, push.y * e.y) * 0.5)


## Ball ownership: true if `me` may play with the ball now (and takes it).
static func take_ball(room: Room, me: Node, force: bool) -> bool:
	if room.ball_user != null and room.ball_user != me and is_instance_valid(room.ball_user):
		if not force:
			return false
		room.ball_user.call("yield_ball")
	room.ball_user = me
	return true


static func release_ball(room: Room, me: Node) -> void:
	if room.ball_user == me:
		room.ball_user = null
