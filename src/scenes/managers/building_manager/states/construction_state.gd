extends BuildingManagerState

# -----------------------------------------
# --- Construction State ------------------
# -----------------------------------------
var is_building_placeable: bool = true
var building_to_build_type: GlobalData.BUILDING_TYPE
var ghost_tile_position: Vector2i

# Single Preview
var single_preview: GhostPreview = null

# Line Construction
var is_line_construction_state: bool = false
var line_construction_start_pos: Vector2i
var construction_line_previews: Array[GhostPreview] = []
var construction_previews_validity: Dictionary = {}
var relay_line_previews: Array[ConnectionLine] = []



func _on_process(_delta: float) -> void:
	# Update previews based on the current mode (single or line)
	if is_line_construction_state:
		_update_construction_line_previews()
	else:
		if is_instance_valid(single_preview): 
			single_preview.update_ghost_preview_position(building_manager.local_tile_position)

func _on_physics_process(_delta : float) -> void:
	pass

func _on_next_transitions() -> void:
	pass


func _on_enter() -> void:
	super()
	# When entering the state, create a single preview for the selected building
	update_ghost_preview()


func _on_exit() -> void:
	# Clean up all previews when exiting the state
	if is_instance_valid(single_preview):
		building_manager.return_placement_preview_to_pool(single_preview)
		single_preview = null
	_clear_construction_line_previews()
	
	# Reset line construction flag
	is_line_construction_state = false

# -----------------------------------------
# --- InputManager Signal Handlers ------
# -----------------------------------------
func _on_InputManager_map_left_clicked(_click_position: Vector2i) -> void:
	is_line_construction_state = true
	line_construction_start_pos = building_manager.tile_position
	if is_instance_valid(single_preview): 
		single_preview.visible = false # Hide single preview during line construction
	_update_construction_line_previews()

func _on_InputManager_map_left_released(_release_position: Vector2i) -> void:
	if is_line_construction_state:
		is_line_construction_state = false
		if is_building_placeable:
			if line_construction_start_pos == building_manager.tile_position:
				_place_building()
			else:
				_place_building_line()
		
		_clear_construction_line_previews()
		
		# If we havent placed the command center yet exit to selection state
		if not building_manager.is_command_center_placed:
			transition.emit("SelectingState")
		else:
			# Re-show the single preview
			if is_instance_valid(single_preview):
				single_preview.visible = true

func _on_InputManager_map_right_clicked(_click_position: Vector2i) -> void:
	# Right click cancels construction and returns to selection state
	transition.emit("SelectingState")


# -----------------------------------------
# --- Placement Logic ---------------------
# -----------------------------------------
func _place_building() -> void:
	var building_scene: PackedScene = GlobalData.get_packed_scene(building_to_build_type)
	if not building_scene:
		return

	# --- Command Center Logic ---
	if not building_manager.is_command_center_placed and building_to_build_type == GlobalData.BUILDING_TYPE.COMMAND_CENTER:
		building_manager.is_command_center_placed = true
		building_manager.construct_building(building_scene, building_manager.local_tile_position)
		transition.emit("SelectingState")
	elif building_manager.is_command_center_placed and building_to_build_type == GlobalData.BUILDING_TYPE.COMMAND_CENTER:
		print("You can only have 1 Command Center!")
	elif building_manager.is_command_center_placed:
		building_manager.construct_building(building_scene, building_manager.local_tile_position)
	else:
		print("Build Command Center First!")

# Places a line of buildings based on the final positions of the construction previews.
func _place_building_line() -> void:
	var building_scene: PackedScene = GlobalData.get_packed_scene(building_to_build_type)
	if not building_scene:
		return
		
	for preview in construction_line_previews:
		# Ensure the preview is visible and its position is valid before placing.
		if preview.visible and construction_previews_validity.get(preview, false):
			building_manager.construct_building(building_scene, preview.global_position)

# ----------------------------------------------
# ------ Ghost Preview Update ------------------
# ----------------------------------------------
func update_ghost_preview() -> void:
	if not is_instance_valid(single_preview):
		single_preview = building_manager.get_placement_preview_from_pool()
		building_manager.add_child(single_preview)
		if not single_preview.is_placeable.is_connected(_on_ghost_preview_is_placeable):
			single_preview.is_placeable.connect(_on_ghost_preview_is_placeable)
	
	single_preview.initialize_ghost_preview(
		building_to_build_type,
		building_manager.grid_manager,
		GlobalData.get_ghost_texture(building_to_build_type),
		building_manager.ground_layer,
		building_manager.buildable_tile_id
	)
	single_preview.visible = true

# ----------------------------------------------
# ------ Ghost Preview Validity Feedback -------
# ----------------------------------------------
# Called when a preview's placement validity changes.
func _on_ghost_preview_is_placeable(is_valid: bool, preview: GhostPreview) -> void:
	if preview == single_preview:
		is_building_placeable = is_valid
	else:
		if construction_line_previews.has(preview):
			construction_previews_validity[preview] = is_valid

		var all_valid = true
		for valid in construction_previews_validity.values():
			if not valid:
				all_valid = false
				break
		is_building_placeable = all_valid


# --------------------------------------------------
# --- Line Construction Preview and Placement ------
# --------------------------------------------------
# Calculates and updates the positions of previews in a construction line.
func _update_construction_line_previews() -> void:
	var start_pos_pixels = building_manager.ground_layer.map_to_local(line_construction_start_pos)
	var end_pos_pixels = building_manager.local_tile_position
	
	var distance_pixels = start_pos_pixels.distance_to(end_pos_pixels)
	var optimal_dist_pixels = GlobalData.get_optimal_building_distance(building_to_build_type)

	var start_tile = line_construction_start_pos
	var end_tile = building_manager.tile_position
	if building_to_build_type == GlobalData.BUILDING_TYPE.RELAY:
		if start_tile.x != end_tile.x and start_tile.y != end_tile.y:
			optimal_dist_pixels *= 0.95

	if optimal_dist_pixels <= 0 or distance_pixels < optimal_dist_pixels:
		while construction_line_previews.size() > 1:
			var p = construction_line_previews.pop_back()
			if is_instance_valid(p): 
				building_manager.return_placement_preview_to_pool(p)
		if construction_line_previews.is_empty():
			var preview = building_manager.get_placement_preview_from_pool()
			building_manager.add_child(preview)
			construction_line_previews.append(preview)
			if not preview.is_placeable.is_connected(_on_ghost_preview_is_placeable):
				preview.is_placeable.connect(_on_ghost_preview_is_placeable)
		
		var _preview = construction_line_previews[0]
		if not _preview.is_ghost_preview_initialized():
			_preview.initialize_ghost_preview(
				building_to_build_type, building_manager.grid_manager,
				GlobalData.get_ghost_texture(building_to_build_type),
				building_manager.ground_layer, building_manager.buildable_tile_id
			)
		_preview.update_ghost_preview_position(start_pos_pixels)
		return

	var num_buildings = int(distance_pixels / optimal_dist_pixels) + 1

	while construction_line_previews.size() < num_buildings:
		var new_preview = building_manager.get_placement_preview_from_pool()
		building_manager.add_child(new_preview)
		construction_line_previews.append(new_preview)
		if not new_preview.is_placeable.is_connected(_on_ghost_preview_is_placeable):
			new_preview.is_placeable.connect(_on_ghost_preview_is_placeable)
	
	while construction_line_previews.size() > num_buildings:
		var p = construction_line_previews.pop_back()
		if is_instance_valid(p): 
			building_manager.return_placement_preview_to_pool(p)

	var direction = (end_pos_pixels - start_pos_pixels).normalized()
	for i in range(num_buildings):
		var preview = construction_line_previews[i]
		var ideal_pos = start_pos_pixels + direction * optimal_dist_pixels * i
		var current_snapped_pos = building_manager.ground_layer.map_to_local(building_manager.ground_layer.local_to_map(ideal_pos))

		if not preview.is_ghost_preview_initialized():
			preview.initialize_ghost_preview(
				building_to_build_type, building_manager.grid_manager,
				GlobalData.get_ghost_texture(building_to_build_type),
				building_manager.ground_layer, building_manager.buildable_tile_id
			)
		preview.update_ghost_preview_position(current_snapped_pos)

	for line in relay_line_previews:
		building_manager.grid_manager.return_connection_line_to_pool(line)
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
				var line: ConnectionLine = building_manager.grid_manager.get_connection_line_from_pool()
				building_manager.add_child(line)
				var is_line_valid = construction_previews_validity.get(preview_a, false) and construction_previews_validity.get(preview_b, false)
				line.setup_preview_connections(from_pos, to_pos, is_line_valid)
				relay_line_previews.append(line)

# Clears and frees all previews used in line construction.
func _clear_construction_line_previews() -> void:
	for preview in construction_line_previews:
		building_manager.return_placement_preview_to_pool(preview)
	construction_line_previews.clear()
	construction_previews_validity.clear()

	for line in relay_line_previews:
		building_manager.grid_manager.return_connection_line_to_pool(line)
	relay_line_previews.clear()
