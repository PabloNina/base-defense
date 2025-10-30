# -------------------------------
# --------- Building.gd ---------
# -------------------------------
# Base building class for all player structures, weapons and network nodes.
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
## Connected to NetWorkManager
signal finish_building()

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
@export var building_type: DataTypes.BUILDING_TYPE = DataTypes.BUILDING_TYPE.NULL
# Max range for connection lines to be created
var connection_range: float = 0.0
# -------------------------------
# --- Child Node References -----
# -------------------------------
@onready var building_hurt_box: Area2D = $BuildingHurtBox
@onready var construction_progress_bar: ProgressBar = $ConstructionProgressBar
@onready var exclamation_mark_sprite: Sprite2D = $ExclamationMarkSprite
# -------------------------------
# --- Runtime State -------------
# -------------------------------
var is_built: bool = false: set = set_built_state
var is_powered: bool = false: set = set_powered_state
var is_scheduled_to_build: bool = false
var is_selected: bool = false

var packets_in_flight: int = 0
var construction_progress: int = 0
var connected_buildings: Array[Building] = []
var network_manager: NetworkManager
var building_manager: BuildingManager


# -------------------------------
# --- Engine Callbacks ----------
# -------------------------------
func _ready():
	# Config building with data from DataTypes
	connection_range = DataTypes.get_connection_range(building_type)
	cost_to_build = DataTypes.get_cost_to_build(building_type)
	is_relay = DataTypes.get_is_relay(building_type)
	upkeep_cost = DataTypes.get_upkeep_cost(building_type)

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
	
	# Register with Managers
	network_manager = get_tree().get_first_node_in_group("network_manager")
	if network_manager:
		network_manager.register_relay(self)

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
		var texture = DataTypes.get_ghost_texture(building_type)
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
# --- Network Linking -----------
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
func received_packet(packet_type: DataTypes.PACKETS):
	match packet_type:
		DataTypes.PACKETS.BUILDING:
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
func needs_packet(packet_type: DataTypes.PACKETS) -> bool:
	match packet_type:
		DataTypes.PACKETS.BUILDING:
			# Needs building packets if not yet built and not fully scheduled to build
			return not is_built and not is_scheduled_to_build

		#DataTypes.PACKETS.AMMO:
			## Needs ammo if built, powered, and not fully stocked
			#return false

		_:
			return false

# -------------------------------
# --- Destroy and Clean ---------
# -------------------------------
func destroy():
	# Unregister from managers
	if network_manager:
		network_manager.unregister_relay(self)
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
	if not is_built or not is_powered:
		return 0.0
	return upkeep_cost
# -----------------------------------------
# ------ Building Actions -----------------
# -----------------------------------------
func get_available_actions() -> Array[DataTypes.BUILDING_ACTIONS]:
# By default, every building can be destroyed.
	return [DataTypes.BUILDING_ACTIONS.DESTROY]

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
