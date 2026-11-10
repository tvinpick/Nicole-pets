extends Node2D
## Room + cat test scene.

@onready var room: Room = $Room
@onready var cat: Cat = $Actors/Cat
@onready var camera: CameraRig = $Camera
@onready var fps_label: Label = $Hud/Fps


func _ready() -> void:
	camera.room_size = Vector2(Room.ROOM_WIDTH, Room.ROOM_HEIGHT)
	# start closer (~1.5x), aligned to the bottom of the room, around the cat
	camera.start_view(1.5, cat.position.x + 120.0)
	camera.tapped.connect(_on_tapped)
	fps_label.visible = OS.is_debug_build()


func _on_tapped(world_pos: Vector2) -> void:
	if cat.contains_point(world_pos):
		cat.on_tapped()
	elif room.is_floor_point(world_pos):
		cat.walk_to(world_pos)


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
				camera.position = cat.position + Vector2(0.0, -40.0)
			elif a.begins_with("--pose="):
				cat.rig.set_pose(StringName(a.substr(7)))
				cat.set_process(false)
			elif a.begins_with("--walk"):
				cat.walk_to(cat.position + Vector2(700.0, 0.0))
			elif a.begins_with("--back"):
				cat.walk_to(cat.position + Vector2(-400.0, 0.0))
			elif a.begins_with("--deep"):
				cat.walk_to(cat.position + Vector2(60.0, -130.0))
			elif a.begins_with("--happy"):
				cat.on_tapped()
			elif a.begins_with("--still"):
				cat.set_process(false)
	_frame += 1
	if a_follow():
		camera.position.x = cat.position.x
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
