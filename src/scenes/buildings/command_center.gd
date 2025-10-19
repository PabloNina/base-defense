class_name Command_Center extends Building

@onready var tick_timer: Timer = $TickTimer

@export var max_packet_capacity: float = 50.0
@export var stored_packets: float = 0.0
@export var default_packet_production: float = 4.0       # intrinsic regen per tick

var generators_production_bonus: float = 0.0        # accumulated generator bonus each tick

const BASE_TICK_RATE: float = 1.0  # 1 ticks per second


func _ready():
	#super()
	super._ready()
	is_built = true
	# tick timer setup
	tick_timer.wait_time = BASE_TICK_RATE
	tick_timer.autostart = true
	tick_timer.one_shot = false

# --- Packet Production ---
func produce_packets() -> float:
	# Total packets produced this tick = base + generators 
	var total_generated := default_packet_production + generators_production_bonus
	stored_packets = min(max_packet_capacity, stored_packets + total_generated)
	
	# Reset generator contribution after applying
	generators_production_bonus = 0
	return total_generated

# --- Packet Deduction ---
func deduct_packets_sent(packets_sent: int) -> void:
	stored_packets = max(0, stored_packets - packets_sent)

func deduct_buildings_consumption(buildings_consumption: float) -> void:
	stored_packets = max(0, stored_packets - buildings_consumption)

# --- Ratio (used for throttling) ---
func available_ratio() -> float:
	if max_packet_capacity <= 0.0:
		return 0.0
		
	# Use base + generator contribution to compute ratio
	var effective_energy := stored_packets #+ generators_production_bonus
	return float(effective_energy) / float(max_packet_capacity)
