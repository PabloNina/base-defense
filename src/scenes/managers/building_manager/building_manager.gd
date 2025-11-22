# =========================================
# buildings_manager.gd
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
@onready var state_machine: NodeStateMachine = $StateMachine
# -----------------------------------------
# --- Mouse Tracking ----------------------
# -----------------------------------------
var mouse_position: Vector2
var tile_position: Vector2i
var tile_source_id: int
var local_tile_position: Vector2
# -----------------------------------------
# --- Shared State ------------------------
# -----------------------------------------
# All available States
enum STATES {NULL, CONSTRUCTION, SELECTING, MOVING}
# Keeps track of current state
var current_state: STATES = STATES.NULL
# Flag to check is the base is placed
var is_command_center_placed: bool = false
# should go to globaldata?
var buildable_tile_id: int = -1 
# All registered buildings
var buildings: Array[Building] = []
# List if selected buildings
var selected_buildings: Array[Building] = []
# Dictionary of active landing markers for buildings currently moving.
var landing_markers: Dictionary = {} # Key: building instance, Value: marker instance
# -----------------------------------------
# --- Signals -----------------------------
# -----------------------------------------
# Emited when buildings are selected or deselected
# Connected to UserInterface
signal selection_changed(buildings: Array[Building])
signal building_deselected()
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Get buildable tile from global data
	buildable_tile_id = GlobalData.BUILDABLE_TILE_ID
	# Ensure BuildingManager processes even when game is paused 
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Group adding
	add_to_group("building_manager")
	# Connect timer signal for double click detection
	double_click_timer.timeout.connect(_on_double_click_timer_timeout)
	# Start the state machine when manager is ready.
	# IMPORTANT: The initial node_state should be SelectingState as it is the default state.
	state_machine.start()
	# Subscribe to Ui signals
	_connect_to_user_interface_signals()
	# Subscribe to InputManager signals
	_connect_to_input_manager_signals()
	# Immediately transition to building the Command Center at the start of the game.
	#_select_building_to_construct(GlobalData.BUILDING_TYPE.COMMAND_CENTER)

func _process(_delta: float) -> void:
	if current_state == STATES.CONSTRUCTION or STATES.MOVING:
		_get_cell_under_mouse()

func _draw() -> void:
	if current_state == STATES.SELECTING:
		var current_state_node = state_machine.current_node_state
		current_state_node._draw()

# --------------------------------------------------
# ---------------- Public Methods ------------------
# --------------------------------------------------

# -----------------------------------------
# --- Building Registration ---------------
# -----------------------------------------
# Called by every building class object on ready
# Adds building to registered buildings list and subscribe to signals
func register_building(new_building: Building) -> void:
	if new_building not in buildings:
		buildings.append(new_building)
		new_building.clicked.connect(_on_building_clicked)
		
		if new_building is MovableBuilding:
			new_building.move_started.connect(_on_building_move_started)
			new_building.move_completed.connect(_on_building_move_completed)

# Called by every building class object on destroy
func unregister_building(destroyed_building: Building) -> void:
	if destroyed_building not in buildings:
		return

	# If it is the CC reset the flag
	if destroyed_building is Command_Center:
		is_command_center_placed = false
		
	# Erase from buildings list
	buildings.erase(destroyed_building)

# -----------------------------------------
# --- Building Construction ---------------
# -----------------------------------------
# Called by ConstructionState
func construct_building(building_scene: PackedScene, building_position: Vector2) -> void:
	var new_building = building_scene.instantiate()
	new_building.global_position = building_position
	buildings_container.add_child(new_building)


# -----------------------------------------
# --- Building Selection ------------------
# -----------------------------------------
# Used by selecting state when double click on building is detected
func select_all_by_type(type: GlobalData.BUILDING_TYPE) -> void:
	clear_selection()
	# Filter all registered buildings to find ones that match the given type.
	var all_of_type = buildings.filter(func(building): return building.building_type == type)
	selected_buildings = all_of_type
	update_selection()

# Used by moving state selection state and self.select_all_by_type() method
func clear_selection() -> void:
	for building in selected_buildings:
		if is_instance_valid(building):
			building.hide_selection_sprite()
	selected_buildings.clear()
	update_selection()

# Used by selecting state and self.select_all_by_type and clear_selection methods
func update_selection() -> void:
	if selected_buildings.is_empty():
		building_deselected.emit()
	else:
		for building in selected_buildings:
			if is_instance_valid(building):
				building.show_selection_sprite()
		selection_changed.emit(selected_buildings)

# -----------------------------------------
# --- Building Destruction ----------------
# -----------------------------------------
## Destroys a list of buildings. This function is designed to be called by other systems
## (like the FlowManager) that need to request the destruction of multiple buildings at once.
func destroy_buildings(buildings_to_destroy: Array[Building]) -> void:
	# Iterate through the provided list and call the destroy method on each building.
	for building in buildings_to_destroy:
		if is_instance_valid(building):
			building.destroy()

# -----------------------------------------
# --- GhostPreview Pool Wrappers ----------
# -----------------------------------------
# Used by self construction and moving states
func get_placement_preview_from_pool() -> GhostPreview:
	return ghost_preview_pool.get_preview()

func return_placement_preview_to_pool(preview: GhostPreview) -> void:
	ghost_preview_pool.return_preview(preview)

# --------------------------------------------------
# ---------------- Private Methods -----------------
# --------------------------------------------------

# -----------------------------------------
# --- Mouse Tile Tracking -----------------
# -----------------------------------------
func _get_cell_under_mouse() -> void:
	mouse_position = ground_layer.get_local_mouse_position()
	tile_position = ground_layer.local_to_map(mouse_position)
	tile_source_id = ground_layer.get_cell_source_id(tile_position)
	local_tile_position = ground_layer.map_to_local(tile_position)

# -----------------------------------------
# --- Building Class Signal Handling ------
# -----------------------------------------
# Creates a static marker when a buildings move begins.
# Connected to move_started signal from MovableBuilding class object
func _on_building_move_started(building: MovableBuilding, landing_position: Vector2) -> void:
	if landing_markers.has(building):
		return_placement_preview_to_pool(landing_markers[building])

	var marker = get_placement_preview_from_pool()
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
# Connected to move_completed signal from MovableBuilding class object
func _on_building_move_completed(building: MovableBuilding) -> void:
	if landing_markers.has(building):
		return_placement_preview_to_pool(landing_markers[building])
		landing_markers.erase(building)

# Connected to clicked signal from Building class object
# Used to select and deselect buildings
func _on_building_clicked(clicked_building: Building) -> void:
	if current_state == STATES.SELECTING:
		var selecting_state = state_machine.current_node_state
		selecting_state.double_click_selection_check(clicked_building)

# -----------------------------------------
# --- Double Click Timer Signal Handling --
# -----------------------------------------
# Called when the double-click timer runs out indicating a single click.
func _on_double_click_timer_timeout() -> void:
	if current_state == STATES.SELECTING:
		var selecting_state = state_machine.current_node_state
		selecting_state.single_click_selection()

# --------------------------------------------------
# --- UserInterface&InputManager Signal Handling ---
# --------------------------------------------------
# Connected to ui and input manager signals
func _select_building_to_construct(new_building_type: GlobalData.BUILDING_TYPE) -> void:
	# Pass data to the state through the state machine or a shared context if needed
	var construction_state = state_machine.node_states["constructionstate"]
	if current_state == STATES.CONSTRUCTION:
		construction_state.building_to_build_type = new_building_type
		construction_state.update_ghost_preview()

	if current_state == STATES.SELECTING:
		construction_state.building_to_build_type = new_building_type
		current_state = STATES.CONSTRUCTION

# -----------------------------------------
# --- UserInterface Signal Subscribing ----
# -----------------------------------------
func _connect_to_user_interface_signals() -> void:
	user_interface.building_button_pressed.connect(_on_ui_building_button_pressed)
	user_interface.destroy_button_pressed.connect(_on_ui_destroy_button_pressed)
	user_interface.move_selection_pressed.connect(_on_ui_move_selection_pressed)
	user_interface.deactivate_button_pressed.connect(_on_ui_deactivate_button_pressed)

# -----------------------------------------
# --- UserInterface Signal Handling -------
# -----------------------------------------
# Signal from UI BuildingsPanel
func _on_ui_building_button_pressed(new_building_type: GlobalData.BUILDING_TYPE) -> void:
	_select_building_to_construct(new_building_type)

# Signals from UI BuildingActionPanel Buttons
func _on_ui_destroy_button_pressed() -> void:
	if current_state == STATES.SELECTING:
		var selecting_state = state_machine.current_node_state
		selecting_state.destroy_building()

func _on_ui_deactivate_button_pressed() -> void:
	if current_state == STATES.SELECTING:
		var selecting_state = state_machine.current_node_state
		selecting_state.deactivate_building()

func _on_ui_move_selection_pressed() -> void:
	if current_state == STATES.SELECTING:
		if selected_buildings.is_empty():
			return
		current_state = STATES.MOVING

# -----------------------------------------
# --- InputManager Signal Subscribing -----
# -----------------------------------------
func _connect_to_input_manager_signals() -> void:
	InputManager.map_left_clicked.connect(_on_InputManager_map_left_clicked)
	InputManager.map_left_released.connect(_on_InputManager_map_left_released)
	InputManager.map_right_clicked.connect(_on_InputManager_map_right_clicked)
	InputManager.build_relay_pressed.connect(func(): _select_building_to_construct(GlobalData.BUILDING_TYPE.RELAY))
	InputManager.build_gun_turret_pressed.connect(func(): _select_building_to_construct(GlobalData.BUILDING_TYPE.CANNON))
	InputManager.build_reactor_pressed.connect(func(): _select_building_to_construct(GlobalData.BUILDING_TYPE.REACTOR))
	InputManager.build_command_center_pressed.connect(func(): _select_building_to_construct(GlobalData.BUILDING_TYPE.COMMAND_CENTER))
	InputManager.formation_tighter_pressed.connect(_on_InputManager_formation_tighter_pressed)
	InputManager.formation_looser_pressed.connect(_on_InputManager_formation_looser_pressed)
	InputManager.formation_rotate_pressed.connect(_on_InputManager_formation_rotate_pressed)
	# Set ground_layer in InputManager
	InputManager.ground_layer = ground_layer

# -----------------------------------------
# --- InputManager Signal Handling --------
# -----------------------------------------
func _on_InputManager_map_left_clicked(click_position: Vector2i) -> void:
	var current_state_node = state_machine.current_node_state
	if current_state_node and current_state_node.has_method("_on_InputManager_map_left_clicked"):
		current_state_node._on_InputManager_map_left_clicked(click_position)

func _on_InputManager_map_left_released(release_position: Vector2i) -> void:
	var current_state_node = state_machine.current_node_state
	if current_state_node and current_state_node.has_method("_on_InputManager_map_left_released"):
		current_state_node._on_InputManager_map_left_released(release_position)

func _on_InputManager_map_right_clicked(click_position: Vector2i) -> void:
	var current_state_node = state_machine.current_node_state
	if current_state_node and current_state_node.has_method("_on_InputManager_map_right_clicked"):
		current_state_node._on_InputManager_map_right_clicked(click_position)

func _on_InputManager_formation_tighter_pressed() -> void:
	if current_state == STATES.MOVING:
		var moving_state = state_machine.current_node_state
		moving_state.move_formation_tighter()

func _on_InputManager_formation_looser_pressed() -> void:
	if current_state == STATES.MOVING:
		var moving_state = state_machine.current_node_state
		moving_state.move_formation_looser()

func _on_InputManager_formation_rotate_pressed() -> void:
	if current_state == STATES.MOVING:
		var moving_state = state_machine.current_node_state
		moving_state.move_formation_rotate()
