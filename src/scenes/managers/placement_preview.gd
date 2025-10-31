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
# The type of building this preview represents.
var building_type: DataTypes.BUILDING_TYPE = DataTypes.BUILDING_TYPE.NULL
# Reference to the NetworkManager to check for connections.
var network_manager: NetworkManager
var ground_layer: TileMapLayer
var buildable_tile_id: int = 0

# --- Visuals ---
const VALID_COLOR: Color = Color(1.0, 1.0, 1.0, 0.5)
const INVALID_COLOR: Color = Color(1.0, 0.0, 0.0, 0.5)
const LINE_WIDTH: float = 1.0
const LINE_COLOR: Color = Color(0.2, 1.0, 0.0, 0.6)
const LINE_INVALID_COLOR: Color = Color(1.0, 0.2, 0.2, 0.6)
# Color for the weapon range visualization circle.
const RANGE_COLOR: Color = Color(1.0, 0.2, 0.2, 0.2)

# --- State ---
# Keeps track of overlapping placement-blocking areas.
var overlapping_areas: Array[Area2D] = []
var is_on_buildable_tile: bool = true
# Pool of Line2D nodes for drawing connection previews.
var _ghost_lines: Array[Line2D] = []
# Tracks if the preview has been configured.
var _is_initialized: bool = false
var show_visual_feedback: bool = true
var is_valid: bool = true

# --------------------------------------------
# --- Engine Callbacks -----------------------
# --------------------------------------------
func _ready() -> void:
	# Connect signals for area overlap detection
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

# Draws the weapon's fire range if applicable.
func _draw() -> void:
	if not show_visual_feedback:
		return
	var fire_range = DataTypes.get_fire_range(building_type)
	if fire_range > 0:
		draw_circle(Vector2.ZERO, fire_range, RANGE_COLOR)

	var texture = sprite.texture
	if texture:
		var rect: Rect2
		rect.size = texture.get_size()
		rect.position = -rect.size / 2
		var color = Color.GREEN if is_valid else Color.RED
		draw_rect(rect.grow(4), color, false, 2.0)

# --------------------------------------------
# --- Public Methods -------------------------
# --------------------------------------------
# Returns whether the preview has been initialized.
func is_initialized() -> bool:
	return _is_initialized


# Initializes the preview's properties.
func initialize(p_building_type: DataTypes.BUILDING_TYPE, p_network_manager: NetworkManager, p_texture: Texture2D, p_ground_layer: TileMapLayer, p_buildable_tile_id: int, p_show_feedback: bool = true) -> void:
	building_type = p_building_type
	network_manager = p_network_manager
	sprite.texture = p_texture
	ground_layer = p_ground_layer
	buildable_tile_id = p_buildable_tile_id
	show_visual_feedback = p_show_feedback
	
	# Configure collision shape based on texture size
	var shape_size = sprite.texture.get_size() * sprite.scale
	collision_shape.shape.size = shape_size
	
	# Ensure collision is enabled
	collision_shape.set_deferred("disabled", false)
	
	# Force an immediate update of the connection lines and range indicator.
	if show_visual_feedback:
		_update_connection_ghosts()
		queue_redraw()
	
	_is_initialized = true
	_update_validity()

# Updates the preview's position and redraws connection lines.
func update_position(new_position: Vector2) -> void:
	global_position = new_position

	if ground_layer:
		var tile_pos = ground_layer.local_to_map(global_position)
		var source_id = ground_layer.get_cell_source_id(tile_pos)
		is_on_buildable_tile = (source_id == buildable_tile_id)
	
	_update_validity()
	_update_connection_ghosts()

# Hides and resets the preview.
func clear() -> void:
	building_type = DataTypes.BUILDING_TYPE.NULL
	sprite.texture = null
	visible = false
	overlapping_areas.clear()
	_clear_ghost_lines()
	collision_shape.set_deferred("disabled", true)
	# Clear the fire range circle.
	queue_redraw()
	_is_initialized = false

# --------------------------------------------
# --- Overlap Handling -----------------------
# --------------------------------------------
# Called when another area enters the preview's detection box.
func _on_area_entered(area: Area2D) -> void:
	overlapping_areas.append(area)
	_update_validity()
	_update_connection_ghosts()

# Called when an area leaves the preview's detection box.
func _on_area_exited(area: Area2D) -> void:
	overlapping_areas.erase(area)
	_update_validity()
	_update_connection_ghosts()

# --------------------------------------------
# --- Visual Feedback ------------------------
# --------------------------------------------
func _update_validity() -> void:
	is_valid = overlapping_areas.is_empty() and is_on_buildable_tile
	_set_valid_color(is_valid)
	is_placeable.emit(is_valid, self)
	queue_redraw()

# Tints the preview sprite based on placement validity.
func _set_valid_color(is_valid: bool) -> void:
	sprite.modulate = VALID_COLOR if is_valid else INVALID_COLOR

# --------------------------------------------
# --- Connection Previews --------------------
# --------------------------------------------
# Updates the visibility and position of connection lines to nearby buildings.
func _update_connection_ghosts() -> void:
	if not show_visual_feedback:
		_clear_ghost_lines()
		return
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
			line.default_color = LINE_COLOR if overlapping_areas.is_empty() and is_on_buildable_tile else LINE_INVALID_COLOR
			line.visible = true
		else:
			line.visible = false

# Frees the Line2D nodes and clears the line array.
func _clear_ghost_lines() -> void:
	for line in _ghost_lines:
		if is_instance_valid(line):
			line.queue_free()
	_ghost_lines.clear()
