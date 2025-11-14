extends Node

@export var enemy_manager: EnemyManager
@export var ground_map_layer: TileMapLayer

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		var mouse_pos: Vector2 = ground_map_layer.get_local_mouse_position()
		var tile_coord: Vector2i = ground_map_layer.local_to_map(mouse_pos)
		var ooze_amount: float = 100.0

		if event.button_index == MOUSE_BUTTON_LEFT:
			enemy_manager.add_ooze(tile_coord, ooze_amount)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Call remove_ooze with an array containing the single tile to match the new signature.
			enemy_manager.remove_ooze([tile_coord], ooze_amount)
			get_viewport().set_input_as_handled()
