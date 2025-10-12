class_name Relay
extends Node2D

# -------------------------------
# --- Signals -------------------
# -------------------------------
# Listener BuildingManager -> on register_building
signal clicked(relay: Relay)

# -------------------------------
# --- Editor Settings ----------- 
# -------------------------------
@export var connection_range: float = 200.0
@export var cost_to_build: int = 1        # packets needed to build
@export var cost_to_supply: int = 1  # packets needed to maintain supply
@export var is_base: bool = false

# -------------------------------
# --- Nodes / State -------------
# -------------------------------
@onready var building_hurt_box: Area2D = $BuildingHurtBox

var is_built: bool = false
var packets_received: int = 0            # total packets received for building
var packets_on_the_way: int = 0          # packets currently in flight toward this relay
var is_powered: bool = false
var is_scheduled: bool = false           # packet already scheduled to arrive
var connected_relays: Array[Relay] = []

var network_manager: NetworkManager
var building_manager: BuildingManager   

# -------------------------------
# --- Engine Callbacks ----------
# -------------------------------
func _ready():
	# connect click detection
	building_hurt_box.area_clicked.connect(on_hurtbox_clicked)

	add_to_group("relays")

	# register with NetworkManager
	network_manager = get_tree().get_first_node_in_group("network_manager")
	if network_manager:
		network_manager.register_relay(self)

	# register with BuildingManager
	building_manager = get_tree().get_first_node_in_group("building_manager")
	if building_manager:
		building_manager.register_building(self)

	_update_power_visual()

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
# --- Power & Build Handling ----
# -------------------------------
func set_powered(state: bool):
	if is_powered == state:
		return

	is_powered = state
	_update_power_visual()


# ------------------------------------------
# --- Packet Reception ---------------------
# ------------------------------------------
func receive_packet(packet_type: DataTypes.PACKETS):
	match packet_type:
		DataTypes.PACKETS.BUILDING:
			if is_built:
				return
			packets_received += 1
			if packets_received >= cost_to_build:
				is_built = true
				set_powered(true)
				_update_power_visual()
				packets_on_the_way = 0

		DataTypes.PACKETS.ENERGY:
			if is_built and is_powered:
				packets_on_the_way = max(0, packets_on_the_way - 1)

		DataTypes.PACKETS.AMMO:
			if has_method("receive_ammo_packet"):
				pass#receive_ammo_packet()

		DataTypes.PACKETS.ORE:
			if has_method("receive_ore_packet"):
				pass#receive_ore_packet()

		DataTypes.PACKETS.TECH:
			if has_method("receive_tech_packet"):
				pass#receive_tech_packet()
				

func _update_power_visual():
	# TODO: implement visual feedback (color, glow, etc)
	pass

# -------------------------------
# --- Cleanup -------------------
# -------------------------------
func destroy():
	if network_manager:
		network_manager.unregister_relay(self)
	if building_manager:
		building_manager.unregister_building(self)

	# disconnect from all relays to prevent dangling links
	for other in connected_relays:
		if is_instance_valid(other):
			other.connected_relays.erase(self)

	connected_relays.clear()
	queue_free()
