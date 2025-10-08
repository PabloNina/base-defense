class_name Relay
extends Node2D

# -------------------------------
# --- Editor Settings -----------
# -------------------------------

@export var connection_range: float = 200.0
@export var is_base: bool = false

# -------------------------------
# --- Nodes / State -------------
# -------------------------------

@onready var sprite_2d: Sprite2D = $Sprite2D
var is_powered: bool = false
var is_scheduled: bool = false  # relay has a packet already on the way
var connected_relays: Array[Relay] = []
var network_manager: NetworkManager

# -------------------------------
# --- Base Energy System --------
# -------------------------------
@export var energy_capacity: int = 150
@export var energy: int = 100
@export var energy_regen_rate: int = 5   # per second
@export var packet_cost: int = 20


# -------------------------------
# --- Engine Callbacks ----------
# -------------------------------

func _ready():
	add_to_group("relays")
	network_manager = get_tree().get_first_node_in_group("network_manager")
	if network_manager:
		network_manager.register_relay(self)
	update_power_visual()

# -------------------------------
# --- Network Linking -----------
# -------------------------------

func connect_to(other_relay: Relay):
	if not connected_relays.has(other_relay):
		connected_relays.append(other_relay)

func disconnect_from(other_relay: Relay):
	connected_relays.erase(other_relay)

# -------------------------------
# --- Power Handling ------------
# -------------------------------

func set_powered(state: bool):
	is_powered = state
	update_power_visual()

func update_power_visual():
	if not sprite_2d:
		return
	sprite_2d.modulate = Color(0.3, 1.0, 0.3) if is_powered else Color(1.0, 0.3, 0.3)
	
# -------------------------------
# --- Base Energy System --------
# -------------------------------

func has_enough_energy() -> bool:
	return energy >= packet_cost

func spend_energy():
	energy = max(0.0, energy - packet_cost)
	
func regen_energy():
	if energy < energy_capacity:
		energy = min(energy_capacity, energy + energy_regen_rate)
		
#func regen_energy(delta: float):
	#if energy < energy_capacity:
		#energy = min(energy_capacity, energy + energy_regen_rate * delta)
		
# -------------------------------
# --- Cleanup -------------------
# -------------------------------

func destroy():
	if network_manager:
		network_manager.unregister_relay(self)
	queue_free()
