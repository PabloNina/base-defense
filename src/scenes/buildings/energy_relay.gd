class_name Relay
extends Node2D

@export var connection_range: float = 200.0
@export var is_base: bool = false

@onready var sprite_2d: Sprite2D = $Sprite2D

var is_powered: bool = false
var connected_relays: Array[Relay] = []
var network_manager: NetworkManager

func _ready():
	add_to_group("relays")

	network_manager = get_tree().get_first_node_in_group("network_manager")
	
	if network_manager:
		network_manager.register_relay(self)
	
	update_power_visual()

func connect_to(other_relay: Relay):
	if not connected_relays.has(other_relay):
		connected_relays.append(other_relay)


func disconnect_from(other_relay: Relay):
	connected_relays.erase(other_relay)

func set_powered(power_state: bool):
	is_powered = power_state
	update_power_visual()

func update_power_visual():
	if not sprite_2d:
		return
	if is_powered == true:
		sprite_2d.modulate = Color(0.3, 1.0, 0.3)
	else:
		sprite_2d.modulate = Color(1.0, 0.3, 0.3)
		
func destroy():
	if network_manager:
		network_manager.unregister_relay(self)
	queue_free()
