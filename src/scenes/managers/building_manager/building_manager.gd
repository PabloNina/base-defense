# =========================================
# building_manager.gd
# =========================================
# Handles Mouse tracking and Input Events related to Buildings
# Manages construction, selection, movement and other buildings actions(to be implemented)
# Comunicates with PlacementPreview for placement validity
class_name BuildingManager extends Node2D
# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
@export var ground_layer: TileMapLayer
@export var buildings_container: Node2D
@export var user_interface: UserInterface
@export var grid_manager: GridManager
# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
@onready var ghost_preview_pool: GhostPreviewPool = $GhostPreviewPool
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
var is_command_center_placed: bool = false
# -----------------------------------------
# --- Construction State ------------------
# -----------------------------------------
var is_construction_state: bool = false
var is_building_placeable: bool = true
var building_to_build_type: GlobalData.BUILDING_TYPE
var ghost_tile_position: Vector2i
var buildable_tile_id: int = 0
var single_preview: GhostPreview = null
# --- Line Construction ---
var is_line_construction_state: bool = false
var line_construction_start_pos: Vector2i
var construction_line_previews: Array[GhostPreview] = []
var construction_previews_validity: Dictionary = {}
var relay_line_previews: Array[ConnectionLine] = []
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
var move_previews: Array[GhostPreview] = []
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
	# Ensure BuildingManager processes even when game is paused 
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("building_manager")
	# Connect timer signal for double click detection
	double_click_timer.timeout.connect(_on_double_click_timer_timeout)
	
	# Subscribe to Ui signals
	user_interface.building_button_pressed.connect(_on_ui_building_button_pressed)
	user_interface.destroy_button_pressed.connect(_on_ui_destroy_button_pressed)
	user_interface.move_selection_pressed.connect(_on_ui_move_selection_pressed)
	user_interface.deactivate_button_pressed.connect(_on_ui_deactivate_button_pressed)
	
	# Set ground_layer in InputManager
	InputManager.ground_layer = ground_layer
	
	# Connect to InputManager signals
	InputManager.map_left_clicked.connect(_on_InputManager_map_left_clicked)
	InputManager.map_left_released.connect(_on_InputManager_map_left_released)
	InputManager.map_right_clicked.connect(_on_InputManager_map_right_clicked)
	InputManager.box_selection_started.connect(_on_InputManager_box_selection_started)
	InputManager.box_selection_ended.connect(_on_InputManager_box_selection_ended)
	InputManager.build_relay_pressed.connect(func(): _select_building_to_build(GlobalData.BUILDING_TYPE.RELAY))
	InputManager.build_gun_turret_pressed.connect(func(): _select_building_to_build(GlobalData.BUILDING_TYPE.GUN_TURRET))
	InputManager.build_generator_pressed.connect(func(): _select_building_to_build(GlobalData.BUILDING_TYPE.GENERATOR))
	InputManager.build_command_center_pressed.connect(func(): _select_building_to_build(GlobalData.BUILDING_TYPE.COMMAND_CENTER))
	InputManager.formation_tighter_pressed.connect(_on_InputManager_formation_tighter_pressed)
	InputManager.formation_looser_pressed.connect(_on_InputManager_formation_looser_pressed)
	InputManager.formation_rotate_pressed.connect(_on_InputManager_formation_rotate_pressed)

	# Start with Command Center selected 
	_select_building_to_build(GlobalData.BUILDING_TYPE.COMMAND_CENTER)

func _process(_delta: float) -> void:
	# If construction or move state are active update building ghost position and track mouse
	if is_construction_state or is_move_state:
		_get_cell_under_mouse()
		# The tile_position is passed to the update_previews function
		_update_previews(tile_position)


# -----------------------------------------
# --- GhostPreview Pool Wrappers ------
# -----------------------------------------
func _get_placement_preview_from_pool() -> GhostPreview:
	return ghost_preview_pool.get_preview()

func _return_placement_preview_to_pool(preview: GhostPreview) -> void:
	ghost_preview_pool.return_preview(preview)
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
	var building_scene: PackedScene = GlobalData.get_packed_scene(building_to_build_type)
	if not building_scene:
		print("Error: Scene not found for building type ", building_to_build_type)
		return

	# --- Command Center Logic ---
	if not is_command_center_placed and building_to_build_type == GlobalData.BUILDING_TYPE.COMMAND_CENTER:
		is_command_center_placed = true
		_instance_and_place_building(building_scene, local_tile_position)
		is_construction_state = false
		if is_instance_valid(single_preview):
			single_preview.clear_ghost_preview() # Clear the preview after successful placement
	elif is_command_center_placed and building_to_build_type == GlobalData.BUILDING_TYPE.COMMAND_CENTER:
		print("You can only have 1 Command Center!")
	elif is_command_center_placed and building_to_build_type != GlobalData.BUILDING_TYPE.COMMAND_CENTER:
		# Place regular building
		_instance_and_place_building(building_scene, local_tile_position)


# Places a line of buildings based on the final positions of the construction previews.
func _place_building_line() -> void:
	var building_scene: PackedScene = GlobalData.get_packed_scene(building_to_build_type)
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
func _select_building_to_build(new_building_type: GlobalData.BUILDING_TYPE) -> void:
	# If the player was in a move state, cancel it before entering construction state.
	if is_move_state:
		_cancel_move_state()

	is_construction_state = true
	building_to_build_type = new_building_type
	
	if not is_instance_valid(single_preview):
		single_preview = _get_placement_preview_from_pool()
		add_child(single_preview)
		if not single_preview.is_placeable.is_connected(_on_ghost_preview_is_placeable):
			single_preview.is_placeable.connect(_on_ghost_preview_is_placeable)
	
	single_preview.initialize_ghost_preview(
		new_building_type,
		grid_manager,
		GlobalData.get_ghost_texture(new_building_type),
		ground_layer,
		buildable_tile_id
	)
	single_preview.visible = true

func _deselect_building_to_build() -> void:
	is_construction_state = false
	if is_instance_valid(single_preview):
		_return_placement_preview_to_pool(single_preview)
		single_preview = null

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
		if is_instance_valid(single_preview): 
			single_preview.update_ghost_preview_position(local_tile_position)
	elif is_move_state:
		_update_move_previews()


# Called when a preview's placement validity changes.
func _on_ghost_preview_is_placeable(is_valid: bool, preview: GhostPreview) -> void:
	# If it's the main construction preview, update the global flag directly.
	if preview == single_preview:
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
			var preview = _get_placement_preview_from_pool()
			add_child(preview)
			preview.initialize_ghost_preview(
				building.building_type,
				grid_manager,
				GlobalData.get_landing_marker_texture(building.building_type),
				ground_layer,
				buildable_tile_id
			)
			move_previews.append(preview)
			move_previews_validity[preview] = true # Assume valid at start

			# Prevents connecting multiple times the same signal when moving buildings
			if not preview.is_placeable.is_connected(_on_ghost_preview_is_placeable):
				preview.is_placeable.connect(_on_ghost_preview_is_placeable)

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
		preview.update_ghost_preview_position(snapped_pos)

# Clears and frees all previews used in a group move.
func _clear_move_previews() -> void:
	for preview in move_previews:
		_return_placement_preview_to_pool(preview)
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
	if is_instance_valid(single_preview): 
		single_preview.clear_ghost_preview()
	_clear_move_previews()


# Creates a static marker when a building's move begins.
func _on_building_move_started(building: MovableBuilding, landing_position: Vector2) -> void:
	if landing_markers.has(building):
		_return_placement_preview_to_pool(landing_markers[building])

	var marker = _get_placement_preview_from_pool()
	add_child(marker)
	marker.initialize_ghost_preview(
		building.building_type,
		grid_manager,
		GlobalData.get_landing_marker_texture(building.building_type),
		ground_layer,
		buildable_tile_id,
		false
	)
	marker.global_position = landing_position
	landing_markers[building] = marker

# Removes the static marker when a building's move is complete.
func _on_building_move_completed(building: MovableBuilding) -> void:
	if landing_markers.has(building):
		_return_placement_preview_to_pool(landing_markers[building])
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
	var optimal_dist_pixels = GlobalData.get_optimal_building_distance(building_type)

	var start_tile = line_construction_start_pos
	var end_tile = tile_position
	if building_to_build_type == GlobalData.BUILDING_TYPE.RELAY:
		if start_tile.x != end_tile.x and start_tile.y != end_tile.y:
			optimal_dist_pixels *= 0.95

	# Avoid division by zero and handle single-point case.
	if optimal_dist_pixels <= 0 or distance_pixels < optimal_dist_pixels:
		# If only one building fits, just show one preview.
		while construction_line_previews.size() > 1:
			var p = construction_line_previews.pop_back()
			if is_instance_valid(p): 
				_return_placement_preview_to_pool(p)
		if construction_line_previews.is_empty():
			var preview = _get_placement_preview_from_pool()
			add_child(preview)
			construction_line_previews.append(preview)
			if not preview.is_placeable.is_connected(_on_ghost_preview_is_placeable):
				preview.is_placeable.connect(_on_ghost_preview_is_placeable)
		
		var _single_preview = construction_line_previews[0]
		if not _single_preview.is_ghost_preview_initialized():
			_single_preview.initialize_ghost_preview(
				building_type,
				grid_manager,
				GlobalData.get_ghost_texture(building_type),
				ground_layer,
				buildable_tile_id
			)
		# Position the single preview at the snapped start position.
		_single_preview.update_ghost_preview_position(start_pos_pixels)
		return

	var num_buildings = int(distance_pixels / optimal_dist_pixels) + 1

	# Create or remove previews to match the required number.
	while construction_line_previews.size() < num_buildings:
		var new_preview = _get_placement_preview_from_pool()
		add_child(new_preview)
		construction_line_previews.append(new_preview)
		if not new_preview.is_placeable.is_connected(_on_ghost_preview_is_placeable):
			new_preview.is_placeable.connect(_on_ghost_preview_is_placeable)
	
	while construction_line_previews.size() > num_buildings:
		var p = construction_line_previews.pop_back()
		if is_instance_valid(p): 
			_return_placement_preview_to_pool(p)

	# --- Direct position calculation to avoid cumulative floating-point errors ---
	var direction = (end_pos_pixels - start_pos_pixels).normalized()
	for i in range(num_buildings):
		var preview = construction_line_previews[i]

		# Calculate the ideal position for each building directly from the start.
		var ideal_pos = start_pos_pixels + direction * optimal_dist_pixels * i
		var current_snapped_pos = ground_layer.map_to_local(ground_layer.local_to_map(ideal_pos))

		if not preview.is_ghost_preview_initialized(): # Initialize only once.
			preview.initialize_ghost_preview(
				building_type,
				grid_manager,
				GlobalData.get_ghost_texture(building_type),
				ground_layer,
				buildable_tile_id
			)
		preview.update_ghost_preview_position(current_snapped_pos)

	# --- Relay line previews ---
	for line in relay_line_previews:
		grid_manager.return_connection_line_to_pool(line)
	relay_line_previews.clear()

	if building_to_build_type == GlobalData.BUILDING_TYPE.RELAY and construction_line_previews.size() > 1:
		for i in range(construction_line_previews.size() - 1):
			var preview_a = construction_line_previews[i]
			var preview_b = construction_line_previews[i+1]
			var from_pos = preview_a.global_position
			var to_pos = preview_b.global_position
			
			var dist = from_pos.distance_to(to_pos)
			var connection_range = GlobalData.get_connection_range(GlobalData.BUILDING_TYPE.RELAY)
			
			if dist <= connection_range:
				var line: ConnectionLine = grid_manager.get_connection_line_from_pool()
				add_child(line)
				var is_line_valid = construction_previews_validity.get(preview_a, false) and construction_previews_validity.get(preview_b, false)
				line.setup_preview_connections(from_pos, to_pos, is_line_valid)
				relay_line_previews.append(line)

# Clears and frees all previews used in line construction.
func _clear_construction_line_previews() -> void:
	for preview in construction_line_previews:
		_return_placement_preview_to_pool(preview)
	construction_line_previews.clear()
	construction_previews_validity.clear()

	for line in relay_line_previews:
		grid_manager.return_connection_line_to_pool(line)
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

	# Reset for the next click sequence.
	last_clicked_building = null


# Finds and selects all buildings of a specific type from the managers list.
func _select_all_by_type(type: GlobalData.BUILDING_TYPE) -> void:
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
			building.hide_selection_sprite()
	selected_buildings.clear()
	_update_selection()

func _update_selection() -> void:
	if selected_buildings.is_empty():
		building_deselected.emit()
	else:
		for building in selected_buildings:
			if is_instance_valid(building):
				building.show_selection_sprite()
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
# --- InputManager Signal Handlers ------
# -----------------------------------------
func _on_InputManager_map_left_clicked(click_position: Vector2i):
	if is_construction_state:
		is_line_construction_state = true
		line_construction_start_pos = click_position
		if is_instance_valid(single_preview): 
			single_preview.visible = false # Hide and disable single preview
		_update_construction_line_previews()
	elif is_move_state and is_building_placeable:
		_move_building_selection()
	elif not is_construction_state and not is_move_state:
		is_box_selecting_state = true
		selection_start_pos = get_global_mouse_position()
		selection_end_pos = selection_start_pos
		clear_selection()

func _on_InputManager_map_left_released(release_position: Vector2i):
	if is_line_construction_state:
		is_line_construction_state = false
		if is_building_placeable:
			if line_construction_start_pos == release_position:
				_place_building()
			else:
				_place_building_line()
		_clear_construction_line_previews()
		
		# Only re-initialize the single preview if we are still in construction mode
		# (i.e., we didn't just place the one-and-only Command Center).
		if is_construction_state:
			if not is_instance_valid(single_preview):
				single_preview = _get_placement_preview_from_pool()
				add_child(single_preview)
				if not single_preview.is_placeable.is_connected(_on_ghost_preview_is_placeable):
					single_preview.is_placeable.connect(_on_ghost_preview_is_placeable)
			
			single_preview.initialize_ghost_preview(
				building_to_build_type,
				grid_manager,
				GlobalData.get_ghost_texture(building_to_build_type),
				ground_layer,
				buildable_tile_id
			)
			single_preview.visible = true
	elif is_box_selecting_state:
		is_box_selecting_state = false
		if selection_start_pos.distance_to(selection_end_pos) > 5:
			_select_weapons_in_box()
		queue_redraw()

func _on_InputManager_map_right_clicked(_click_position: Vector2i):
	if is_line_construction_state:
		is_line_construction_state = false
		_clear_construction_line_previews()
		if is_instance_valid(single_preview): 
			single_preview.visible = true
	elif is_construction_state:
		_deselect_building_to_build()
	elif is_move_state:
		_cancel_move_state()
	else:
		clear_selection()

func _on_InputManager_box_selection_started(start_position: Vector2):
	if not is_construction_state and not is_move_state:
		is_box_selecting_state = true
		selection_start_pos = start_position
		selection_end_pos = start_position
		clear_selection()

func _on_InputManager_box_selection_ended(end_position: Vector2):
	if is_box_selecting_state:
		selection_end_pos = end_position
		queue_redraw()

func _on_InputManager_formation_tighter_pressed():
	if is_move_state:
		formation_scale = clamp(formation_scale - FORMATION_SCALE_STEP, MIN_FORMATION_SCALE, MAX_FORMATION_SCALE)
		_update_move_previews()

func _on_InputManager_formation_looser_pressed():
	if is_move_state:
		formation_scale = clamp(formation_scale + FORMATION_SCALE_STEP, MIN_FORMATION_SCALE, MAX_FORMATION_SCALE)
		_update_move_previews()

func _on_InputManager_formation_rotate_pressed():
	if is_move_state:
		formation_angle = fmod(formation_angle + 90.0, 360.0)
		_update_move_previews()

# -----------------------------------------
# --- User Interface Input Handling ------
# -----------------------------------------
# Signals from UI BuildingsPanel
func _on_ui_building_button_pressed(building: GlobalData.BUILDING_TYPE) -> void:
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
		if is_instance_valid(single_preview): 
			single_preview.clear_ghost_preview()
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
			
		if is_instance_valid(single_preview): 
			single_preview.clear_ghost_preview()
		_create_move_previews()
	
	clear_selection()
