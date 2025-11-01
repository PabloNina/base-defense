# =========================================
# BuildingManager.gd
# =========================================
# Handles Mouse tracking and Input Events related to Buildings
# Manages construction, selection, movement and other buildings actions(to be implemented)
# Comunicates with PlacementPreview for placement validity
class_name BuildingManager extends Node2D

const placement_preview_scene: PackedScene = preload("res://src/scenes/managers/placement_preview.tscn")

# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
@export var ground_layer: TileMapLayer
@export var buildings_container: Node2D
@export var user_interface: UserInterface
@export var network_manager: NetworkManager
# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
# The primary preview used for construction and single-building moves.
@onready var construction_preview: PlacementPreview = $PlacementPreview
@onready var double_click_timer: Timer = $DoubleClickTimer
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
var building_to_build_type: DataTypes.BUILDING_TYPE
var ghost_tile_position: Vector2i
var buildable_tile_id: int = 0
# --- Line Construction ---
var is_line_construction_state: bool = false
var line_construction_start_pos: Vector2i
var construction_line_previews: Array[PlacementPreview] = []
var construction_previews_validity: Dictionary = {}
var relay_line_previews: Array[Line2D] = []
# ---------------------------------------
# --- Move State -----------------------
# ---------------------------------------
var is_move_state: bool = false
var buildings_to_move_group: Array[Building] = []
var formation_offsets: Array[Vector2] = []
# --- Formation Scaling ---
# Adjusts the tightness of the group formation.
var formation_scale: float = 1.0
var formation_angle: float = 0.0
const MIN_FORMATION_SCALE: float = 1.0
const MAX_FORMATION_SCALE: float = 2.0
const FORMATION_SCALE_STEP: float = 0.5
var position_to_move: Vector2 = Vector2.ZERO
# Dictionary of active landing markers for buildings currently moving.
var landing_markers = {} # Key: building instance, Value: marker instance
# Array of active previews for group moves.
var move_previews: Array[PlacementPreview] = []
# Tracks the validity of each preview in a group move.
var move_previews_validity: Dictionary = {}
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
# --- Double Click Selection ---
var last_clicked_building: Building = null
# Window in seconds for double-click detection
var double_click_window: float = 0.2 
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
	
	double_click_timer.timeout.connect(_on_double_click_timer_timeout)
	
	# Subscribe to Ui signals
	user_interface.building_button_pressed.connect(_on_ui_building_button_pressed)
	user_interface.destroy_button_pressed.connect(_on_ui_destroy_button_pressed)
	user_interface.move_selection_pressed.connect(_on_ui_move_selection_pressed)
	user_interface.deactivate_button_pressed.connect(_on_ui_deactivate_button_pressed)
	
	# Connect to the construction preview's signal
	construction_preview.is_placeable.connect(_on_placement_preview_is_placeable)
	
	# Start with Command Center selected 
	_select_building_to_build(DataTypes.BUILDING_TYPE.COMMAND_CENTER)

func _process(_delta: float) -> void:
	# If construction or move state are active update building ghost position and track mouse
	if is_construction_state or is_move_state:
		_get_cell_under_mouse()
		# The tile_position is passed to the update_previews function
		_update_previews(tile_position)

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
	var building_scene: PackedScene = DataTypes.get_scene(building_to_build_type)
	if not building_scene:
		print("Error: Scene not found for building type ", building_to_build_type)
		return

	# --- Command Center Logic ---
	if not is_command_center_placed and building_to_build_type == DataTypes.BUILDING_TYPE.COMMAND_CENTER:
		is_command_center_placed = true
		_instance_and_place_building(building_scene, local_tile_position)
		is_construction_state = false
	elif is_command_center_placed and building_to_build_type == DataTypes.BUILDING_TYPE.COMMAND_CENTER:
		print("You can only have 1 Command Center!")
	elif is_command_center_placed and building_to_build_type != DataTypes.BUILDING_TYPE.COMMAND_CENTER:
		# Place regular building
		_instance_and_place_building(building_scene, local_tile_position)


# Places a line of buildings based on the final positions of the construction previews.
func _place_building_line() -> void:
	var building_scene: PackedScene = DataTypes.get_scene(building_to_build_type)
	if not building_scene:
		print("Error: Scene not found for building type ", building_to_build_type)
		return
		
	for preview in construction_line_previews:
		# Ensure the preview is visible and its position is valid before placing.
		if preview.visible and construction_previews_validity.get(preview, false):
			_instance_and_place_building(building_scene, preview.global_position)


func _instance_and_place_building(building_scene: PackedScene, building_position: Vector2) -> void:
	var new_building = building_scene.instantiate()
	new_building.global_position = building_position
	buildings_container.add_child(new_building)


# -----------------------------------------
# --- Construction State / Helpers --------
# -----------------------------------------
func _select_building_to_build(new_building_type: DataTypes.BUILDING_TYPE) -> void:
	# If the player was in a move state, cancel it before entering construction state.
	if is_move_state:
		_cancel_move_state()

	is_construction_state = true
	building_to_build_id = DataTypes.get_tilemap_id(new_building_type)
	building_to_build_type = new_building_type
	
	construction_preview.initialize(
		new_building_type,
		network_manager,
		DataTypes.get_ghost_texture(new_building_type),
		ground_layer,
		buildable_tile_id
	)
	construction_preview.visible = true

func _deselect_building_to_build() -> void:
	is_construction_state = false
	construction_preview.clear()
	building_to_build_id = 0

# ----------------------------------------------
# ------ Preview Feedback ----------------------
# ----------------------------------------------
# Updates the active placement previews based on the current state.
func _update_previews(new_position: Vector2i) -> void:
	# No need to update if the mouse hasn't moved to a new tile,
	# unless we are in line construction mode, which needs continuous updates.
	if ghost_tile_position == new_position and not is_line_construction_state:
		return
	ghost_tile_position = new_position
	
	# Update previews based on the current mode.
	if is_line_construction_state:
		_update_construction_line_previews()
	elif is_construction_state:
		construction_preview.update_position(local_tile_position)
	elif is_move_state:
		_update_move_previews()


# Called when a preview's placement validity changes.
func _on_placement_preview_is_placeable(is_valid: bool, preview: PlacementPreview) -> void:
	# If it's the main construction preview, update the global flag directly.
	if preview == construction_preview:
		is_building_placeable = is_valid
	# If it's a group move or line construction preview, update its status in the dictionary.
	else:
		if move_previews.has(preview):
			move_previews_validity[preview] = is_valid
		elif construction_line_previews.has(preview):
			construction_previews_validity[preview] = is_valid

		# The entire group is only placeable if all individual previews are valid.
		var all_valid = true
		# Check the validity dictionary that is currently in use.
		var validity_dict = move_previews_validity if is_move_state else construction_previews_validity
		for valid in validity_dict.values():
			if not valid:
				all_valid = false
				break
		is_building_placeable = all_valid


# -----------------------------------------
# --- Moving State Placement / Signals ----
# -----------------------------------------
func _move_building_selection() -> void:
	var new_centroid = local_tile_position
	
	for i in range(buildings_to_move_group.size()):
		var building = buildings_to_move_group[i]
		# Apply the current formation scale to the offset.
		var offset = formation_offsets[i] * formation_scale
		# Rotate the offset based on the current formation angle.
		offset = offset.rotated(deg_to_rad(formation_angle))
		var target_pos = new_centroid + offset
		
		# Snap to the grid
		var target_tile = ground_layer.local_to_map(target_pos)
		var snapped_pos = ground_layer.map_to_local(target_tile)
		
		if building is MovableBuilding:
			# Start move
			building.start_move(snapped_pos)

	is_move_state = false
	buildings_to_move_group.clear()
	formation_offsets.clear()
	_clear_move_previews()

# Creates and configures the placement previews for a group move.
func _create_move_previews() -> void:
	move_previews_validity.clear()
	for building in buildings_to_move_group:
		if building is MovableBuilding:
			var preview = placement_preview_scene.instantiate() as PlacementPreview
			add_child(preview)
			preview.initialize(
				building.building_type,
				network_manager,
				DataTypes.get_landing_marker_texture(building.building_type),
				ground_layer,
				buildable_tile_id
			)
			move_previews.append(preview)
			move_previews_validity[preview] = true # Assume valid at start
			preview.is_placeable.connect(_on_placement_preview_is_placeable)

# Updates the positions of all previews in a group move.
func _update_move_previews() -> void:
	var new_centroid = local_tile_position
	for i in range(move_previews.size()):
		var preview = move_previews[i]
		# Apply the current formation scale to the offset.
		var offset = formation_offsets[i] * formation_scale
		# Rotate the offset based on the current formation angle.
		offset = offset.rotated(deg_to_rad(formation_angle))
		var target_pos = new_centroid + offset
		
		# Snap to the grid
		var target_tile = ground_layer.local_to_map(target_pos)
		var snapped_pos = ground_layer.map_to_local(target_tile)
		preview.update_position(snapped_pos)

# Clears and frees all previews used in a group move.
func _clear_move_previews() -> void:
	for preview in move_previews:
		preview.queue_free()
	move_previews.clear()
	move_previews_validity.clear()


# Cancels the current single or group move state, resetting all related variables and clearing previews.
func _cancel_move_state() -> void:
	is_move_state = false
	buildings_to_move_group.clear()
	formation_offsets.clear()
	# Reset the formation scale and angle to their default values.
	formation_scale = 1.0
	formation_angle = 0.0
	construction_preview.clear()
	_clear_move_previews()


# Creates a static marker when a building's move begins.
func _on_building_move_started(building: MovableBuilding, landing_position: Vector2) -> void:
	if landing_markers.has(building):
		landing_markers[building].queue_free()

	var marker = placement_preview_scene.instantiate() as PlacementPreview
	add_child(marker)
	marker.initialize(
		building.building_type,
		network_manager,
		DataTypes.get_landing_marker_texture(building.building_type),
		ground_layer,
		buildable_tile_id,
		false
	)
	marker.global_position = landing_position
	landing_markers[building] = marker

# Removes the static marker when a building's move is complete.
func _on_building_move_completed(building: MovableBuilding) -> void:
	if landing_markers.has(building):
		landing_markers[building].queue_free()
		landing_markers.erase(building)


# --------------------------------------------------
# --- Line Construction Preview and Placement ------
# --------------------------------------------------
# Calculates and updates the positions of previews in a construction line.
func _update_construction_line_previews() -> void:
	var start_pos_pixels = ground_layer.map_to_local(line_construction_start_pos)
	var end_pos_pixels = local_tile_position
	
	var distance_pixels = start_pos_pixels.distance_to(end_pos_pixels)
	var building_type = building_to_build_type
	var optimal_dist_pixels = DataTypes.get_optimal_building_distance(building_type)

	var start_tile = line_construction_start_pos
	var end_tile = tile_position
	if building_to_build_type == DataTypes.BUILDING_TYPE.RELAY:
		if start_tile.x != end_tile.x and start_tile.y != end_tile.y:
			optimal_dist_pixels *= 0.95

	# Avoid division by zero and handle single-point case.
	if optimal_dist_pixels <= 0 or distance_pixels < optimal_dist_pixels:
		# If only one building fits, just show one preview.
		while construction_line_previews.size() > 1:
			var p = construction_line_previews.pop_back()
			if is_instance_valid(p): p.queue_free()
		if construction_line_previews.is_empty():
			var preview = placement_preview_scene.instantiate()
			add_child(preview)
			construction_line_previews.append(preview)
			preview.is_placeable.connect(_on_placement_preview_is_placeable)
		
		var single_preview = construction_line_previews[0]
		if not single_preview.is_initialized():
			single_preview.initialize(
				building_type,
				network_manager,
				DataTypes.get_ghost_texture(building_type),
				ground_layer,
				buildable_tile_id
			)
		# Position the single preview at the snapped start position.
		single_preview.update_position(start_pos_pixels)
		return

	var num_buildings = int(distance_pixels / optimal_dist_pixels) + 1

	# Create or remove previews to match the required number.
	while construction_line_previews.size() < num_buildings:
		var new_preview = placement_preview_scene.instantiate()
		add_child(new_preview)
		construction_line_previews.append(new_preview)
		new_preview.is_placeable.connect(_on_placement_preview_is_placeable)
	
	while construction_line_previews.size() > num_buildings:
		var p = construction_line_previews.pop_back()
		if is_instance_valid(p): p.queue_free()

	# --- Direct position calculation to avoid cumulative floating-point errors ---
	var direction = (end_pos_pixels - start_pos_pixels).normalized()
	for i in range(num_buildings):
		var preview = construction_line_previews[i]

		# Calculate the ideal position for each building directly from the start.
		var ideal_pos = start_pos_pixels + direction * optimal_dist_pixels * i
		var current_snapped_pos = ground_layer.map_to_local(ground_layer.local_to_map(ideal_pos))

		if not preview.is_initialized(): # Initialize only once.
			preview.initialize(
				building_type,
				network_manager,
				DataTypes.get_ghost_texture(building_type),
				ground_layer,
				buildable_tile_id
			)
		preview.update_position(current_snapped_pos)

	# --- Relay line previews ---
	for line in relay_line_previews:
		line.queue_free()
	relay_line_previews.clear()

	if building_to_build_type == DataTypes.BUILDING_TYPE.RELAY and construction_line_previews.size() > 1:
		for i in range(construction_line_previews.size() - 1):
			var from_pos = construction_line_previews[i].global_position
			var to_pos = construction_line_previews[i+1].global_position
			
			var dist = from_pos.distance_to(to_pos)
			var connection_range = DataTypes.get_connection_range(DataTypes.BUILDING_TYPE.RELAY)
			
			if dist <= connection_range:
				var line = Line2D.new()
				line.points = [from_pos, to_pos]
				line.width = 1.0
				line.default_color = Color.GREEN
				add_child(line)
				relay_line_previews.append(line)

# Clears and frees all previews used in line construction.
func _clear_construction_line_previews() -> void:
	for preview in construction_line_previews:
		preview.queue_free()
	construction_line_previews.clear()
	construction_previews_validity.clear()

	for line in relay_line_previews:
		line.queue_free()
	relay_line_previews.clear()


# -----------------------------------------
# --- Selection Logic ---------------------
# -----------------------------------------
# This function is called when a building's 'clicked' signal is emitted.
# It now handles both single and double clicks.
func _on_building_clicked(clicked_building: Building) -> void:
	if is_construction_state:
		return

	# If the timer is running and the same building is clicked, it's a double-click.
	if not double_click_timer.is_stopped() and clicked_building == last_clicked_building:
		double_click_timer.stop()
		_select_all_by_type(clicked_building.building_type)
		last_clicked_building = null # Reset for the next click sequence.
	# Otherwise, it's the first click of a potential double-click.
	else:
		double_click_timer.start(double_click_window) # 0.3-second window for a double-click.
		last_clicked_building = clicked_building


# Called when the double-click timer runs out, indicating a single click.
func _on_double_click_timer_timeout() -> void:
	# Ensure the building is still valid before proceeding.
	if not is_instance_valid(last_clicked_building):
		return

	# Standard single-click logic: deselect if already selected, otherwise select it.
	if selected_buildings.size() == 1 and selected_buildings[0] == last_clicked_building:
		clear_selection()
	else:
		clear_selection()
		selected_buildings.append(last_clicked_building)
		_update_selection()

	last_clicked_building = null # Reset for the next click sequence.


# Finds and selects all buildings of a specific type from the manager's list.
func _select_all_by_type(type: DataTypes.BUILDING_TYPE) -> void:
	clear_selection()
	# Filter all registered buildings to find ones that match the given type.
	var all_of_type = buildings.filter(func(b): return b.building_type == type)
	selected_buildings = all_of_type
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
		draw_rect(rect, Color(0, 0.5, 1, 0.2))
		draw_rect(rect, Color(0, 0.5, 1, 1), false, 1.0)

# -----------------------------------------
# --- Mouse and Keyboard Input Handling ---
# -----------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# --- Line Construction --- 
	if is_construction_state and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			is_line_construction_state = true
			line_construction_start_pos = tile_position
			construction_preview.clear() # Hide and disable single preview
			_update_construction_line_previews()
		elif not event.is_pressed() and is_line_construction_state:
			is_line_construction_state = false
			if is_building_placeable:
				# If it was just a click (no drag), place a single building.
				if line_construction_start_pos == tile_position:
					_place_building()
				else:
					_place_building_line()
			_clear_construction_line_previews()
			# Re-initialize the main preview for the next placement.
			construction_preview.initialize(
				building_to_build_type,
				network_manager,
				DataTypes.get_ghost_texture(building_to_build_type),
				ground_layer,
				buildable_tile_id
			)
			construction_preview.visible = true
			return # Consume the event

	# --- Mouse Motion ---
	if event is InputEventMouseMotion:
		if is_box_selecting_state:
			selection_end_pos = get_global_mouse_position()
			queue_redraw()
			return # Consume the event

	# --- Left Mouse Actions (that are not line construction) ---
	if event.is_action_pressed("left_mouse"):
		# This handles the move placement for single and group moves.
		if is_move_state and is_building_placeable:
			_move_building_selection()
		# This handles the start of a box selection.
		elif not is_construction_state and not is_move_state:
			is_box_selecting_state = true
			selection_start_pos = get_global_mouse_position()
			selection_end_pos = selection_start_pos
			clear_selection()

	# --- Left Mouse Release for Box Selection ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.is_pressed() and is_box_selecting_state:
		is_box_selecting_state = false
		if selection_start_pos.distance_to(selection_end_pos) > 5:
			_select_weapons_in_box()
		queue_redraw()

	# --- Formation Scale Adjustment ---
	# Adjust formation tightness if in group move state and the appropriate action is pressed.
	if is_move_state:
		if event.is_action_pressed("formation_tighter"):
			# Decrease scale to make the formation tighter
			formation_scale = clamp(formation_scale - FORMATION_SCALE_STEP, MIN_FORMATION_SCALE, MAX_FORMATION_SCALE)
			_update_move_previews()
		elif event.is_action_pressed("formation_looser"):
			# Increase scale to make the formation looser.
			formation_scale = clamp(formation_scale + FORMATION_SCALE_STEP, MIN_FORMATION_SCALE, MAX_FORMATION_SCALE)
			_update_move_previews()
		elif event.is_action_pressed("formation_rotate"):
			formation_angle = fmod(formation_angle + 90.0, 360.0)
			_update_move_previews()

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
		if is_line_construction_state:
			is_line_construction_state = false
			_clear_construction_line_previews()
			construction_preview.visible = true
		elif is_construction_state:
			_deselect_building_to_build()
		elif is_move_state:
			_cancel_move_state()
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

func _on_ui_deactivate_button_pressed(building_to_deactivate: Building) -> void:
	building_to_deactivate.set_deactivated_state(not building_to_deactivate.is_deactivated)
	building_to_deactivate.deselect()
	
func _on_ui_move_selection_pressed() -> void:
	_enter_move_mode()

#####################
func _enter_move_mode() -> void:
	if selected_buildings.is_empty():
		return

	if selected_buildings.size() == 1 and selected_buildings[0] is MovableBuilding:
		is_move_state = true
		buildings_to_move_group = selected_buildings.duplicate()
		formation_offsets.clear()
		formation_offsets.append(Vector2.ZERO)
		construction_preview.clear()
		_create_move_previews()
	else:
		is_move_state = true
		buildings_to_move_group = selected_buildings.duplicate()
		formation_offsets.clear()
		
		# When moving a group, calculate a compact line formation instead of preserving original spacing.
		# The formation can be adjusted by the player using the formation_tighter/formation_looser actions.
		var num_buildings = buildings_to_move_group.size()
		var tile_size = ground_layer.tile_set.tile_size
		
		for i in range(num_buildings):
			# Calculate position in a horizontal line formation. The offsets are centered around (0,0).
			var offset_x = (i - (num_buildings - 1) / 2.0) * tile_size.x
			var offset_y = 0
			formation_offsets.append(Vector2(offset_x, offset_y))
			
		construction_preview.clear()
		_create_move_previews()
	
	clear_selection()
