# -------------------------------
# --------- Building.gd ---------
# -------------------------------
# Base building class for all player structures, weapons and grid nodes.
# Other types (CommandCenter, relays, Generator, etc.) extend this.
@abstract
class_name Building extends Node2D
# -------------------------------
# --- Signals -------------------
# -------------------------------
## Emited when building is clicked
## Connected to BuildingManager
signal clicked(building: Building)
## Emited when building is built
## Connected to GridManager
signal finish_building()
## Emited when building is (de)activated.
signal deactivated(is_deactivated: bool)

# -------------------------------
# --- Editor Settings ----------- 
# -------------------------------
# packets needed to complete construction
var cost_to_build: int = 0
# tag to prevent connections between generators/weapons etc...
var is_relay: bool = false
# Amount of Packets this building consumes per tick
var upkeep_cost: float = 0.0
## Type of building that is using this class for Ui labeling
@export var building_type: GlobalData.BUILDING_TYPE = GlobalData.BUILDING_TYPE.NULL
# Max range for connection lines to be created
var connection_range: float = 0.0
# -------------------------------
# --- Child Node References -----
# -------------------------------
@onready var building_hurt_box: Area2D = $BuildingHurtBox
@onready var construction_progress_bar: ProgressBar = $ConstructionProgressBar
@onready var exclamation_mark_sprite: Sprite2D = $ExclamationMarkSprite
@onready var deactivated_sprite: Sprite2D = $DeactivatedSprite
# -------------------------------
# --- Runtime States ------------
# -------------------------------
var is_built: bool = false: set = set_built_state
var is_powered: bool = false: set = set_powered_state
var is_deactivated: bool = false: set = set_deactivated_state
var is_scheduled_to_build: bool = false
var is_selected: bool = false

var packets_in_flight: int = 0
var construction_progress: int = 0
var connected_buildings: Array[Building] = []
var grid_manager: GridManager
var building_manager: BuildingManager


# -------------------------------
# --- Engine Callbacks ----------
# -------------------------------
func _ready():
	# Config building with data from GlobalData
	connection_range = GlobalData.get_connection_range(building_type)
	cost_to_build = GlobalData.get_cost_to_build(building_type)
	is_relay = GlobalData.get_is_relay(building_type)
	upkeep_cost = GlobalData.get_upkeep_cost(building_type)

	# Setup Click Detection
	building_hurt_box.area_clicked.connect(on_hurtbox_clicked)
	# group adding
	add_to_group("buildings")
	
	# setup construction progress bar
	construction_progress_bar.max_value = cost_to_build
	construction_progress_bar.step = 1
	construction_progress_bar.value = 0
	# Starts hidden is activated after receiving the first building packet
	construction_progress_bar.visible = false
	# hide exclamation mark sprite
	#exclamation_mark_sprite.visible = false
	# hide deactivated sprite
	deactivated_sprite.visible = false
	
	# Register with Managers
	grid_manager = get_tree().get_first_node_in_group("grid_manager")
	if grid_manager:
		grid_manager.register_to_grid(self)

	building_manager = get_tree().get_first_node_in_group("building_manager")
	if building_manager:
		building_manager.register_building(self)

	_updates_visuals()

# -------------------------------
# --- Selected Box Drawing ------
# -------------------------------
func _draw() -> void:                                                                                                                                   
	if is_selected:                                                                                                                                     
		# Find the building texture to determine the size of the selection box
		var texture = GlobalData.get_ghost_texture(building_type)
		if texture:
			var rect: Rect2 
			rect.size = texture.get_size()
			rect.position = -rect.size / 2
			# Grow the rectangle by 4 pixels on each side to create a margin
			draw_rect(rect.grow(4), Color.GREEN, false, 2.0)
			
# -------------------------------
# --- Selection Box Updating ----
# -------------------------------
func select() -> void:
	is_selected = true
	queue_redraw()


func deselect() -> void:
	is_selected = false
	queue_redraw()
	
# -------------------------------
# --- Input / Click Handling ----
# -------------------------------
func on_hurtbox_clicked() -> void:
	clicked.emit(self)

# -------------------------------
# --- grid Linking -----------
# -------------------------------
func connect_to(other_building: Building):
	if not connected_buildings.has(other_building):
		connected_buildings.append(other_building)

func disconnect_from(other_building: Building):
	connected_buildings.erase(other_building)

# ----------------------
# --- States Setters ---
# ----------------------
func set_powered_state(new_state: bool) -> void:
	if is_powered == new_state:
		return
	is_powered = new_state
	#_updates_visuals()
	if is_powered:
		exclamation_mark_sprite.visible = false
	else:
		exclamation_mark_sprite.visible = true

func set_built_state(new_state: bool) -> void:
	if is_built == new_state:
		return
	is_built = new_state
	finish_building.emit()
	_updates_visuals()

# Sets the deactivated state of the building.
func set_deactivated_state(deactivate: bool) -> void:
	is_deactivated = deactivate
	deactivated.emit(is_deactivated)
	if is_deactivated:
		deactivated_sprite.visible = true
	else:
		deactivated_sprite.visible = false
	#_updates_visuals()
	
# -------------------------------
# --- Packet In Flight ----------
# -------------------------------
func increment_packets_in_flight() -> void:
	packets_in_flight += 1
	if not is_built and packets_in_flight + construction_progress >= cost_to_build:
		is_scheduled_to_build = true

func decrement_packets_in_flight() -> void:
	packets_in_flight = max(0, packets_in_flight - 1)
	if not is_built and packets_in_flight + construction_progress < cost_to_build:
		is_scheduled_to_build = false

func reset_packets_in_flight() -> void:
	packets_in_flight = 0
	if not is_built:
		is_scheduled_to_build = false
# -------------------------------
# --- Packet Reception ----------
# -------------------------------
func received_packet(packet_type: GlobalData.PACKETS):
	match packet_type:
		GlobalData.PACKETS.BUILDING:
			_handle_received_building_packet()
		_:
			push_warning("Unknown packet type received: %s" % str(packet_type))

# -------------------------------
# --- Packet Processing ----------
# -------------------------------
func _handle_received_building_packet() -> void:
	if is_built:
		return
	construction_progress += 1
	_update_construction_progress_bar(construction_progress)

	if construction_progress >= cost_to_build:
		is_built = true

# -------------------------------
# --- Packet Demand Query -------
# -------------------------------
func needs_packet(packet_type: GlobalData.PACKETS) -> bool:
	match packet_type:
		GlobalData.PACKETS.BUILDING:
			# Needs building packets if not yet built and not fully scheduled to build
			return not is_built and not is_scheduled_to_build

		#GlobalData.PACKETS.AMMO:
			## Needs ammo if built, powered, and not fully stocked
			#return false

		_:
			return false

# -------------------------------
# --- Destroy and Clean ---------
# -------------------------------
func destroy():
	# Unregister from managers
	if grid_manager:
		grid_manager.unregister_to_grid(self)
	if building_manager:
		building_manager.unregister_building(self)

	# Disconnect from others to avoid dangling references
	for other in connected_buildings:
		if is_instance_valid(other):
			other.connected_buildings.erase(self)
	connected_buildings.clear()

	queue_free()

# -----------------------------------------
# ------ Building Energy Consumption ------
# -----------------------------------------
# Called by command center on tick
func get_upkeep_cost() -> float:
	if not is_built or not is_powered or is_deactivated:
		return 0.0
	return upkeep_cost
# -----------------------------------------
# ------ Building Actions -----------------
# -----------------------------------------
func get_available_actions() -> Array[GlobalData.BUILDING_ACTIONS]:
	# By default every building can be destroyed 
	var actions: Array[GlobalData.BUILDING_ACTIONS] = [GlobalData.BUILDING_ACTIONS.DESTROY]
	# Only relays and CC cant be deactivated every other building can
	if not is_relay:
		actions.append(GlobalData.BUILDING_ACTIONS.DEACTIVATE)
	return actions

# -------------------------------
# --- Visuals Updating ----------
# -------------------------------
# Make it abstract
func _updates_visuals() -> void:
# Implemented by child classes (e.g., change color or glow)
	pass

# Update ammo bar
func _update_construction_progress_bar(new_value: float) -> void:
	construction_progress_bar.value = new_value
	# Only show bar if not full
	if construction_progress_bar.value < cost_to_build:
		construction_progress_bar.visible = true
	else:
		construction_progress_bar.visible = false
