class_name LandingMarker extends Node2D

const landing_marker_scene: PackedScene = preload("res://src/scenes/objects/landing_marker.tscn")
@onready var sprite_2d: Sprite2D = $Sprite2D

var texture_to_use: Texture2D = null

# ------------------------------------
# --- Engine Callbacks ---------------
# ------------------------------------
func _ready() -> void:
	sprite_2d.texture = texture_to_use
	
# ------------------------------------
# --- Public Methods / Constructor ---
# ------------------------------------
# LandingMarker constructor
static func new_landing_marker(building_type: DataTypes.BUILDING_TYPE, landing_position: Vector2) -> LandingMarker:
	# Create the new marker
	var new_marker = landing_marker_scene.instantiate()
	# Initialize the marker properties
	new_marker.global_position = landing_position
	new_marker.texture_to_use = DataTypes.get_landing_marker_texture(building_type)
	# return configured marker
	return new_marker
