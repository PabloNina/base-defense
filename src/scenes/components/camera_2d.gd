extends Camera2D

var zoom_speed: float = 0.05
var zoom_min: float = 0.5
var zoom_max: float = 1.0
var drag_sensitivity: float = 1.0

func _ready():
	InputManager.camera_zoom_in.connect(_on_InputManager_camera_zoom_in)
	InputManager.camera_zoom_out.connect(_on_InputManager_camera_zoom_out)
	InputManager.camera_pan.connect(_on_InputManager_camera_pan)

func _on_InputManager_camera_zoom_in():
	zoom += Vector2(zoom_speed, zoom_speed)
	zoom = clamp(zoom, Vector2(zoom_min, zoom_min), Vector2(zoom_max, zoom_max))

func _on_InputManager_camera_zoom_out():
	zoom -= Vector2(zoom_speed, zoom_speed)
	zoom = clamp(zoom, Vector2(zoom_min, zoom_min), Vector2(zoom_max, zoom_max))

func _on_InputManager_camera_pan(delta: Vector2):
	self.position -= delta * drag_sensitivity / zoom
