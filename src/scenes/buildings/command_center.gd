class_name Command_Center
extends Relay

@export var max_energy_capacity: int = 150
@export var stored_energy: int = 0
@export var energy_regen_rate: int = 2
@export var packet_cost: int = 10

# Called each tick by NetworkManager
func produce_energy() -> int:
	if stored_energy < max_energy_capacity:
		var prev = stored_energy
		stored_energy = min(max_energy_capacity, stored_energy + energy_regen_rate)
		return stored_energy - prev
	return 0

func has_enough_energy() -> bool:
	return stored_energy >= packet_cost

func spend_energy() -> void:
	stored_energy = max(0, stored_energy - packet_cost)

func available_ratio() -> float:
	return float(stored_energy) / float(max_energy_capacity)
