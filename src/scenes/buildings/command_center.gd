class_name Command_Center extends Building
# -----------------------------------------
# --- Onready Variables -------------------
# -----------------------------------------
@onready var tick_timer: Timer = $TickTimer
# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
@export var max_packet_capacity: float = 50.0
@export var stored_packets: float = 0.0
@export var default_packet_production: float = 4.0  # intrinsic regen per tick

@export_group("ComputeQuota")
@export var throttle_exponent: float = 1.6
@export var critical_threshold: float = 0.12
@export var ema_alpha: float = 0.25 # smoothing factor for energy ratio (0..1)
@export var enable_quota_debug: bool = false
@export var ema_alpha_rise: float = 0.8 # faster smoothing when ratio increases
@export var ema_alpha_fall: float = 0.25 # slower smoothing when ratio decreases
# -----------------------------------------
# --- Signals -----------------------------
# -----------------------------------------
signal update_packets(pkt_stored: float, max_pkt_capacity: float , pkt_produced: float, pkt_consumed: float, net_balance: float)
# -----------------------------------------
# --- Packets Tracking --------------------
# -----------------------------------------
const BASE_TICK_RATE: float = 1.0 # 1 ticks per second
const MIN_PACKETS_PER_TICK: int = 0
const MAX_PACKETS_PER_TICK: int = 12
const ENERGY_CRITICAL_THRESHOLD: float = 0.12  # 12% energy

# Smoothed energy ratio (EMA). Single value since only one Command Center is allowed.
var _smoothed_energy_ratio: float = 0.0

var generators_accumulated_bonus: float = 0.0 # accumulated generator bonus each tick
var packet_manager: PacketManager

# -----------------------------------------
# --- Engine CallBacks --------------------
# -----------------------------------------
func _ready():
	super._ready()
	is_built = true
	# tick timer setup
	tick_timer.wait_time = BASE_TICK_RATE
	tick_timer.autostart = true
	tick_timer.one_shot = false
	tick_timer.timeout.connect(_on_timer_tick)
	# find and assign packet_manager
	packet_manager = get_tree().get_first_node_in_group("packet_manager")

# -----------------------------------------
# --- Timer Tick --------------------------
# -----------------------------------------
func _on_timer_tick():
	#print("--- TICK START ---")
	#print("Initial stored: ", stored_packets)

	var packets_produced: float = 0.0
	var packets_spent: float = 0.0
	var packets_consumed: float = 0.0
	var packets_allowed: int = MIN_PACKETS_PER_TICK 
	
	# --- Stage 1: Add all active buildings per tick upkeep packet consumption ---
	for building in grid_manager.registered_buildings:
		if building.is_powered and building.is_built:
			packets_consumed += building.get_upkeep_cost()
	
	# --- Stage 2: Add Generator bonuses to Command Center ---
	for generator in grid_manager.registered_buildings:
		if generator is EnergyGenerator and generator.is_powered and generator.is_built:
			generators_accumulated_bonus += generator.get_packet_production_bonus()

	# --- Stage 3: Command Center generates packets ---
	packets_produced = _produce_packets()
	var stored_for_ui = stored_packets
	#print("Produced: ", packets_produced)
	#print("Stored after production: ", stored_packets)

	# --- Stage 3.5: Command Center consumes packets ---
	# Pay all active buildings per tick upkeep packet consumption
	_deduct_buildings_upkeep(packets_consumed)
	#print("Consumed (upkeep): ", packets_consumed)
	#print("Stored after upkeep: ", stored_packets)

	# Update smoothed energy ratio (asymmetric EMA) for this command center before computing quota
	var raw_ratio := _available_ratio()
	# initialize smoothed ratio to raw on first tick
	if _smoothed_energy_ratio == 0.0:
		_smoothed_energy_ratio = raw_ratio
	# Use faster alpha when ratio is increasing to recover quicker from zeros
	var alpha := ema_alpha_fall
	if raw_ratio > _smoothed_energy_ratio:
		alpha = ema_alpha_rise
	var smoothed := _smoothed_energy_ratio * (1.0 - alpha) + raw_ratio * alpha
	_smoothed_energy_ratio = smoothed

	# Compute packet quota with updated Command_Center stored energy and smoothed ratio
	packets_allowed = _compute_packet_quota()
	var packet_quota: int = packets_allowed
	#print(packet_quota)

	# --- Stage 4: Command Center starts packet propagation ---
	var packet_types := [
		GlobalData.PACKETS.BUILDING,
		GlobalData.PACKETS.ENERGY,
		GlobalData.PACKETS.AMMO,
		GlobalData.PACKETS.ORE,
		GlobalData.PACKETS.TECH
	]

	for pkt_type in packet_types:
		if packet_quota <= 0:
			break
		var packets_sent := packet_manager.start_packet_propagation(self, packet_quota, pkt_type)
		if packets_sent > 0:
			# Command_Center deducts stored packets
			_deduct_packets_sent(packets_sent)
			#print("Sent for ", pkt_type, ": ", packets_sent)
			#print("Stored after sending: ", stored_packets)
			# Track total packets spent for UI
			packets_spent += packets_sent 
			packet_quota -= packets_sent

	# --- Stage 5: Update packet stats and Ui ---
	# Calculate total consumption (packets spent + building consumption)
	var total_consumption: float = packets_spent + packets_consumed
	
	# Update raw net balance
	var net_balance: float = packets_produced - total_consumption

	#print("Final stored: ", stored_packets)
	#print("--- TICK END ---")

	# Update UI with proper values
	update_packets.emit(
		#command_center.stored_packets, # current packets stored
		stored_for_ui,  # packets stored before consumption 
		max_packet_capacity, # current max storage
		packets_produced,          # total produced
		total_consumption,         # total consumed
		net_balance                # net balance
	)


# Calculates how many packets the Command Center can send this tick.
# This is based on available stored packets, grid size, and throttling for low energy.
func _compute_packet_quota() -> int:
	# 1. Compute the ratio of available packets to max capacity (energy_ratio).
	# Use the smoothed energy ratio (single CC) or fall back to raw
	var energy_ratio := _smoothed_energy_ratio if _smoothed_energy_ratio > 0.0 else _available_ratio()
	
	# 2. Apply aggressive throttling if energy is low (throttle_ratio).
	# More aggressive throttling at low energy. Uses exported parameters for tuning.
	var throttle_ratio := pow(energy_ratio, throttle_exponent) if energy_ratio > critical_threshold else 0.5 * energy_ratio

	# 3. Scale the max packet limit by grid size (grid_size_factor).
	var grid_size_factor := sqrt(float(grid_manager.registered_buildings.size()) / 20.0)  # Adjust divisor as needed
	var dynamic_packet_limit := MAX_PACKETS_PER_TICK * grid_size_factor
	
	# 4. Determine the max number of packets that can be afforded (max_affordable).
	var max_affordable := int(floor(float(stored_packets) / 1.0 )) # 1 = packet cost
	# 5. The desired number of packets is the dynamic limit scaled by throttle_ratio.
	var desired_packets := int(floor(dynamic_packet_limit * throttle_ratio))

	# 6. The final quota is the minimum of desired_packets and max_affordable, clamped to allowed range.
	# DON'T force a minimum of 1 here. Allow zero when energy is too low or max_affordable == 0.
	var result: int = min(desired_packets, max_affordable)
	# Clamp to the allowed range but allow 0.
	var final_quota = clamp(result, MIN_PACKETS_PER_TICK, MAX_PACKETS_PER_TICK)

	# 7. Preventing a final quota of 0 if cc has at least 1 packet stored
	if final_quota == 0 and stored_packets >= 1:
		final_quota = 1
		
	##### DEBUG ######
	if enable_quota_debug:
		prints("[QuotaDebug] CC =", self, "raw_ratio =", _available_ratio(), "smoothed =", energy_ratio, "throttle =", throttle_ratio, "dyn_limit =", dynamic_packet_limit, "desired =", desired_packets, "affordable =", max_affordable, "final =", final_quota)
	
	# Returns: The number of packets the Command Center is allowed to send this tick.
	return final_quota


# -----------------------------------------
# --- Packet Production -------------------
# -----------------------------------------
func _produce_packets() -> float:
	# Total packets produced this tick = base + generators 
	var total_generated := default_packet_production + generators_accumulated_bonus
	stored_packets = min(max_packet_capacity, stored_packets + total_generated)
	
	# Reset generator contribution after applying
	generators_accumulated_bonus = 0
	return total_generated
	
# -----------------------------------------
# --- Packet Deduction --------------------
# -----------------------------------------
func _deduct_packets_sent(packets_sent: int) -> void:
	stored_packets = max(0, stored_packets - packets_sent)

func _deduct_buildings_upkeep(buildings_consumption: float) -> void:
	stored_packets = max(0, stored_packets - buildings_consumption)
	
# -----------------------------------------
# --- Ratio (used for throttling) ---------
# -----------------------------------------
func _available_ratio() -> float:
	if max_packet_capacity <= 0.0:
		return 0.0
		
	# Use base + generator contribution to compute ratio
	var effective_energy := stored_packets #+ generators_production_bonus
	return float(effective_energy) / float(max_packet_capacity)
