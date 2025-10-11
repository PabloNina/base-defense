class_name Command_Center
extends Relay

# -------------------------------
# --- Base Energy System --------
# -------------------------------
@export var max_energy_capacity: int = 150
@export var stored_energy: int = 0
@export var energy_regen_rate: int = 5   # per tick
@export var packet_cost: int = 10

# -------------------------------
# --- Base Energy System --------
# -------------------------------

func has_enough_energy() -> bool:
	return stored_energy >= packet_cost

func spend_energy():
	stored_energy = max(0.0, stored_energy - packet_cost)
	
func regen_energy():
	if stored_energy < max_energy_capacity:
		stored_energy = min(max_energy_capacity, stored_energy + energy_regen_rate)
