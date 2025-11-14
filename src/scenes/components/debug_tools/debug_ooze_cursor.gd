extends Node

@export var flow_manager: FlowManager
@export var ground_map_layer: TileMapLayer
@export var enabled: bool = false
@export var cursor_component_texture: Texture2D

func _ready() -> void:
	InputManager.debug_ooze_cursor_enabled.connect(_toggle_enabled)


func _toggle_enabled() -> void:
	enabled = not enabled
	if enabled:
		Input.set_custom_mouse_cursor(cursor_component_texture, Input.CURSOR_ARROW)
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventMouseButton and event.is_pressed():
		var mouse_pos: Vector2 = ground_map_layer.get_local_mouse_position()
		var tile_coord: Vector2i = ground_map_layer.local_to_map(mouse_pos)
		var ooze_amount: float = flow_manager.max_ooze_per_tile

		if event.button_index == MOUSE_BUTTON_LEFT:
			flow_manager.add_ooze(tile_coord, ooze_amount)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Call remove_ooze with an array containing the single tile to match the new signature.
			flow_manager.remove_ooze([tile_coord], ooze_amount)
			get_viewport().set_input_as_handled()
