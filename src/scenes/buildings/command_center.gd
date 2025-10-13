class_name Command_Center
extends Relay

@export var max_energy_capacity: int = 200
@export var stored_energy: int = 100
@export var base_regen_rate: int = 4       # intrinsic regen
var generators_regen_rate: int = 0         # accumulated generator bonus each tick

# --- Per-packet energy cost table ---
var packet_costs := {
	DataTypes.PACKETS.BUILDING: 15,  # building = expensive
	DataTypes.PACKETS.ENERGY: 5,     # supply = cheap
	DataTypes.PACKETS.AMMO: 8,
	DataTypes.PACKETS.ORE: 10,
	DataTypes.PACKETS.TECH: 20
}

# --- Energy Production ---
func produce_energy() -> int:
	# Total energy produced this tick = base + generators
	var total_generated := base_regen_rate + generators_regen_rate
	stored_energy = min(max_energy_capacity, stored_energy + total_generated)

	# Reset generator contribution after applying
	generators_regen_rate = 0

	return total_generated

# --- Energy Spend & Queries ---
func get_packet_cost(packet_type: int) -> int:
	return packet_costs.get(packet_type)

func has_enough_energy(packet_type: int) -> bool:
	return stored_energy >= get_packet_cost(packet_type)

func spend_energy(packet_type: int, packet_cout: int) -> void:
	var total_cost = get_packet_cost(packet_type) * packet_cout
	stored_energy = max(0, stored_energy - total_cost)

# --- Ratio (used for throttling) ---
func available_ratio() -> float:
	if max_energy_capacity <= 0:
		return 0.0
	# Use base + generator contribution to compute ratio
	var effective_energy := stored_energy + generators_regen_rate
	return float(effective_energy) / float(max_energy_capacity)
