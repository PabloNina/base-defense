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
enum STATES {NULL, CONSTRUCTION, SELECTING, MOVING}
var current_state: STATES = STATES.NULL: set = _set_state
func _set_state(new_state: STATES):
	current_state = new_state
	print(new_state, state_machine.current_node_state_name)

var is_command_center_placed: bool = false
var buildable_tile_id: int = 0 # should go to globaldata?
# All registered buildings
var buildings: Array[Building] = []
# List if selected buildings
var selected_buildings: Array[Building] = []
# Dictionary of active landing markers for buildings currently moving.
var landing_markers = {} # Key: building instance, Value: marker instance
# Double Click Selection
var last_clicked_building: Building = null
# Window in seconds for double-click detection
var double_click_window: float = 0.2 
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
	# Ensure BuildingManager processes even when game is paused 
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Group adding
	add_to_group("building_manager")
	# Connect timer signal for double click detection
	double_click_timer.timeout.connect(_on_double_click_timer_timeout)
	# Start the state machine now that the manager is ready.
	# IMPORTANT: The initial state in the scene should be 'SelectingState'.
	state_machine.start()
	# Subscribe to Ui signals
	_connect_to_ui_signals()
	# Subscribe to InputManager signals
	_connect_to_InputManager_signals()
	# Immediately transition to building the Command Center at the start of the game.
	_enter_construction_state(GlobalData.BUILDING_TYPE.COMMAND_CENTER)

func _process(_delta: float) -> void:
	if current_state == STATES.CONSTRUCTION or STATES.MOVING:
		_get_cell_under_mouse()

func _draw() -> void:
	# Delegate drawing to the current state, if it has a _draw method.
	var current_state_node = state_machine.current_node_state
	if current_state_node and current_state_node.has_method("_draw"):
		current_state_node._draw()

# --------------------------------------------------
# ---------------- Public Methods ------------------
# --------------------------------------------------

# -----------------------------------------
# --- Building Registration ---------------
# -----------------------------------------
# Called by every building class object on ready
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
# --- GhostPreview Pool Wrappers ----------
# -----------------------------------------
# Used by self, construction and moving states
func get_placement_preview_from_pool() -> GhostPreview:
	return ghost_preview_pool.get_preview()

func return_placement_preview_to_pool(preview: GhostPreview) -> void:
	ghost_preview_pool.return_preview(preview)

# -----------------------------------------
# --- State Transitions -------------------
# -----------------------------------------
func _enter_construction_state(new_building_type: GlobalData.BUILDING_TYPE) -> void:
	# Pass data to the state through the state machine or a shared context if needed
	var construction_state = state_machine.node_states["constructionstate"]
	construction_state.building_to_build_type = new_building_type
	state_machine.transition_to("ConstructionState")

func _enter_move_state() -> void:
	if selected_buildings.is_empty():
		return
	state_machine.transition_to("MovingState")

# -----------------------------------------
# --- Mouse Tile Tracking -----------------
# -----------------------------------------
func _get_cell_under_mouse() -> void:
	mouse_position = ground_layer.get_local_mouse_position()
	tile_position = ground_layer.local_to_map(mouse_position)
	tile_source_id = ground_layer.get_cell_source_id(tile_position)
	local_tile_position = ground_layer.map_to_local(tile_position)

# -----------------------------------------
# --- Landing Markers ---------------------
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

# -----------------------------------------
# --- Selection Logic ---------------------
# -----------------------------------------
# Connected to clicked signal from Building class object
func _on_building_clicked(clicked_building: Building) -> void:
	#if current_state == STATES.SELECTING:
		#var current_state_node = state_machine.current_node_state
		#current_state_node._on_building_clicked(clicked_building)
	# Delegate click handling to the current state
	var current_state_node = state_machine.current_node_state
	if current_state_node.has_method("_on_building_clicked"):
		current_state_node._on_building_clicked(clicked_building)

# Called when the double-click timer runs out indicating a single click.
func _on_double_click_timer_timeout() -> void:
	# Delegate timeout handling to the current state
	var current_state_node = state_machine.current_node_state
	if current_state_node.has_method("_on_double_click_timer_timeout"):
		current_state_node._on_double_click_timer_timeout()

# Called by selecting state when double click on building is detected
func select_all_by_type(type: GlobalData.BUILDING_TYPE) -> void:
	clear_selection()
	# Filter all registered buildings to find ones that match the given type.
	var all_of_type = buildings.filter(func(b): return b.building_type == type)
	selected_buildings = all_of_type
	update_selection()

# Called by moving state and self select_all_by_type() method
func clear_selection() -> void:
	for building in selected_buildings:
		if is_instance_valid(building):
			building.hide_selection_sprite()
	selected_buildings.clear()
	update_selection()

# Called by selecting state and self select_all_by_type and clear_selection methods
func update_selection() -> void:
	if selected_buildings.is_empty():
		building_deselected.emit()
	else:
		for building in selected_buildings:
			if is_instance_valid(building):
				building.show_selection_sprite()
		selection_changed.emit(selected_buildings)

# -----------------------------------------
# --- UserInterface Signal Subscribing ----
# -----------------------------------------
func _connect_to_ui_signals() -> void:
	user_interface.building_button_pressed.connect(_on_ui_building_button_pressed)
	user_interface.destroy_button_pressed.connect(_on_ui_destroy_button_pressed)
	user_interface.move_selection_pressed.connect(_on_ui_move_selection_pressed)
	user_interface.deactivate_button_pressed.connect(_on_ui_deactivate_button_pressed)

# -----------------------------------------
# --- UserInterface Signal Handling -------
# -----------------------------------------
# Signal from UI BuildingsPanel
func _on_ui_building_button_pressed(building: GlobalData.BUILDING_TYPE) -> void:
	_enter_construction_state(building)

# Signals from UI BuildingActionPanel Buttons
func _on_ui_destroy_button_pressed() -> void:
	var current_state_node = state_machine.current_node_state
	if current_state_node and current_state_node.has_method("_on_ui_destroy_button_pressed"):
		current_state_node._on_ui_destroy_button_pressed()

func _on_ui_deactivate_button_pressed() -> void:
	var current_state_node = state_machine.current_node_state
	if current_state_node and current_state_node.has_method("_on_ui_deactivate_button_pressed"):
		current_state_node._on_ui_deactivate_button_pressed()
	
func _on_ui_move_selection_pressed() -> void:
	_enter_move_state()

# -----------------------------------------
# --- InputManager Signal Subscribing -----
# -----------------------------------------
func _connect_to_InputManager_signals() -> void:
	InputManager.map_left_clicked.connect(_on_InputManager_map_left_clicked)
	InputManager.map_left_released.connect(_on_InputManager_map_left_released)
	InputManager.map_right_clicked.connect(_on_InputManager_map_right_clicked)
	InputManager.build_relay_pressed.connect(func(): _enter_construction_state(GlobalData.BUILDING_TYPE.RELAY))
	InputManager.build_gun_turret_pressed.connect(func(): _enter_construction_state(GlobalData.BUILDING_TYPE.CANNON))
	InputManager.build_reactor_pressed.connect(func(): _enter_construction_state(GlobalData.BUILDING_TYPE.REACTOR))
	InputManager.build_command_center_pressed.connect(func(): _enter_construction_state(GlobalData.BUILDING_TYPE.COMMAND_CENTER))
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
	var current_state_node = state_machine.current_node_state
	if current_state_node and current_state_node.has_method("_on_InputManager_formation_tighter_pressed"):
		current_state_node._on_InputManager_formation_tighter_pressed()

func _on_InputManager_formation_looser_pressed() -> void:
	var current_state_node = state_machine.current_node_state
	if current_state_node and current_state_node.has_method("_on_InputManager_formation_looser_pressed"):
		current_state_node._on_InputManager_formation_looser_pressed()

func _on_InputManager_formation_rotate_pressed() -> void:
	var current_state_node = state_machine.current_node_state
	if current_state_node and current_state_node.has_method("_on_InputManager_formation_rotate_pressed"):
		current_state_node._on_InputManager_formation_rotate_pressed()
