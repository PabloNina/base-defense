# =========================================
# GhostBuilding.gd
# =========================================
# Displays a semi-transparent ghost of the selected building.
# Handles placement validity (via Area2D overlap) and visual tinting.
# Communicates with BuildingManager to confirm whether placement is valid.
class_name GhostBuilding extends Area2D
# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
# Reference to the collision shape used for overlap detection
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
# Reference to the ghost_sprite used for building preview
@onready var ghost_sprite: Sprite2D = $GhostSprite
@onready var ghost_lines_container: Node2D = $GhostLines

# --------------------------------------------
# --- Signals --------------------------------
# --------------------------------------------
# Signal emitted whenever placement validity changes
# Listener: BuildingManager -> _on_building_ghost_preview_is_placeable(value: bool)
signal is_placeable(value: bool)

# --------------------------------------------
# --- Ghost Configuration -------------------
# --------------------------------------------
# Visual and logical parameters for placement preview
var collision_shape_size: Vector2 = Vector2.ZERO
# Currently selected building type (from DataTypes.BuildingType)
var current_building_type: DataTypes.BUILDING_TYPE = DataTypes.BUILDING_TYPE.NULL
# Keeps track of overlapping placement-blocking areas
var overlapping_areas: Array[Area2D] = []

# Tint colors for visual feedback
const VALID_COLOR: Color = Color(1.0, 1.0, 0.0, 0.6)
const INVALID_COLOR: Color = Color(1.0, 0.0, 0.0, 0.6) 

# Line visuals for potential network connections
const GHOST_LINE_WIDTH: float = 1.0
const GHOST_LINE_COLOR: Color = Color(0.2, 1.0, 0.0, 0.6)
const GHOST_LINE_INVALID_COLOR: Color = Color(1.0, 0.2, 0.2, 0.6)

# Internal state for connection ghosting
var _ghost_lines: Array[Line2D] = []
var _last_global_position: Vector2 = Vector2.INF
var _last_building_type: int = DataTypes.BUILDING_TYPE.NULL

var _network_manager: NetworkManager
#var _building_manager: BuildingManager

# --------------------------------------------
# --- Engine Callbacks -----------------------
# --------------------------------------------
func _ready() -> void:
	# Ghost starts hidden until building preview is active
	ghost_sprite.visible = false
	ghost_sprite.modulate = VALID_COLOR  # Default color

func _process(_delta: float) -> void:
	# Only recalc when visible and a building type is selected
	if not ghost_sprite.visible:
		return

	# Recompute when either global position or building type changes
	if global_position != _last_global_position or current_building_type != _last_building_type:
		_last_global_position = global_position
		_last_building_type = current_building_type
		_update_connection_ghosts()

	#if _building_manager.tile_source_id != _building_manager.buildable_tile_id:
		#is_placeable.emit(false)
		#_set_valid_color(false)
	#else:
		#is_placeable.emit(true)
		#_set_valid_color(true)
		
# --------------------------------------------
# --- Public Methods -------------------------
# --------------------------------------------
func set_building_type(new_type: DataTypes.BUILDING_TYPE) -> void:
	# Updates the ghost appearance and connections based on selected building type.
	# Pulls ghost texture and connection range from DataTypes.
	if current_building_type == new_type:
		return  # No need to reapply the same texture

	current_building_type = new_type
	var ghost_texture = DataTypes.get_ghost_texture(current_building_type)
	if ghost_texture:
		ghost_sprite.texture = ghost_texture
		ghost_sprite.visible = true
	else:
		ghost_sprite.visible = false
	
	# Adjust collisionshape size automatically from texture
	collision_shape_size = ghost_sprite.texture.get_size() * ghost_sprite.scale
	collision_shape_2d.shape.size = collision_shape_size

	# Force connection ghost recalculation
	_update_connection_ghosts()

func clear_preview() -> void:
	# Hides and resets the ghost building completely
	current_building_type = DataTypes.BUILDING_TYPE.NULL
	ghost_sprite.texture = null
	ghost_sprite.visible = false
	overlapping_areas.clear()

	# Clear ghost connection lines
	_clear_ghost_lines()

# --------------------------------------------
# --- Overlap Handling -----------------------
# --------------------------------------------
func _on_area_entered(area: Area2D) -> void:
	# Called automatically when another area enters the marker.
	# If there is an overlap, placement becomes invalid (red marker).
	overlapping_areas.append(area)
	_set_valid_color(false)
	is_placeable.emit(false)
	# Update visuals (invalid connection color won't affect lines, but keep for parity)
	_update_connection_ghosts()

func _on_area_exited(area: Area2D) -> void:
	# Called when an area leaves the marker.
	# If no more overlaps exist, placement becomes valid again (yellow marker).
	overlapping_areas.erase(area)
	if overlapping_areas.is_empty():
		_set_valid_color(true)
		is_placeable.emit(true)

	# Update ghosts when an overlap changes
	_update_connection_ghosts()

# --------------------------------------------
# --- Visual Feedback ------------------------
# --------------------------------------------
func _set_valid_color(valid: bool) -> void:
	# Updates ghost tint based on placement validity
	ghost_sprite.modulate = VALID_COLOR if valid else INVALID_COLOR

func _update_connection_ghosts() -> void:
	# Safety
	if current_building_type == DataTypes.BUILDING_TYPE.NULL or not ghost_sprite.visible:
		_clear_ghost_lines()
		return
	# Need network manager to query existing buildings
	if not _network_manager:
		return

	# For each registered building, check if it would connect to the ghost using the same logic as NetworkManager
	var targets: Array = []
	for other in _network_manager.registered_buildings:
		if not is_instance_valid(other):
			continue
		# Use the public static helper for connection logic
		if NetworkManager.can_buildings_connect(
			current_building_type,
			global_position,
			DataTypes.get_is_relay(current_building_type), # ghost is always is_relay (or could be settable if needed)
			other.building_type if other.has_method("get") else DataTypes.BUILDING_TYPE.NULL,
			other.global_position,
			other.is_relay if other.has_method("get") else false
		):
			targets.append(other)

	# Reuse existing Line2D nodes, create more if needed
	while _ghost_lines.size() < targets.size():
		var line := Line2D.new()
		line.width = GHOST_LINE_WIDTH
		line.default_color = GHOST_LINE_COLOR
		if ghost_lines_container:
			ghost_lines_container.add_child(line)
		else:
			add_child(line)
		_ghost_lines.append(line)

	# Update or hide extra lines
	for i in range(_ghost_lines.size()):
		if i < targets.size():
			var t = targets[i]
			var l: Line2D = _ghost_lines[i]
			l.points = [global_position, t.global_position]
			l.global_position = Vector2.ZERO  # Ensures points are in world space
			# Color indicates whether placement is valid (no overlaps)
			l.default_color = GHOST_LINE_COLOR if overlapping_areas.is_empty() else GHOST_LINE_INVALID_COLOR
			l.visible = true
		else:
			_ghost_lines[i].visible = false

func _clear_ghost_lines() -> void:
	for l in _ghost_lines:
		if is_instance_valid(l):
			l.queue_free()
	_ghost_lines.clear()
