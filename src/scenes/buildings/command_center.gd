class_name Command_Center
extends Relay

# -------------------------------
# --- Base Energy System --------
# -------------------------------
@export var energy_capacity: int = 150
@export var energy: int = 0
@export var energy_regen_rate: int = 5   # per tick
@export var packet_cost: int = 10

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
