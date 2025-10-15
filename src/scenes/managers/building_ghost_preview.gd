# =========================================
# BuildingGhostPreview.gd
# =========================================
# Displays a semi-transparent ghost of the selected building.
# Handles placement validity (via Area2D overlap) and visual tinting.
# Communicates with BuildingManager to confirm whether placement is valid.

class_name BuildingGhostPreview
extends Area2D

# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
# Reference to the collision shape used for overlap detection
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
# Reference to the ghost_sprite used for building preview
@onready var ghost_sprite: Sprite2D = $GhostSprite

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
const VALID_COLOR: Color = Color(1.0, 1.0, 0.0, 0.6)  # (placeable)
const INVALID_COLOR: Color = Color(1.0, 0.0, 0.0, 0.6)  # (blocked)

# --------------------------------------------
# --- Engine Callbacks -----------------------
# --------------------------------------------
func _ready() -> void:
	# Ghost starts hidden until building preview is active
	ghost_sprite.visible = false
	ghost_sprite.modulate = VALID_COLOR  # Default color

# --------------------------------------------
# --- Public API -----------------------------
# --------------------------------------------

func set_building_type(new_type: DataTypes.BUILDING_TYPE) -> void:
	# Updates the ghost appearance based on selected building type.
	# Pulls ghost texture from DataTypes.
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


func clear_preview() -> void:
	# Hides and resets the ghost completely
	current_building_type = DataTypes.BUILDING_TYPE.NULL
	ghost_sprite.texture = null
	ghost_sprite.visible = false
	overlapping_areas.clear()

# --------------------------------------------
# --- Overlap Handling -----------------------
# --------------------------------------------
func _on_area_entered(area: Area2D) -> void:
	# Called automatically when another area enters the marker.
	# If there is an overlap, placement becomes invalid (red marker).
	overlapping_areas.append(area)
	_set_valid_color(false)
	is_placeable.emit(false)


func _on_area_exited(area: Area2D) -> void:
	# Called when an area leaves the marker.
	# If no more overlaps exist, placement becomes valid again (yellow marker).
	overlapping_areas.erase(area)
	if overlapping_areas.is_empty():
		_set_valid_color(true)
		is_placeable.emit(true)

# --------------------------------------------
# --- Visual Feedback ------------------------
# --------------------------------------------
func _set_valid_color(valid: bool) -> void:
	# Updates ghost tint based on placement validity
	ghost_sprite.modulate = VALID_COLOR if valid else INVALID_COLOR
