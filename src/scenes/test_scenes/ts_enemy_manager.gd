extends Node2D

@export var enemy_manager: EnemyManager
@export var ground_map_layer: TileMapLayer

func _ready() -> void:
	# The InputManager autoload needs a reference to the ground layer to handle mouse-to-tile conversion.
	# In the main game, the BuildingManager does this. For this test scene, we must do it manually.
	InputManager.ground_layer = ground_map_layer

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		var mouse_pos: Vector2 = ground_map_layer.get_local_mouse_position()
		var tile_coord: Vector2i = ground_map_layer.local_to_map(mouse_pos)
		
		# Add a fixed amount of creeper for testing
		var creeper_amount: float = 100.0
		enemy_manager.add_ooze(tile_coord, creeper_amount)
		
		# Print the entire map for debugging
		#print("Creeper map updated: ", enemy_manager.ooze_map)

		# Mark the event as handled
		get_viewport().set_input_as_handled()
