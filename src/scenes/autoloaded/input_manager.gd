extends Node2D

# -----------------------------------------
# --- Signals -----------------------------
# -----------------------------------------
# Mouse clicks
signal map_left_clicked(tile_position: Vector2i)
signal map_left_released(tile_position: Vector2i)
signal map_right_clicked(tile_position: Vector2i)

# Camera
signal camera_zoom_in
signal camera_zoom_out
signal camera_pan(delta: Vector2)

# Building selection hotkeys
signal build_relay_pressed
signal build_gun_turret_pressed
signal build_reactor_pressed
signal build_command_center_pressed

# Formation hotkeys
signal formation_tighter_pressed
signal formation_looser_pressed
signal formation_rotate_pressed
signal game_paused(is_paused: bool)

# -----------------------------------------
# --- References --------------------------
# -----------------------------------------
var ground_layer: TileMapLayer

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------

func _ready() -> void:
	# Ensure InputManager processes even when game is paused 
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	# --- Mouse Motion ---
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			camera_pan.emit(event.relative)

	# --- Mouse Buttons ---
	if event is InputEventMouseButton:
		var tile_position = ground_layer.local_to_map(ground_layer.get_local_mouse_position())
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				map_left_clicked.emit(tile_position)
			else:
				map_left_released.emit(tile_position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			map_right_clicked.emit(tile_position)

	# --- Keyboard ---
	if event.is_action_pressed("camera_zoom_in"):
		camera_zoom_in.emit()
	elif event.is_action_pressed("camera_zoom_out"):
		camera_zoom_out.emit()
	elif event.is_action_pressed("key_1"):
		build_relay_pressed.emit()
	elif event.is_action_pressed("key_2"):
		build_gun_turret_pressed.emit()
	elif event.is_action_pressed("key_3"):
		build_reactor_pressed.emit()
	elif event.is_action_pressed("key_4"):
		build_command_center_pressed.emit()
	elif event.is_action_pressed("formation_tighter"):
		formation_tighter_pressed.emit()
	elif event.is_action_pressed("formation_looser"):
		formation_looser_pressed.emit()
	elif event.is_action_pressed("formation_rotate"):
		formation_rotate_pressed.emit()
	elif event.is_action_pressed("pause"):
		get_tree().paused = not get_tree().paused
		game_paused.emit(get_tree().paused)
