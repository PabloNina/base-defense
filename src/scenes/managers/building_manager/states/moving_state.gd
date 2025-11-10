extends BuildingManagerState

# ---------------------------------------
# --- Move State -----------------------
# ---------------------------------------
var buildings_to_move_group: Array[Building] = []
var formation_offsets: Array[Vector2] = []
var is_building_placeable: bool = true

# Formation Scaling
# Adjusts the tightness of the group formation.
var formation_scale: float = 1.0
var formation_angle: float = 0.0
const MIN_FORMATION_SCALE: float = 1.0
const MAX_FORMATION_SCALE: float = 2.0
const FORMATION_SCALE_STEP: float = 0.5

# Array of active previews for group moves.
var move_previews: Array[GhostPreview] = []
# Tracks the validity of each preview in a group move.
var move_previews_validity: Dictionary = {}



func _on_process(_delta: float) -> void:
	_update_move_previews()

func _on_physics_process(_delta : float) -> void:
	pass

func _on_next_transitions() -> void:
	pass

func _on_enter() -> void:
	super()
	
	# Duplicate the selection to create our move group
	buildings_to_move_group = building_manager.selected_buildings.duplicate()
	building_manager.clear_selection()
	
	formation_offsets.clear()
	
	# Calculate offsets from the centroid for formation
	if buildings_to_move_group.size() == 1:
		formation_offsets.append(Vector2.ZERO)
	else:
		var num_buildings = buildings_to_move_group.size()
		var tile_size = building_manager.ground_layer.tile_set.tile_size
		
		for i in range(num_buildings):
			# Calculate position in a horizontal line formation. The offsets are centered around (0,0).
			var offset_x = (i - (num_buildings - 1) / 2.0) * tile_size.x
			var offset_y = 0
			formation_offsets.append(Vector2(offset_x, offset_y))
			
	_create_move_previews()


func _on_exit() -> void:
	# Clear all move-related data
	buildings_to_move_group.clear()
	formation_offsets.clear()
	formation_scale = 1.0
	formation_angle = 0.0
	_clear_move_previews()


# -----------------------------------------
# --- InputManager Signal Handlers ------
# -----------------------------------------
func _on_InputManager_map_left_clicked(_click_position: Vector2i) -> void:
	if is_building_placeable:
		_move_building_selection()
		building_manager.state_machine.transition_to("SelectingState") # Return to selection after move

func _on_InputManager_map_right_clicked(_click_position: Vector2i) -> void:
	# Cancel move and return to selection state
	building_manager.state_machine.transition_to("SelectingState")

func _on_InputManager_formation_tighter_pressed() -> void:
	formation_scale = clamp(formation_scale - FORMATION_SCALE_STEP, MIN_FORMATION_SCALE, MAX_FORMATION_SCALE)
	_update_move_previews()

func _on_InputManager_formation_looser_pressed() -> void:
	formation_scale = clamp(formation_scale + FORMATION_SCALE_STEP, MIN_FORMATION_SCALE, MAX_FORMATION_SCALE)
	_update_move_previews()

func _on_InputManager_formation_rotate_pressed() -> void:
	formation_angle = fmod(formation_angle + 90.0, 360.0)
	_update_move_previews()


# -----------------------------------------
# --- Moving State Placement / Signals ----
# -----------------------------------------
func _move_building_selection() -> void:
	var new_centroid = building_manager.local_tile_position
	
	for i in range(buildings_to_move_group.size()):
		var building = buildings_to_move_group[i]
		# Apply the current formation scale to the offset.
		var offset = formation_offsets[i] * formation_scale
		# Rotate the offset based on the current formation angle.
		offset = offset.rotated(deg_to_rad(formation_angle))
		var target_pos = new_centroid + offset
		
		# Snap to the grid
		var target_tile = building_manager.ground_layer.local_to_map(target_pos)
		var snapped_pos = building_manager.ground_layer.map_to_local(target_tile)
		
		if building is MovableBuilding:
			building.start_move(snapped_pos)


# ----------------------------------------------
# ------ Preview Feedback ----------------------
# ----------------------------------------------
# Called when a preview's placement validity changes.
func _on_ghost_preview_is_placeable(is_valid: bool, preview: GhostPreview) -> void:
	if move_previews.has(preview):
		move_previews_validity[preview] = is_valid

	var all_valid = true
	for valid in move_previews_validity.values():
		if not valid:
			all_valid = false
			break
	is_building_placeable = all_valid


# Creates and configures the placement previews for a group move.
func _create_move_previews() -> void:
	move_previews_validity.clear()
	for building in buildings_to_move_group:
		if building is MovableBuilding:
			var preview = building_manager.get_placement_preview_from_pool()
			building_manager.add_child(preview)
			preview.initialize_ghost_preview(
				building.building_type,
				building_manager.grid_manager,
				GlobalData.get_landing_marker_texture(building.building_type),
				building_manager.ground_layer,
				building_manager.buildable_tile_id
			)
			move_previews.append(preview)
			move_previews_validity[preview] = true # Assume valid at start

			if not preview.is_placeable.is_connected(_on_ghost_preview_is_placeable):
				preview.is_placeable.connect(_on_ghost_preview_is_placeable)


# Updates the positions of all previews in a group move.
func _update_move_previews() -> void:
	var new_centroid = building_manager.local_tile_position
	for i in range(move_previews.size()):
		var preview = move_previews[i]
		var offset = formation_offsets[i] * formation_scale
		offset = offset.rotated(deg_to_rad(formation_angle))
		var target_pos = new_centroid + offset
		
		var target_tile = building_manager.ground_layer.local_to_map(target_pos)
		var snapped_pos = building_manager.ground_layer.map_to_local(target_tile)
		preview.update_ghost_preview_position(snapped_pos)


# Clears and frees all previews used in a group move.
func _clear_move_previews() -> void:
	for preview in move_previews:
		building_manager.return_placement_preview_to_pool(preview)
	move_previews.clear()
	move_previews_validity.clear()
