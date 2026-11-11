extends Node2D
## Room with the cat and the puppy.

## Start zoom relative to "the whole room height fits the screen", anchored to the
## bottom of the room (1.5x closer than the previous 1.5x default).
const START_ZOOM: float = 2.25

@onready var room: Room = $Room
@onready var cat: Cat = $Actors/Cat
@onready var dog: Dog = $Actors/Dog
@onready var camera: CameraRig = $Camera
@onready var fps_label: Label = $Hud/Fps


func _ready() -> void:
	# PLACEHOLDER food bowl until there is bowl art (y-sorted with the cat)
	var bowl := FoodBowlPlaceholder.new()
	bowl.name = "FoodBowlPlaceholder"
	bowl.position = Room.FOOD_BOWL_POS
	bowl.scale = Vector2.ONE * room.depth_scale(bowl.position.y)
	$Actors.add_child(bowl)
	room.food_bowl = bowl
	# PLACEHOLDER toy ball
	var ball := BallPlaceholder.new()
	ball.name = "BallPlaceholder"
	ball.room = room
	ball.position = Room.BALL_START
	$Actors.add_child(ball)
	room.ball = ball
	# PLACEHOLDER puppy bowls (food + water), not the cat's bowl
	room.dog_food_bowl = _placeholder_bowl("DogFoodBowlPlaceholder", Room.DOG_FOOD_POS,
			Color(0.9, 0.45, 0.4), Color(0.97, 0.62, 0.55), Color(0.55, 0.35, 0.2))
	room.dog_water_bowl = _placeholder_bowl("DogWaterBowlPlaceholder", Room.DOG_WATER_POS,
			Color(0.9, 0.45, 0.4), Color(0.97, 0.62, 0.55), Color(0.45, 0.72, 0.95))
	camera.room_size = Vector2(Room.ROOM_WIDTH, Room.ROOM_HEIGHT)
	# start closer (~1.5x), aligned to the bottom of the room, around the cat
	camera.start_view(START_ZOOM, (cat.position.x + dog.position.x) * 0.5)
	# once more after the first frames: the window size on Android is final only then
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if not camera.get("_user_moved"):
			camera.start_view(START_ZOOM, (cat.position.x + dog.position.x) * 0.5))
	camera.tapped.connect(_on_tapped)
	fps_label.visible = OS.is_debug_build()


func _placeholder_bowl(n: String, pos: Vector2, body: Color, rim: Color, fill: Color) -> Node2D:
	var b := FoodBowlPlaceholder.new()
	b.name = n
	b.position = pos
	b.bowl_color = body
	b.rim_color = rim
	b.fill_color = fill
	b.width = 58.0
	b.scale = Vector2.ONE * room.depth_scale(pos.y)
	$Actors.add_child(b)
	return b


func _on_tapped(world_pos: Vector2) -> void:
	# the pet drawn in front (lower on the floor) gets the tap first
	var pets: Array[Node2D] = [cat, dog]
	pets.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.position.y > b.position.y)
	for p: Node2D in pets:
		if p.call("contains_point", world_pos):
			p.call("on_tapped")
			return
	if room.is_floor_point(world_pos):
		cat.on_floor_tapped(world_pos)


func _process(_delta: float) -> void:
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if _shot_path != "":
		_dev_capture()


# --- developer tooling: `godot -- --shot=out.png [--frames=N] [--zoom=Z] [--pose=sit]` ---
var _shot_path: String = ""
var _shot_frames: int = 30
var _frame: int = 0
var _shot_every: int = 0


func _enter_tree() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--frames="):
			_shot_frames = a.substr(9).to_int()
		elif a.begins_with("--every="):
			_shot_every = a.substr(8).to_int()


func _dev_capture() -> void:
	if _frame == 0:
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("--zoom="):
				var z: float = a.substr(7).to_float()
				camera.zoom = Vector2.ONE * z
				camera.set("_target_zoom", z)
				camera.set("_user_moved", true)
				camera.position = cat.position + Vector2(0.0, -40.0)
			elif a.begins_with("--pose="):
				cat.rig.set_pose(StringName(a.substr(7)))
				cat.set_process(false)
			elif a.begins_with("--walk"):
				cat.walk_to(cat.position + Vector2(700.0, 0.0))
			elif a.begins_with("--back"):
				cat.walk_to(cat.position + Vector2(-400.0, 0.0))
			elif a.begins_with("--view="):
				cat.rig.set_view(CatRig.View.FRONT if a.ends_with("front") else CatRig.View.BACK)
				cat.set_process(false)
			elif a.begins_with("--eat"):
				cat.position = Room.FOOD_BOWL_POS + Vector2(-500.0, -3.0)
				cat.call("_go_eat")
			elif a.begins_with("--hunt"):
				cat.position = Vector2(Room.BALL_START.x + 420.0, Room.BALL_START.y - 2.0)
				cat.call("_go_hunt", false)
				camera.position = Room.BALL_START + Vector2(160.0, -60.0)
			elif a.begins_with("--dog="):
				cat.set_process(false)
				camera.position = dog.position + Vector2(0.0, -60.0)
				var what: String = a.substr(6)
				match what:
					"walk": dog.call("_begin_walk", dog.position + Vector2(500.0, 0.0), false)
					"run": dog.call("_begin_walk", dog.position + Vector2(700.0, 0.0), true)
					"up": dog.call("_begin_walk", dog.position + Vector2(0.0, -180.0), false)
					"down": dog.call("_begin_walk", dog.position + Vector2(0.0, 40.0), false)
					"play": dog.call("_run_to_ball")
					"eat": dog.call("_go_bowl", &"eat")
					"sleep": dog.call("_rest", Dog.Mode.SLEEP)
					"happy": dog.on_tapped()
					_: dog.rig.play(StringName(what))
				dog.set("_mode_timer", 999.0)
			elif a.begins_with("--stretch"):
				cat.rig.stretch()
			elif a.begins_with("--up"):
				cat.walk_to(cat.position + Vector2(0.0, -150.0))
			elif a.begins_with("--down"):
				cat.walk_to(cat.position + Vector2(0.0, 100.0))
			elif a.begins_with("--diag"):
				cat.walk_to(cat.position + Vector2(-260.0, 100.0))
			elif a.begins_with("--happy"):
				cat.on_tapped()
			elif a.begins_with("--still"):
				cat.set_process(false)
	_frame += 1
	if a_follow():
		var who: Node2D = dog if cat.is_processing() == false else cat
		camera.position = who.position + Vector2(0.0, -80.0)
	var save_now: bool = _frame == _shot_frames or (_shot_every > 0 and _frame % _shot_every == 0)
	if save_now:
		await RenderingServer.frame_post_draw
		var path: String = _shot_path
		if _shot_every > 0:
			path = _shot_path.get_basename() + "_%04d.png" % _frame
		get_viewport().get_texture().get_image().save_png(path)
	if _frame >= _shot_frames:
		get_tree().quit()


func a_follow() -> bool:
	return "--follow" in OS.get_cmdline_user_args()
