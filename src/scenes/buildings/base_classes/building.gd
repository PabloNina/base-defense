# -------------------------------
# --------- Building.gd ---------
# -------------------------------
# Base building class for all player structures, weapons and network nodes.
# Other types (CommandCenter, relays, Generator, etc.) extend this.
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
## Distance this building can connect to others
@export var connection_range: float = 0.0
## packets needed to complete construction
@export var cost_to_build: int = 0
## packets needed to maintain supply
@export var cost_to_supply: int = 0
## tag to prevent connections between generators/weapons etc...
@export var is_relay: bool = false
## Amount of Packets this building consumes per tick
@export var per_tick_packet_consumption: float = 0.0
## Type of building that is using this class for Ui labeling
@export var building_type: DataTypes.BUILDING_TYPE = DataTypes.BUILDING_TYPE.NULL
# -------------------------------
# --- Node References -----------
# -------------------------------
@onready var building_hurt_box: Area2D = $BuildingHurtBox
# -------------------------------
# --- Runtime State -------------
# -------------------------------
var is_built: bool = false: set = set_built_state
var is_powered: bool = false: set = set_powered_state
var is_scheduled_to_build: bool = false
var is_supplied: bool = false

var packets_in_flight: int = 0
var construction_progress: int = 0
var supply_level: int = 0
var connected_buildings: Array[Building] = []
var network_manager: NetworkManager
var building_manager: BuildingManager

# -------------------------------
# --- Engine Callbacks ----------
# -------------------------------
func _ready():
	# Setup Click Detection
	building_hurt_box.area_clicked.connect(on_hurtbox_clicked)
	# group adding
	add_to_group("relays")

	# Register with Managers
	network_manager = get_tree().get_first_node_in_group("network_manager")
	if network_manager:
		network_manager.register_relay(self)

	building_manager = get_tree().get_first_node_in_group("building_manager")
	if building_manager:
		building_manager.register_building(self)

	_updates_visuals()

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
	_updates_visuals()


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
		DataTypes.PACKETS.ENERGY:
			_handle_received_energy_packet()
		_:
			push_warning("Unknown packet type received: %s" % str(packet_type))

# -------------------------------
# --- Packet Processing ----------
# -------------------------------
func _handle_received_building_packet() -> void:
	if is_built:
		return
	construction_progress += 1

	if construction_progress >= cost_to_build:
		is_built = true

func _handle_received_energy_packet() -> void:
	if not is_built:
		return
	supply_level += 1
	if supply_level >= cost_to_supply:
		is_supplied = true
	else:
		is_supplied = false


# -------------------------------
# --- Packet Demand Query -------
# -------------------------------
func needs_packet(packet_type: DataTypes.PACKETS) -> bool:
	match packet_type:
		DataTypes.PACKETS.BUILDING:
			# Needs building packets if not yet built and not fully scheduled to build
			return not is_built and not is_scheduled_to_build

		DataTypes.PACKETS.ENERGY:
			# Needs energy if built, powered, and not fully supplied
			return false#is_built and is_powered and (supply_level < cost_to_supply)

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
# Called by networkmanager on tick
func consume_packets() -> float:
	if not is_built or not is_powered:
		return 0.0
	return per_tick_packet_consumption

# -------------------------------
# --- Visuals Updating ----------
# -------------------------------
func _updates_visuals():
	# Implemented by child classes (e.g., change color or glow)
	pass
