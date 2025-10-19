# =========================================
# BuildingManager.gd
# =========================================
# Handles Mouse tracking and Building placement/selection/movement
class_name BuildingManager extends Node
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
# --- Construction State ----------------------
# -----------------------------------------
var is_construction_state: bool = false
var is_building_placeable: bool = true
var building_to_build_id: int = 0
var ghost_tile_position: Vector2i
var buildable_tile_id: int = 0
# -----------------------------------------
# --- Select State ----------------------
# -----------------------------------------
var current_clicked_building: Building = null
var buildings: Array[Building] = []  # All active buildings
# ---------------------------------------
# --- Move State -----------------------
# ---------------------------------------
var current_building_to_move: MovableBuilding = null
var is_move_state: bool = false
var position_to_move: Vector2 = Vector2.ZERO
# -----------------------------------------
# --- Signals -----------------------------
# -----------------------------------------
# Emited when building is clicked and selected
# Connected to UserInterface
signal building_selected(building: Building)
signal building_deselected()
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	add_to_group("building_manager")
	# Dependency injection
	ghost_building._network_manager = network_manager
	#ghost_building._building_manager = self
	# Subscribe to Ui signals
	user_interface.building_button_pressed.connect(_on_ui_building_button_pressed)
	user_interface.destroy_button_pressed.connect(_on_ui_destroy_button_pressed)
	user_interface.move_button_pressed.connect(_on_ui_move_button_pressed)
	
	is_construction_state = true
	building_to_build_id = command_center_id

func _process(_delta: float) -> void:
	# If construction or move state are active update building ghost position and track mouse
	if is_construction_state == true or is_move_state == true:
		_get_cell_under_mouse()
		_update_ghost_tile_position(tile_position)

# ----------------------------------------------
# --- Building Registration / Public Methods ---
# ----------------------------------------------
func register_building(new_building: Building) -> void:
	if new_building not in buildings:
		buildings.append(new_building)
		new_building.clicked.connect(_on_building_clicked)

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
# --- Construction State Placement --------
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
	elif not is_command_center_placed and building_to_build_id != command_center_id:
		print("Build Command Center First!")
	elif is_command_center_placed and building_to_build_id == command_center_id:
		print("You can only have 1 Command Center!")
	elif is_command_center_placed and building_to_build_id != command_center_id:
		# Place regular building
		buildings_layer.set_cell(tile_position, 2, Vector2i.ZERO, building_to_build_id)
	else:
		print("Invalid Placement State")

# -----------------------------------------
# --- Construction State Helpers ---------------
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
# ------ Construction State Ghost Feedback -----
# ----------------------------------------------
func _update_ghost_tile_position(new_position: Vector2i) -> void:
	if ghost_tile_position == new_position:
		return
	ghost_tile_position = new_position
	ghost_building.position = local_tile_position

# Used in Keyboard Input Handling to check if a building can be built or moved
# Called by the signal is_placeable emited everytime a building enters/exits BuildingGhost area2d
func _on_building_ghost_preview_is_placeable(value: bool) -> void:
	is_building_placeable = value

# -----------------------------------------
# --- Building Clicked in GameWorld -------
# -----------------------------------------
# Called when a building is clicked in the game world
# by connecting signal clicked on register_building
func _on_building_clicked(clicked_building: Building) -> void:
	# if construction state is on dont select buildings
	if is_construction_state == true:
		return

	if current_clicked_building == clicked_building:
		# Deselect if clicked again
		_deselect_clicked_building()
	else:
		# Select new building
		_select_clicked_building(clicked_building)

func _select_clicked_building(building: Building) -> void:
	building_selected.emit(building)
	current_clicked_building = building

func _deselect_clicked_building() -> void:
	building_deselected.emit()
	current_clicked_building = null

# -----------------------------------------
# --- Moving State Placement ------------
# -----------------------------------------
func _move_building(building_to_move: MovableBuilding) -> void:
	building_to_move.start_move(local_tile_position)
	is_move_state = false
	current_building_to_move = null
	ghost_building.clear_preview()
	_deselect_clicked_building()

# -----------------------------------------
# --- Mouse and Keyboard Input Handling ---
# -----------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# --- Placement ---
	if event.is_action_pressed("left_mouse") and is_construction_state and is_building_placeable:
		_place_building()
	elif event.is_action_pressed("left_mouse") and is_move_state and is_building_placeable:
		_move_building(current_building_to_move)

	# --- Selection: Building Hotkeys ---
	if event.is_action_pressed("key_1"):
		_select_building_to_build(DataTypes.BUILDING_TYPE.RELAY)
	elif event.is_action_pressed("key_2"):
		_select_building_to_build(DataTypes.BUILDING_TYPE.GUN_TURRET)
	elif event.is_action_pressed("key_3"):
		_select_building_to_build(DataTypes.BUILDING_TYPE.GENERATOR)
	elif event.is_action_pressed("key_4"):
		_select_building_to_build(DataTypes.BUILDING_TYPE.COMMAND_CENTER)

	# --- Cancel Building Mode or Building selection---
	elif event.is_action_pressed("right_mouse"):
		if is_construction_state == true:
			_deselect_building_to_build()

		else:
			# if is_construction_state == false:
			_deselect_clicked_building()
			# deselect moving state
			current_building_to_move = null
			is_move_state = false

# -----------------------------------------
# --- User Interface Input Handling ------
# -----------------------------------------
func _on_ui_building_button_pressed(building: DataTypes.BUILDING_TYPE) -> void:
	_select_building_to_build(building)
	
func _on_ui_destroy_button_pressed(building_to_destroy: Building) -> void:
	building_to_destroy.destroy()

func _on_ui_move_button_pressed(building_to_move: MovableBuilding) -> void:
	is_move_state = true
	current_building_to_move = building_to_move
	ghost_building.set_building_type(current_building_to_move.building_type)
