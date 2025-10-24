# =========================================
# PlacementPreview.gd
# =========================================
# Displays a semi-transparent preview of a building and its potential network connections.
# Handles placement validity through Area2D overlap detection and provides visual feedback.
class_name PlacementPreview extends Area2D

# --------------------------------------------
# --- Signals --------------------------------
# --------------------------------------------
# Emitted when placement validity changes, passing itself for identification.
signal is_placeable(is_valid: bool, preview: PlacementPreview)

# --------------------------------------------
# --- Onready References ---------------------
# --------------------------------------------
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lines_container: Node2D = $LinesContainer

# --------------------------------------------
# --- Preview Configuration ------------------
# --------------------------------------------
var building_type: DataTypes.BUILDING_TYPE = DataTypes.BUILDING_TYPE.NULL
var network_manager: NetworkManager

# --- Visuals ---
const VALID_COLOR: Color = Color(1.0, 1.0, 1.0, 0.5)
const INVALID_COLOR: Color = Color(1.0, 0.0, 0.0, 0.5)
const LINE_WIDTH: float = 1.0
const LINE_COLOR: Color = Color(0.2, 1.0, 0.0, 0.6)
const LINE_INVALID_COLOR: Color = Color(1.0, 0.2, 0.2, 0.6)
const RANGE_COLOR: Color = Color(1.0, 0.2, 0.2, 0.2)

# --- State ---
var overlapping_areas: Array[Area2D] = []
var _ghost_lines: Array[Line2D] = []

# --------------------------------------------
# --- Engine Callbacks -----------------------
# --------------------------------------------
func _ready() -> void:
	# Connect signals for area overlap detection
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func _draw() -> void:
	var fire_range = DataTypes.get_fire_range(building_type)
	if fire_range > 0:
		draw_circle(Vector2.ZERO, fire_range, RANGE_COLOR)

# --------------------------------------------
# --- Public Methods -------------------------
# --------------------------------------------
# Initializes the preview's properties.
func initialize(p_building_type: DataTypes.BUILDING_TYPE, p_network_manager: NetworkManager, p_texture: Texture2D) -> void:
	building_type = p_building_type
	network_manager = p_network_manager
	sprite.texture = p_texture
	
	# Configure collision shape based on texture size
	var shape_size = sprite.texture.get_size() * sprite.scale
	collision_shape.shape.size = shape_size
	
	# Ensure collision is enabled
	collision_shape.set_deferred("disabled", false)
	
	# Force an immediate update of the connection lines
	_update_connection_ghosts()
	queue_redraw()

# Updates the preview's position and redraws connection lines.
func update_position(new_position: Vector2) -> void:
	global_position = new_position
	_update_connection_ghosts()

# Hides and resets the preview.
func clear() -> void:
	building_type = DataTypes.BUILDING_TYPE.NULL
	sprite.texture = null
	visible = false
	overlapping_areas.clear()
	_clear_ghost_lines()
	collision_shape.set_deferred("disabled", true)
	queue_redraw()

# --------------------------------------------
# --- Overlap Handling -----------------------
# --------------------------------------------
func _on_area_entered(area: Area2D) -> void:
	overlapping_areas.append(area)
	_set_valid_color(false)
	is_placeable.emit(false, self)
	_update_connection_ghosts()

func _on_area_exited(area: Area2D) -> void:
	overlapping_areas.erase(area)
	if overlapping_areas.is_empty():
		_set_valid_color(true)
		is_placeable.emit(true, self)
	_update_connection_ghosts()

# --------------------------------------------
# --- Visual Feedback ------------------------
# --------------------------------------------
func _set_valid_color(is_valid: bool) -> void:
	sprite.modulate = VALID_COLOR if is_valid else INVALID_COLOR

# --------------------------------------------
# --- Connection Previews --------------------
# --------------------------------------------
func _update_connection_ghosts() -> void:
	if building_type == DataTypes.BUILDING_TYPE.NULL or not is_visible():
		_clear_ghost_lines()
		return
	if not network_manager:
		return

	var targets: Array = []
	for other in network_manager.registered_buildings:
		if not is_instance_valid(other):
			continue
		if NetworkManager.can_buildings_connect(
			building_type,
			global_position,
			DataTypes.get_is_relay(building_type),
			other.building_type,
			other.global_position,
			other.is_relay
		):
			targets.append(other)

	while _ghost_lines.size() < targets.size():
		var line := Line2D.new()
		line.width = LINE_WIDTH
		line.default_color = LINE_COLOR
		lines_container.add_child(line)
		_ghost_lines.append(line)

	for i in range(_ghost_lines.size()):
		var line: Line2D = _ghost_lines[i]
		if i < targets.size():
			var target = targets[i]
			line.points = [global_position, target.global_position]
			line.global_position = Vector2.ZERO
			line.default_color = LINE_COLOR if overlapping_areas.is_empty() else LINE_INVALID_COLOR
			line.visible = true
		else:
			line.visible = false

func _clear_ghost_lines() -> void:
	for line in _ghost_lines:
		if is_instance_valid(line):
			line.queue_free()
	_ghost_lines.clear()
