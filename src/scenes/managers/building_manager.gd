# =========================================
# BuildingManager.gd
# =========================================
# Handles Mouse tracking and Building placement/selection

class_name BuildingManager
extends Node

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
var energy_relay_id: int = 5
var energy_generator_id: int = 4
var command_center_id: int = 3
var gun_turret_id: int = 6

# -----------------------------------------
# --- Building State ----------------------
# -----------------------------------------
var building_mode: bool = false
var is_placeable: bool = true
var is_command_center: bool = false
var building_to_build_id: int = 0
var ghost_tile_position: Vector2i

# -----------------------------------------
# --- Select State ----------------------
# -----------------------------------------
var current_selected_building: Relay = null
var buildings: Array[Relay] = []  # All active buildings

# -----------------------------------------
# --- Signals -----------------------------
# -----------------------------------------
signal building_selected(building: Relay)
signal building_deselected()

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	add_to_group("building_manager")
	
	# Subscribe to Ui signals1
	user_interface.building_button_pressed.connect(on_ui_building_button_pressed)


func _process(_delta: float) -> void:
	# If building mode is active update building ghost position
	if building_mode == true:
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

func update_ghost_tile_position(new_position: Vector2i) -> void:
	if ghost_tile_position == new_position:
		return
	ghost_tile_position = new_position
	building_ghost_preview.position = local_tile_position


# -----------------------------------------
# --- Building Registration ---------------
# -----------------------------------------
func register_building(new_building: Relay) -> void:
	if new_building not in buildings:
		buildings.append(new_building)
		new_building.clicked.connect(on_building_clicked)

func unregister_building(destroyed_building: Relay) -> void:
	if destroyed_building not in buildings:
		return
	
	# Erase from buildings list
	buildings.erase(destroyed_building)
	# Remove tile from map so it can be used again
	var tile_coords = buildings_layer.local_to_map(destroyed_building.global_position)
	buildings_layer.erase_cell(tile_coords)


# -----------------------------------------
# --- Building Placement ------------------
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

func _select_building_to_build(building: DataTypes.BUILDING_TYPE) -> void:
	building_mode = true
	building_ghost_preview.set_building_type(building)
	building_to_build_id = DataTypes.get_tilemap_id(building)

func _deselect_building_to_build() -> void:
	building_mode = false
	building_ghost_preview.clear_preview()
	building_to_build_id = 0

# ---------------------------------------------------
# ------- BuildingGhost Collision Feedback ----------
# ---------------------------------------------------
func _on_building_ghost_preview_is_placeable(value: bool) -> void:
	is_placeable = value

# -----------------------------------------
# --- Building Clicked in GameWorld -------
# -----------------------------------------
# Called when a building is clicked in the game world 
# by connecting signal clicked on register_building
func on_building_clicked(clicked_building: Relay) -> void:
	# if building_mode is on dont select buildings
	if building_mode == true:
		return

	if current_selected_building == clicked_building:
		# Deselect if clicked again
		_deselect_clicked_building()
	else:
		# Select new building
		_select_clicked_building(clicked_building)

func _select_clicked_building(building: Relay) -> void:
	building_selected.emit(building)
	current_selected_building = building
	#print("Building selected")

func _deselect_clicked_building() -> void:
	building_deselected.emit()
	current_selected_building = null
	#print("Building deselected")

# -----------------------------------------
# --- Mouse and Keyboard Input Handling ---
# -----------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	# --- Placement ---
	if event.is_action_pressed("left_mouse") and building_mode and is_placeable:
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
		if building_mode == true:
			_deselect_building_to_build()

		else:
			# if building_mode == false:
			_deselect_clicked_building()

# -----------------------------------------
# --- User Interface Input Handling ------
# -----------------------------------------
func on_ui_building_button_pressed(building: DataTypes.BUILDING_TYPE) -> void:
	_select_building_to_build(building)
