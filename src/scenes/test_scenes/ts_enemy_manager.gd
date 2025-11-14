extends Node2D

@export var ground_map_layer: TileMapLayer

func _ready() -> void:
	# The InputManager autoload needs a reference to the ground layer to handle mouse-to-tile conversion.
	# In the main game, the BuildingManager does this. For this test scene, we must do it manually.
	InputManager.ground_layer = ground_map_layer
