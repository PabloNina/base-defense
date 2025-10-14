# =========================================
# BuildingGhostPreview.gd
# =========================================
# Works as a placement preview, collision and validity helper

class_name BuildingGhostPreview
extends Area2D

# --------------------------------------------
# --- Marker Configuration -------------------
# --------------------------------------------
# Visual and logical parameters for placement preview
var size: Vector2 = Vector2(16, 16)
var color: Color = Color(1.0, 1.0, 0.0, 0.5)

# Reference to the collision shape used for overlap detection
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

# Reference to the ghost_sprite used for building preview
@onready var ghost_sprite: Sprite2D = $GhostSprite

# Signal emitted whenever placement validity changes
# Listener: BuildingManager -> _on_building_ghost_preview_is_placeable(value: bool)
signal is_placeable(value: bool)

# Keeps track of overlapping placement-blocking areas
var overlapping_areas: Array[Area2D] = []

# --------------------------------------------
# --- Engine Callbacks -----------------------
# --------------------------------------------
func _ready() -> void:
	# Marker starts hidden until building preview is active
	visible = false


func _draw() -> void:
	# Update collision shape and draw visual marker
	collision_shape_2d.shape.size = size
	draw_rect(Rect2(-size / 2.0, size), color)


# --------------------------------------------
# --- Public API -----------------------------
# --------------------------------------------
func update_ghost(new_size: Vector2, new_visible: bool) -> void:
	#Updates the visual and logical state of the placement marker.
	#Used by BuildingManager when previewing new building placement.
	size = new_size
	visible = new_visible
	queue_redraw()


# --------------------------------------------
# --- Overlap Handling -----------------------
# --------------------------------------------
func _on_area_entered(area: Area2D) -> void:
	# Called automatically when another area enters the marker.
	# If there is an overlap, placement becomes invalid (red marker).
	overlapping_areas.append(area)
	color = Color(1.0, 0.0, 0.0, 0.5)  # Red tint for blocked placement
	queue_redraw()
	is_placeable.emit(false)


func _on_area_exited(area: Area2D) -> void:
	# Called when an area leaves the marker.
	# If no more overlaps exist, placement becomes valid again (yellow marker).
	overlapping_areas.erase(area)
	if overlapping_areas.is_empty():
		color = Color(1.0, 1.0, 0.0, 0.5)  # Yellow tint for valid placement
		queue_redraw()
		is_placeable.emit(true)
