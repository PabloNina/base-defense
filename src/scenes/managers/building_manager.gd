# =========================================
# BuildingManager.gd
# =========================================
# Handles Mouse tracking and Input Events related to Buildings
# Manages construction, selection, movement and other buildings actions(to be implemented)
# Comunicates with GhostBuilding for placement validity
class_name BuildingManager extends Node2D

const landing_marker_scene: PackedScene = preload("res://src/scenes/objects/landing_marker.tscn")

# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
@export var ground_layer: TileMapLayer
@export var buildings_layer: TileMapLayer
@export var user_interface: UserInterface
@export var network_manager: NetworkManager
# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
@onready var ghost_building: GhostBuilding = $GhostBuilding
# -----------------------------------------
# --- Mouse Tracking ----------------------
# -----------------------------------------
var mouse_position: Vector2
var tile_position: Vector2i
var tile_source_id: int
var local_tile_position: Vector2
# -----------------------------------------
# --- Building Tile IDs -------------------
# -----------------------------------------
# TileSet SceneCollection ID is 2
# Each building inside has an alternate ID used for placement
var command_center_id: int = 3
var is_command_center_placed: bool = false
# -----------------------------------------
# --- Construction State ------------------
# -----------------------------------------
var is_construction_state: bool = false
var is_building_placeable: bool = true
var building_to_build_id: int = 0
var ghost_tile_position: Vector2i
var buildable_tile_id: int = 0
# ---------------------------------------
# --- Move State -----------------------
# ---------------------------------------
var current_building_to_move: MovableBuilding = null
var is_move_state: bool = false
var is_group_move_state: bool = false
var buildings_to_move_group: Array[Building] = []
var formation_offsets: Array[Vector2] = []
var position_to_move: Vector2 = Vector2.ZERO
var landing_markers: Dictionary = {} # Key: building instance, Value: marker instance
# ---------------------------------------
# --- Multi Selection (Box) State -------
# ---------------------------------------
var is_box_selecting_state: bool = false
var selection_start_pos: Vector2 = Vector2.ZERO
var selection_end_pos: Vector2 = Vector2.ZERO
# -----------------------------------------
# --- Selection State ----
# -----------------------------------------
var selected_buildings: Array[Building] = []
var buildings: Array[Building] = []  # All active buildings
# -----------------------------------------
# --- Signals -----------------------------
# -----------------------------------------
# Emited when building is clicked and selected
# Connected to UserInterface
signal selection_changed(buildings: Array[Building])
signal building_deselected()
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	add_to_group("building_manager")
	# Dependency injection
	ghost_building._network_manager = network_manager

	# Subscribe to Ui signals
	user_interface.building_button_pressed.connect(_on_ui_building_button_pressed)
	user_interface.destroy_button_pressed.connect(_on_ui_destroy_button_pressed)
	user_interface.move_selection_pressed.connect(_on_ui_move_selection_pressed)
	
	# Start with Command Center selected 
	is_construction_state = true
	building_to_build_id = command_center_id
	ghost_building.set_building_type(DataTypes.BUILDING_TYPE.COMMAND_CENTER)

func _process(_delta: float) -> void:
	# If construction or move state are active update building ghost position and track mouse
	if is_construction_state or is_move_state or is_group_move_state:
		_get_cell_under_mouse()
		_update_ghost_tile_position(tile_position)

# ----------------------------------------------
# --- Public Methods / Building Registration ---
# ----------------------------------------------
func register_building(new_building: Building) -> void:
	if new_building not in buildings:
		buildings.append(new_building)
		new_building.clicked.connect(_on_building_clicked)
		
		if new_building is MovableBuilding:
			new_building.move_started.connect(_on_building_move_started)
			new_building.move_completed.connect(_on_building_move_completed)

func unregister_building(destroyed_building: Building) -> void:
	if destroyed_building not in buildings:
		return
	
	# Erase from buildings list
	buildings.erase(destroyed_building)
	# Remove tile from map so it can be used again
	var tile_coords = buildings_layer.local_to_map(destroyed_building.global_position)
	buildings_layer.erase_cell(tile_coords)

# -----------------------------------------
# --- Mouse Tile Tracking -----------------
# -----------------------------------------
func _get_cell_under_mouse() -> void:
	mouse_position = ground_layer.get_local_mouse_position()
	tile_position = ground_layer.local_to_map(mouse_position)
	tile_source_id = ground_layer.get_cell_source_id(tile_position)
	local_tile_position = ground_layer.map_to_local(tile_position)

# -----------------------------------------
# --- Construction State / Placement --------
# -----------------------------------------
func _place_building() -> void:
	# Only build on valid ground tiles
	if tile_source_id != buildable_tile_id:
		print("Invalid Placement")
		return

	# --- Command Center Logic ---
	if not is_command_center_placed and building_to_build_id == command_center_id:
		is_command_center_placed = true
		buildings_layer.set_cell(tile_position, 2, Vector2i.ZERO, building_to_build_id)
		is_construction_state = false
	elif is_command_center_placed and building_to_build_id == command_center_id:
		print("You can only have 1 Command Center!")
	elif is_command_center_placed and building_to_build_id != command_center_id:
		# Place regular building
		buildings_layer.set_cell(tile_position, 2, Vector2i.ZERO, building_to_build_id)

# -----------------------------------------
# --- Construction State / Helpers --------
# -----------------------------------------
func _select_building_to_build(new_building: DataTypes.BUILDING_TYPE) -> void:
	is_construction_state = true
	ghost_building.set_building_type(new_building)
	building_to_build_id = DataTypes.get_tilemap_id(new_building)

func _deselect_building_to_build() -> void:
	is_construction_state = false
	ghost_building.clear_preview()
	building_to_build_id = 0

# ----------------------------------------------
# ------ Construction State / Ghost Feedback -----
# ----------------------------------------------
func _update_ghost_tile_position(new_position: Vector2i) -> void:
	if ghost_tile_position == new_position:
		return
	ghost_tile_position = new_position
	ghost_building.position = local_tile_position

# Used in Mouse&Keyboard Input Handling to check if a building can be built or moved
# Called by the signal is_placeable emited everytime a building enters/exits BuildingGhost area2d
func _on_building_ghost_preview_is_placeable(value: bool) -> void:
	is_building_placeable = value
	
# -----------------------------------------
# --- Moving State Placement / Signals ----
# -----------------------------------------
func _move_building(building_to_move: MovableBuilding) -> void:
	building_to_move.start_move(local_tile_position)
	is_move_state = false
	current_building_to_move = null
	ghost_building.clear_preview()
	clear_selection()

func _move_building_selection() -> void:
	var new_centroid = local_tile_position
	
	for i in range(buildings_to_move_group.size()):
		var building = buildings_to_move_group[i]
		var offset = formation_offsets[i]
		var target_pos = new_centroid + offset
		
		# Snap to the grid
		var target_tile = buildings_layer.local_to_map(target_pos)
		var snapped_pos = buildings_layer.map_to_local(target_tile)
		
		if building is MovableBuilding:
			building.start_move(snapped_pos)

	is_group_move_state = false
	buildings_to_move_group.clear()
	formation_offsets.clear()
	ghost_building.clear_preview()

func _on_building_move_started(building: MovableBuilding, landing_position: Vector2) -> void:
	# If this building already has a marker, remove the old one
	if landing_markers.has(building):
		landing_markers[building].queue_free()

	# Create the new marker using LandingMarker constructor
	var new_marker = LandingMarker.new_landing_marker(building.building_type, landing_position)
	add_child(new_marker)

	# Store the new marker in the dictionary with the building as the key
	landing_markers[building] = new_marker

func _on_building_move_completed(building: MovableBuilding) -> void:
	# Check if a marker exists for this building
	if landing_markers.has(building):
		# Remove the marker from the scene and the dictionary
		landing_markers[building].queue_free()
		landing_markers.erase(building)

# -----------------------------------------
# --- Selection Logic ---------------------
# -----------------------------------------
func _on_building_clicked(clicked_building: Building) -> void:
	if is_construction_state:
		return

	if selected_buildings.size() == 1 and selected_buildings[0] == clicked_building:
		clear_selection()
	else:
		clear_selection()
		selected_buildings.append(clicked_building)
		_update_selection()

func _select_weapons_in_box() -> void:
	var selection_box = Rect2(selection_start_pos, selection_end_pos - selection_start_pos).abs()
	clear_selection()

	var weapons_in_scene = get_tree().get_nodes_in_group("weapons")
	for weapon in weapons_in_scene:
		if selection_box.has_point(weapon.global_position):
			selected_buildings.append(weapon)
	
	_update_selection()

func clear_selection() -> void:
	for building in selected_buildings:
		if is_instance_valid(building):
			building.deselect()
	selected_buildings.clear()
	_update_selection()

func _update_selection() -> void:
	if selected_buildings.is_empty():
		building_deselected.emit()
	else:
		for building in selected_buildings:
			if is_instance_valid(building):
				building.select()
		selection_changed.emit(selected_buildings)

# ---------------------------------------
# --- Multi Selection / Drag Box --------
# ---------------------------------------
func _draw() -> void:
	if is_box_selecting_state:
		var rect = Rect2(selection_start_pos, selection_end_pos - selection_start_pos)
		# Draw a semi-transparent blue rectangle
		draw_rect(rect, Color(0, 0.5, 1, 0.2))
		# Draw a thin blue border
		draw_rect(rect, Color(0, 0.5, 1, 1), false, 1.0)

# -----------------------------------------
# --- Mouse and Keyboard Input Handling ---
# -----------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# --- Selection Box ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed() and not is_construction_state and not is_move_state and not is_group_move_state:
			is_box_selecting_state = true
			selection_start_pos = get_global_mouse_position()
			selection_end_pos = selection_start_pos
			clear_selection()
		elif not event.is_pressed() and is_box_selecting_state:
			is_box_selecting_state = false
			# To avoid calling selection on a single click, check if the box is a certain size
			if selection_start_pos.distance_to(selection_end_pos) > 5:
				_select_weapons_in_box()
			queue_redraw()

	if event is InputEventMouseMotion and is_box_selecting_state:
		selection_end_pos = get_global_mouse_position()
		queue_redraw()

	# --- Construction/Move placement ---
	if event.is_action_pressed("left_mouse"):
		if is_construction_state and is_building_placeable:
			_place_building()
		elif is_move_state and is_building_placeable:
			_move_building(current_building_to_move)
		elif is_group_move_state and is_building_placeable:
			_move_building_selection()

	# --- Selection: Building Hotkeys ---
	if event.is_action_pressed("key_1"):
		_select_building_to_build(DataTypes.BUILDING_TYPE.RELAY)
	elif event.is_action_pressed("key_2"):
		_select_building_to_build(DataTypes.BUILDING_TYPE.GUN_TURRET)
	elif event.is_action_pressed("key_3"):
		_select_building_to_build(DataTypes.BUILDING_TYPE.GENERATOR)
	elif event.is_action_pressed("key_4"):
		_select_building_to_build(DataTypes.BUILDING_TYPE.COMMAND_CENTER)

	# --- Cancel Construction Mode or Building selection---
	elif event.is_action_pressed("right_mouse"): # Cancel action
		if is_construction_state:
			_deselect_building_to_build()
		elif is_move_state or is_group_move_state:
			is_move_state = false
			is_group_move_state = false
			current_building_to_move = null
			buildings_to_move_group.clear()
			formation_offsets.clear()
			ghost_building.clear_preview()
		else:
			clear_selection()

# -----------------------------------------
# --- User Interface Input Handling ------
# -----------------------------------------
# Signals from UI BuildingsPanel
func _on_ui_building_button_pressed(building: DataTypes.BUILDING_TYPE) -> void:
	_select_building_to_build(building)

# Signals from UI BuildingActionPanel Buttons
func _on_ui_destroy_button_pressed(building_to_destroy: Building) -> void:
	building_to_destroy.destroy()

func _on_ui_move_selection_pressed() -> void:
	_enter_move_mode()

func _enter_move_mode() -> void:
	if selected_buildings.is_empty():
		return

	if selected_buildings.size() == 1 and selected_buildings[0] is MovableBuilding:
		is_move_state = true
		current_building_to_move = selected_buildings[0]
		ghost_building.set_building_type(current_building_to_move.building_type)
	else:
		is_group_move_state = true
		buildings_to_move_group = selected_buildings.duplicate()
		formation_offsets.clear()
		
		# Calculate centroid
		var centroid = Vector2.ZERO
		for building in buildings_to_move_group:
			centroid += building.global_position
		centroid /= buildings_to_move_group.size()
		
		# Calculate offsets
		for building in buildings_to_move_group:
			formation_offsets.append(building.global_position - centroid)
			
		# For now, ghost the first building type in the selection
		if not buildings_to_move_group.is_empty():
			ghost_building.set_building_type(buildings_to_move_group[0].building_type)
	
	clear_selection()
