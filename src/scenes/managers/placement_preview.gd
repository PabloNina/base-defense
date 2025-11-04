# =========================================
# placement_preview.gd
# =========================================
# Displays a semi-transparent preview of a building and its potential grid connections and fire range.
# Handles placement validity through Area2D overlap detection and provides visual feedback.
class_name PlacementPreview extends Node2D
# --------------------------------------------
# --- Signals --------------------------------
# --------------------------------------------
# Emitted when placement validity changes, passing itself for identification.
# Listener BuildingManager
signal is_placeable(is_valid: bool, preview: PlacementPreview)
# --------------------------------------------
# --- Onready References ---------------------
# --------------------------------------------
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D
@onready var connection_lines_container: Node = $ConnectionLinesContainer
# --------------------------------------------
# --- Preview Configuration ------------------
# --------------------------------------------
# The type of building this preview represents.
var building_type: GlobalData.BUILDING_TYPE = GlobalData.BUILDING_TYPE.NULL
# Reference to the GridManager to check for connections.
var grid_manager: GridManager
# Reference to TileMap ground layer and buildable tile for placement validity
var ground_layer: TileMapLayer
var buildable_tile_id: int = 0
# --- Visuals ---
# Color for the weapon range visualization circle.
const RANGE_COLOR: Color = Color(1.0, 0.2, 0.2, 0.2)
# --- State ---
# Keeps track of overlapping placement-blocking areas.
var overlapping_areas: Array[Area2D] = []
var is_on_buildable_tile: bool = true
# Pool of Line2D nodes for drawing connection previews.
var _ghost_lines: Array[ConnectionLine] = []
# Tracks if the preview has been configured.
var _is_initialized: bool = false
var show_visual_feedback: bool = true
var is_valid: bool = true

# --------------------------------------------
# --- Engine Callbacks -----------------------
# --------------------------------------------
func _draw() -> void:
	if not show_visual_feedback:
		return
	# Draws the weapon's fire range if applicable.
	var fire_range = GlobalData.get_fire_range(building_type)
	if fire_range > 0:
		draw_circle(Vector2.ZERO, fire_range, RANGE_COLOR)
	
	# Draws the validity box around the building
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
func initialize(p_building_type: GlobalData.BUILDING_TYPE, p_grid_manager: GridManager, p_texture: Texture2D, p_ground_layer: TileMapLayer, p_buildable_tile_id: int, p_show_feedback: bool = true) -> void:
	building_type = p_building_type
	grid_manager = p_grid_manager
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
	building_type = GlobalData.BUILDING_TYPE.NULL
	if sprite:
		sprite.texture = null
	visible = false
	overlapping_areas.clear()
	if grid_manager:
		_clear_ghost_lines()
	if collision_shape:
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
	is_placeable.emit(is_valid, self)
	queue_redraw()

# --------------------------------------------
# --- Connection Previews --------------------
# --------------------------------------------
# Updates the visibility and position of connection lines to nearby buildings.
func _update_connection_ghosts() -> void:
	if not show_visual_feedback:
		_clear_ghost_lines()
		return
	if building_type == GlobalData.BUILDING_TYPE.NULL or not is_visible():
		_clear_ghost_lines()
		return
	if not grid_manager:
		return

	var targets: Array = []
	for other in grid_manager.registered_buildings:
		if not is_instance_valid(other):
			continue
		if grid_manager.can_buildings_connect(
			building_type,
			global_position,
			GlobalData.get_is_relay(building_type),
			other.building_type,
			other.global_position,
			other.is_relay
		):
			targets.append(other)

	# Get more lines from the pool if needed.
	while _ghost_lines.size() < targets.size():
		var line: ConnectionLine = grid_manager.get_connection_line_from_pool()
		connection_lines_container.add_child(line)
		_ghost_lines.append(line)

	# Return excess lines to the pool.
	while _ghost_lines.size() > targets.size():
		var line: ConnectionLine = _ghost_lines.pop_back()
		grid_manager.return_connection_line_to_pool(line)

	# Update the visible lines.
	for i in range(targets.size()):
		var line: ConnectionLine = _ghost_lines[i]
		var target = targets[i]
		var is_line_valid = overlapping_areas.is_empty() and is_on_buildable_tile
		line.setup_preview(global_position, target.global_position, is_line_valid)


# Frees the Line2D nodes and clears the line array.
func _clear_ghost_lines() -> void:
	for line in _ghost_lines:
		grid_manager.return_connection_line_to_pool(line)
	_ghost_lines.clear()
