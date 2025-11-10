extends BuildingManagerState

# ---------------------------------------
# --- Multi Selection (Box) State -------
# ---------------------------------------
var is_box_selecting_state: bool = false
var selection_start_pos: Vector2 = Vector2.ZERO
var selection_end_pos: Vector2 = Vector2.ZERO


func _on_process(_delta: float) -> void:
	# If we are dragging a selection box, update its end position and request a redraw
	if is_box_selecting_state:
		selection_end_pos = building_manager.get_global_mouse_position()
		building_manager.queue_redraw()

func _on_physics_process(_delta : float) -> void:
	pass

func _on_next_transitions() -> void:
	pass

func _on_enter() -> void:
	super()
	is_box_selecting_state = false


func _on_exit() -> void:
	# Clean up the drawing if we exit the state while drawing a box
	if is_box_selecting_state:
		is_box_selecting_state = false
		building_manager.queue_redraw()
	
	# Stop any pending double-click action
	if not building_manager.double_click_timer.is_stopped():
		building_manager.double_click_timer.stop()
	building_manager.last_clicked_building = null


# This is a virtual Godot function that is called by the engine via the BuildingManager
func _draw() -> void:
	if is_box_selecting_state:
		var rect = Rect2(selection_start_pos, selection_end_pos - selection_start_pos)
		building_manager.draw_rect(rect, Color(0, 0.5, 1, 0.2))
		building_manager.draw_rect(rect, Color(0, 0.5, 1, 1), false, 1.0)


# -----------------------------------------
# --- InputManager Signal Handlers ------
# -----------------------------------------
func _on_InputManager_map_left_clicked(_click_position: Vector2i) -> void:
	is_box_selecting_state = true
	selection_start_pos = building_manager.get_global_mouse_position()
	selection_end_pos = selection_start_pos
	building_manager.clear_selection()

func _on_InputManager_map_left_released(_release_position: Vector2i) -> void:
	if is_box_selecting_state:
		is_box_selecting_state = false
		# Only perform selection if the box is a meaningful size
		if selection_start_pos.distance_to(selection_end_pos) > 5:
			_select_buildings_in_box()
		building_manager.queue_redraw()

func _on_InputManager_map_right_clicked(_click_position: Vector2i) -> void:
	building_manager.clear_selection()


# This function is called by the BuildingManager when a building's 'clicked' signal is emitted.
func _on_building_clicked(clicked_building: Building) -> void:
	# If the timer is running and the same building is clicked, it's a double-click.
	if not building_manager.double_click_timer.is_stopped() and clicked_building == building_manager.last_clicked_building:
		building_manager.double_click_timer.stop()
		building_manager.select_all_by_type(clicked_building.building_type)
		building_manager.last_clicked_building = null # Reset for the next click sequence.
	# Otherwise, it's the first click of a potential double-click.
	else:
		building_manager.double_click_timer.start(building_manager.double_click_window)
		building_manager.last_clicked_building = clicked_building


# This function is called by the BuildingManager when the double-click timer runs out.
func _on_double_click_timer_timeout() -> void:
	# Ensure the building is still valid before proceeding.
	if not is_instance_valid(building_manager.last_clicked_building):
		return

	# Standard single-click logic: deselect if already selected, otherwise select it.
	if building_manager.selected_buildings.size() == 1 and building_manager.selected_buildings[0] == building_manager.last_clicked_building:
		building_manager.clear_selection()
	else:
		building_manager.clear_selection()
		building_manager.selected_buildings.append(building_manager.last_clicked_building)
		building_manager.update_selection()

	# Reset for the next click sequence.
	building_manager.last_clicked_building = null


func _select_buildings_in_box() -> void:
	var selection_box = Rect2(selection_start_pos, selection_end_pos - selection_start_pos).abs()
	building_manager.clear_selection()

	# Use the manager's authoritative list of buildings for efficiency
	var buildings_in_scene = building_manager.buildings
	for building in buildings_in_scene:
		if selection_box.has_point(building.global_position):
			building_manager.selected_buildings.append(building)
	
	building_manager.update_selection()

# -----------------------------------------
# --- UserInterface Signal Handlers -------
# -----------------------------------------
func _on_ui_destroy_button_pressed() -> void:
	for building in building_manager.selected_buildings:
		if is_instance_valid(building):
			building.destroy()
	building_manager.clear_selection()

func _on_ui_deactivate_button_pressed() -> void:
	for building in building_manager.selected_buildings:
		if is_instance_valid(building):
			building.set_deactivated_state(not building.is_deactivated)
	building_manager.clear_selection()
