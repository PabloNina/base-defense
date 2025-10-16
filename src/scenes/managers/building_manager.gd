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

# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
@onready var building_ghost_preview: BuildingGhostPreview = $BuildingGhostPreview

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
# -----------------------------------------
# --- Construction State ----------------------
# -----------------------------------------
var is_construction_state: bool = false
var is_building_placeable: bool = true
var is_command_center: bool = false
var building_to_build_id: int = 0
var ghost_tile_position: Vector2i

# -----------------------------------------
# --- Select State ----------------------
# -----------------------------------------
var current_clicked_building: Building = null
var buildings: Array[Building] = []  # All active buildings

# ---------------------------------------
# --- Move State -----------------------
# ---------------------------------------
var building_to_move: MovableBuilding = null
var is_move_state: bool = false

# -----------------------------------------
# --- Signals -----------------------------
# -----------------------------------------
signal building_selected(building: Building)
signal building_deselected()

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	add_to_group("building_manager")
	# Subscribe to Ui signals
	user_interface.building_button_pressed.connect(on_ui_building_button_pressed)


func _process(_delta: float) -> void:
	# If building mode is active update building ghost position
	if is_construction_state == true:
		get_cell_under_mouse()
		update_ghost_tile_position(tile_position)

# -----------------------------------------
# --- Mouse Tile Tracking -----------------
# -----------------------------------------
func get_cell_under_mouse() -> void:
	mouse_position = ground_layer.get_local_mouse_position()
	tile_position = ground_layer.local_to_map(mouse_position)
	tile_source_id = ground_layer.get_cell_source_id(tile_position)
	local_tile_position = ground_layer.map_to_local(tile_position)
	# print("Mouse:", mouse_position, "Tile:", tile_position, "Source ID:", tile_source_id)

# -----------------------------------------
# --- Building Registration ---------------
# -----------------------------------------
func register_building(new_building: Building) -> void:
	if new_building not in buildings:
		buildings.append(new_building)
		new_building.clicked.connect(on_building_clicked)

func unregister_building(destroyed_building: Building) -> void:
	if destroyed_building not in buildings:
		return
	
	# Erase from buildings list
	buildings.erase(destroyed_building)
	# Remove tile from map so it can be used again
	var tile_coords = buildings_layer.local_to_map(destroyed_building.global_position)
	buildings_layer.erase_cell(tile_coords)


# -----------------------------------------
# --- Building Mode Placement ------------------
# -----------------------------------------
func place_building() -> void:
	# Only build on valid ground tiles
	if tile_source_id != 0:
		print("Invalid Placement")
		return

	# --- Command Center Logic ---
	if not is_command_center and building_to_build_id == command_center_id:
		is_command_center = true
		buildings_layer.set_cell(tile_position, 2, Vector2i.ZERO, building_to_build_id)
	elif not is_command_center and building_to_build_id != command_center_id:
		print("Build Command Center First!")
	elif is_command_center and building_to_build_id == command_center_id:
		print("You can only have 1 Command Center!")
	elif is_command_center and building_to_build_id != command_center_id:
		# Place regular building
		buildings_layer.set_cell(tile_position, 2, Vector2i.ZERO, building_to_build_id)
	else:
		print("Invalid Placement State")

# -----------------------------------------
# --- Building Mode Helpers ---------------
# -----------------------------------------

func _select_building_to_build(new_building: DataTypes.BUILDING_TYPE) -> void:
	is_construction_state = true
	building_ghost_preview.set_building_type(new_building)
	building_to_build_id = DataTypes.get_tilemap_id(new_building)

func _deselect_building_to_build() -> void:
	is_construction_state = false
	building_ghost_preview.clear_preview()
	building_to_build_id = 0

# -----------------------------------------
# ------ Building Mode Ghost Feedback -----
# -----------------------------------------
func update_ghost_tile_position(new_position: Vector2i) -> void:
	if ghost_tile_position == new_position:
		return
	ghost_tile_position = new_position
	building_ghost_preview.position = local_tile_position

func _on_building_ghost_preview_is_placeable(value: bool) -> void:
	is_building_placeable = value

# -----------------------------------------
# --- Building Clicked in GameWorld -------
# -----------------------------------------
# Called when a building is clicked in the game world 
# by connecting signal clicked on register_building
func on_building_clicked(clicked_building: Building) -> void:
	# if building_mode is on dont select buildings
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
	#print("Building selected")

func _deselect_clicked_building() -> void:
	building_deselected.emit()
	current_clicked_building = null
	#print("Building deselected")

# -----------------------------------------
# --- Mouse and Keyboard Input Handling ---
# -----------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# --- Placement ---
	if event.is_action_pressed("left_mouse") and is_construction_state and is_building_placeable:
		place_building()

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
			# if building_mode == false:
			_deselect_clicked_building()

# -----------------------------------------
# --- User Interface Input Handling ------
# -----------------------------------------
func on_ui_building_button_pressed(building: DataTypes.BUILDING_TYPE) -> void:
	_select_building_to_build(building)
