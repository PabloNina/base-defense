class_name Relay
extends Node2D

#Listener: Network Manager on register Relay
signal clicked(relay: Relay)
@onready var building_hurt_box: Area2D = $BuildingHurtBox

# -------------------------------
# --- Editor Settings -----------
# -------------------------------

@export var connection_range: float = 200.0
@export var cost_to_build: int = 1
@export var is_base: bool = false

# -------------------------------
# --- Nodes / State -------------
# -------------------------------

var packets_received: int = 0
var packets_on_the_way: int = 0
var is_powered: bool = false
var is_scheduled: bool = false  # relay has a packet already on the way
var connected_relays: Array[Relay] = []
var network_manager: NetworkManager

# -------------------------------
# --- Engine Callbacks ----------
# -------------------------------

func _ready():
	#
	building_hurt_box.area_clicked.connect(on_hurtbox_clicked)
	
	add_to_group("relays")
	network_manager = get_tree().get_first_node_in_group("network_manager")
	if network_manager:
		network_manager.register_relay(self)
	_update_power_visual()

###################################
###################################
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
# --- Power Handling ------------
# -------------------------------

func set_powered(state: bool):
	is_powered = state
	_update_power_visual()

func _update_power_visual():
	#if not sprite_2d:
		#return
	#sprite_2d.modulate = Color(0.3, 1.0, 0.3) if is_powered else Color(1.0, 0.3, 0.3)
	pass
# -------------------------------
# --- Cleanup -------------------
# -------------------------------

func destroy():
	if network_manager:
		network_manager.unregister_relay(self)
	queue_free()
