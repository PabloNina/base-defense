extends Camera2D

@export var zoom_speed: float = 0.05
@export var zoom_min: float = 0.5
@export var zoom_max: float = 1.0
@export var drag_sensitivity: float = 1.0
@export var camera_move_speed: float = 300.0 # Pixels per second

var _keyboard_move_direction: Vector2 = Vector2.ZERO

func _ready():
	InputManager.camera_zoom_in.connect(_on_InputManager_camera_zoom_in)
	InputManager.camera_zoom_out.connect(_on_InputManager_camera_zoom_out)
	InputManager.camera_pan.connect(_on_InputManager_camera_pan)
	InputManager.camera_keyboard_move_vector_changed.connect(_on_InputManager_camera_keyboard_move_vector_changed)

func _process(delta):
	# Apply keyboard movement continuously
	if _keyboard_move_direction != Vector2.ZERO:
		position += _keyboard_move_direction * camera_move_speed * delta

func _on_InputManager_camera_zoom_in():
	zoom += Vector2(zoom_speed, zoom_speed)
	zoom = clamp(zoom, Vector2(zoom_min, zoom_min), Vector2(zoom_max, zoom_max))

func _on_InputManager_camera_zoom_out():
	zoom -= Vector2(zoom_speed, zoom_speed)
	zoom = clamp(zoom, Vector2(zoom_min, zoom_min), Vector2(zoom_max, zoom_max))

func _on_InputManager_camera_pan(delta: Vector2):
	self.position -= delta * drag_sensitivity / zoom

func _on_InputManager_camera_keyboard_move_vector_changed(new_direction: Vector2):
	_keyboard_move_direction = new_direction
