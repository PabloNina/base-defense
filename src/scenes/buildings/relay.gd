# -------------------------------
# --------- Relay.gd ------------
# -------------------------------
# Base relay class for all buildings and network nodes.
# Other types (CommandCenter, Turret, Generator, etc.) extend this.

class_name Relay
extends Node2D

# -------------------------------
# --- Signals -------------------
# -------------------------------
signal clicked(relay: Relay)

# -------------------------------
# --- Editor Settings ----------- 
# -------------------------------
@export var connection_range: float = 200.0
@export var cost_to_build: int = 1   # packets needed to complete construction
@export var cost_to_supply: int = 0  # packets needed to maintain supply
@export var consumer_only: bool = false # consumer-only tag to prevent connections between generators/weapons
@export var energy_consumption_rate: float = 0.0  # Energy consumed per tick
# -------------------------------
# --- Node References -----------
# -------------------------------
@onready var building_hurt_box: Area2D = $BuildingHurtBox

# -------------------------------
# --- Runtime State -------------
# -------------------------------
var is_built: bool = false
var is_powered: bool = false
var is_scheduled_to_build: bool = false
var is_supplied: bool = false
var packets_received: int = 0
var packets_on_the_way: int = 0
var build_progress: int = 0
var supply_level: int = 0
var connected_relays: Array[Relay] = []
var network_manager: NetworkManager
var building_manager: BuildingManager


# -------------------------------
# --- Engine Lifecycle ----------
# -------------------------------
func _ready():
	# --- Setup Click Detection ---
	building_hurt_box.area_clicked.connect(on_hurtbox_clicked)
	add_to_group("relays")

	# --- Register with Managers ---
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
func connect_to(other_relay: Relay):
	if not connected_relays.has(other_relay):
		connected_relays.append(other_relay)

func disconnect_from(other_relay: Relay):
	connected_relays.erase(other_relay)

# -------------------------------
# --- Power Management ----------
# -------------------------------
func set_powered(state: bool):
	if is_powered == state:
		return

	is_powered = state
	_updates_visuals()

func _updates_visuals():
	# Implemented by child classes (e.g., change color or glow)
	pass

# -------------------------------
# --- Packet Reception ----------
# -------------------------------
func receive_packet(packet_type: DataTypes.PACKETS):
	match packet_type:
		DataTypes.PACKETS.BUILDING:
			_handle_building_packet()
		DataTypes.PACKETS.ENERGY:
			_handle_energy_packet()
		DataTypes.PACKETS.AMMO:
			if has_method("receive_ammo_packet"):
				pass#receive_ammo_packet()
		DataTypes.PACKETS.ORE:
			if has_method("receive_ore_packet"):
				pass#receive_ore_packet()
		DataTypes.PACKETS.TECH:
			if has_method("receive_tech_packet"):
				pass#receive_tech_packet()
		_:
			push_warning("Unknown packet type received: %s" % str(packet_type))

# -------------------------------
# --- Packet Type Handlers ------
# -------------------------------
func _handle_building_packet() -> void:
	if is_built:
		return
	packets_received += 1
	packets_on_the_way = max(0, packets_on_the_way - 1)
	build_progress = packets_received

	if build_progress >= cost_to_build:
		is_built = true
		set_powered(true)
		_updates_visuals()
		is_scheduled_to_build = false
		packets_on_the_way = 0

func _handle_energy_packet() -> void:
	if not is_built:
		return

	packets_on_the_way = max(0, packets_on_the_way - 1)
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
			# Needs building packets if not yet built and not fully scheduled
			return not is_built and not is_scheduled_to_build

		DataTypes.PACKETS.ENERGY:
			# Needs energy if built, powered, and not fully supplied
			return is_built and is_powered and (supply_level < cost_to_supply)

		DataTypes.PACKETS.AMMO:
			# Optional: later for turrets etc.
			return has_method("needs_ammo_packet") and call("needs_ammo_packet")

		DataTypes.PACKETS.ORE:
			return has_method("needs_ore_packet") and call("needs_ore_packet")

		DataTypes.PACKETS.TECH:
			return has_method("needs_tech_packet") and call("needs_tech_packet")

		_:
			return false


# -------------------------------
# --- Cleanup -------------------
# -------------------------------
func destroy():
	if network_manager:
		network_manager.unregister_relay(self)
	if building_manager:
		building_manager.unregister_building(self)

	# Disconnect from others to avoid dangling references
	for other in connected_relays:
		if is_instance_valid(other):
			other.connected_relays.erase(self)
	connected_relays.clear()

	queue_free()

func consume_energy() -> float:
	if not is_built or not is_powered:
		return 0.0
	return energy_consumption_rate
