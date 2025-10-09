class_name BuildingManager
extends Node

@export var network_manager: NetworkManager
@export var ground_layer: TileMapLayer
@export var buildings_layer: TileMapLayer


@onready var highlight_marker: HighLightMarker = $HighlightMarker

var mouse_position: Vector2
var tile_position: Vector2i
var tile_source_id: int
var local_tile_position: Vector2
var highlighted_tile_position: Vector2i

var selected_building_id: int = 0
var energy_relay_id: int = 5
var energy_generator_id: int = 4
var command_center_id: int = 3
var plasma_cannor_id: int = 6

var building_mode: bool = false
var is_placeable : bool = true
var is_command_center: bool = false
var current_selected_building: Relay = null

func _ready() -> void:
	network_manager.building_selected.connect(on_building_selected)

func _process(_delta: float) -> void:
	# if true start building preview
	if building_mode == true:
		get_cell_under_mouse()
		update_highlighted_tile_position(tile_position)


func get_cell_under_mouse() -> void:
	mouse_position = ground_layer.get_local_mouse_position()
	tile_position = ground_layer.local_to_map(mouse_position)
	tile_source_id = ground_layer.get_cell_source_id(tile_position)
	local_tile_position = ground_layer.map_to_local(tile_position)
	#print("Mouse position: ", mouse_position, "Cell position: ", cell_position, "Cell source id: ", cell_source_id )


func update_highlighted_tile_position(new_position: Vector2i):
	if highlighted_tile_position == new_position:
			return
			
	highlighted_tile_position = new_position
	highlight_marker.position = local_tile_position

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("left_mouse") and building_mode == true and is_placeable == true:
		#
		place_building()
		#get_viewport().set_input_as_handled()
		
	if event.is_action_pressed("key_1"):
		selected_building_id = energy_relay_id
		building_mode = true
		highlight_marker.update_marker(Vector2(16, 16), true)
		#print("energy relay selected")
	if event.is_action_pressed("key_2"):
		selected_building_id = plasma_cannor_id
		building_mode = true
		highlight_marker.update_marker(Vector2(16, 16), true)
		#print("energy generator selected")
	if event.is_action_pressed("key_3"):
		selected_building_id = command_center_id
		building_mode = true
		highlight_marker.update_marker(Vector2(48, 48), true)
		#print("command center selected")
	if event.is_action_pressed("right_mouse"):
		building_mode = false
		selected_building_id = 0
		highlight_marker.update_marker(Vector2(16, 16), false)
		#print("Building mode deactivated")

func place_building() -> void:
	# Check if tile is ground
	if tile_source_id == 0:
		# Check if we have a command center and if it is the selected buiding
		if is_command_center == false and selected_building_id == command_center_id:
			is_command_center = true
			buildings_layer.set_cell(tile_position, 2, Vector2i.ZERO, selected_building_id)
			
		if is_command_center == false and selected_building_id != command_center_id:
			print("Build Command Center First!")
			
		if is_command_center == true and selected_building_id == command_center_id:
			print("You can only have 1 Command Center!")
			
		if is_command_center == true and selected_building_id != command_center_id:
			# place building in layer
			buildings_layer.set_cell(tile_position, 2, Vector2i.ZERO, selected_building_id)
		
		# disable building mode and marker
		#building_mode = false
		#highlight_marker.update_marker(Vector2(16, 16), false)
		

		# Debug
		#print("Building Constructed")
	else:
		print("Invalid Placement")

func destroy_building() -> void:
	#buildings_layer.set_cell(tile_position, 2, Vector2i.ZERO, -1)
	#buildings_layer.erase_cell(tile_position)
	#print("building destroyed")
	pass

func _on_highlight_marker_is_placeable(value: bool) -> void:
	is_placeable = value





func on_building_selected(clicked_building: Relay) -> void:
	if current_selected_building == clicked_building:
		# Deselect if clicked again
		current_selected_building = null
		
	else:
		# Select new building
		print("building selected")
		current_selected_building = clicked_building
		
		
	
