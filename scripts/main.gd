extends Node2D
## Room + cat test scene.

## Start zoom relative to "the whole room height fits the screen", anchored to the
## bottom of the room (1.5x closer than the previous 1.5x default).
const START_ZOOM: float = 2.25

@onready var room: Room = $Room
@onready var cat: Cat = $Actors/Cat
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
	camera.room_size = Vector2(Room.ROOM_WIDTH, Room.ROOM_HEIGHT)
	# start closer (~1.5x), aligned to the bottom of the room, around the cat
	camera.start_view(START_ZOOM, cat.position.x)
	# once more after the first frames: the window size on Android is final only then
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if not camera.get("_user_moved"):
			camera.start_view(START_ZOOM, cat.position.x))
	camera.tapped.connect(_on_tapped)
	fps_label.visible = OS.is_debug_build()


func _on_tapped(world_pos: Vector2) -> void:
	if cat.contains_point(world_pos):
		cat.on_tapped()
	elif room.is_floor_point(world_pos):
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
		camera.position = cat.position + Vector2(0.0, -80.0)
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
