# =========================================
# NetworkManager.gd
# =========================================
class_name NetworkManager extends Node
# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
@export var packet_manager: PacketManager
@export_group("ComputeQuota")
@export var throttle_exponent: float = 1.6
@export var critical_threshold: float = 0.12
@export var ema_alpha: float = 0.25 # smoothing factor for energy ratio (0..1)
@export var enable_quota_debug: bool = false
@export var ema_alpha_rise: float = 0.8 # faster smoothing when ratio increases
@export var ema_alpha_fall: float = 0.25 # slower smoothing when ratio decreases
# -----------------------------------------
# --- Onready Variables -------------------
# -----------------------------------------
@onready var lines_2d_container: Node = $Lines2DContainer
# -----------------------------------------
# --- Runtime Data ------------------------
# -----------------------------------------
var registered_buildings: Array[Building] = [] # All active buildings in the network
var connections: Array = []                 # Connection visuals between buildings
# -----------------------------------------
# --- Cached Data for Optimization --------
# -----------------------------------------
var path_cache: Dictionary = {}             # { "aID_bID": [Relay path] } cached buildings paths
var distance_cache: Dictionary = {}         # { "aID_bID": float } cached buildings distances
var reachable_cache: Dictionary = {}        # { base: [reachable_relays] } which buildings a base can reach
var last_target_index: Dictionary = {}      # { base: int } tracks incremental target selection
# -----------------------------------------
# --- Energy Tracking ---------------------
# -----------------------------------------
signal ui_update_packets(pkt_stored: float, max_pkt_capacity: float , pkt_produced: float, pkt_consumed: float, net_balance: float)

const MIN_PACKETS_PER_TICK: int = 0
const MAX_PACKETS_PER_TICK: int = 12
const ENERGY_CRITICAL_THRESHOLD: float = 0.12  # 12% energy

# Smoothed energy ratio (EMA). Single value since only one Command Center is allowed.
var _smoothed_energy_ratio: float = 0.0

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready():
	add_to_group("network_manager")
	initialize_network()

# -----------------------------------------
# --- Buildings Registration ------------------
# -----------------------------------------
func register_relay(new_building: Building):
	if new_building in registered_buildings:
		return
	
	# Prevents connecting multiple times the same signal when moving buildings
	if not new_building.finish_building.is_connected(_on_building_built):
		new_building.finish_building.connect(_on_building_built)
	
	registered_buildings.append(new_building)
	_update_connections_for(new_building)

	if new_building is Command_Center:
		new_building.set_powered_state(true)
		_setup_cc_tick_timer(new_building)

	_refresh_network_caches()
	_update_network_integrity()

	if new_building.is_built:
		new_building.set_powered_state(true)
		new_building._updates_visuals()


func unregister_relay(building: Building):
	if building not in registered_buildings:
		return

	# Remove all packets referencing this building
	for packet in get_tree().get_nodes_in_group("packets"):
		if packet is Packet and building in packet.path:
			packet.queue_free()

	# Remove building from network
	registered_buildings.erase(building)
	
	# Clear connections first
	_clear_connections_for(building)
	for other in registered_buildings:
		other.connected_buildings.erase(building)

	# Update network state (order is important)
	_refresh_network_caches() # clears all cached data Dictionaries
	_rebuild_all_connections() # handles both connections and power states 


# -----------------------------------------
# --- Network Construction ----------------
# -----------------------------------------
func initialize_network():
	_rebuild_all_connections()

# Fully clears and rebuilds all physical connections in the network.
# This is more expensive and is only needed after mass changes or a full reset.
# Usually you only need to call _refresh_network_caches and _update_network_integrity for incremental changes.
func _rebuild_all_connections():
	_clear_all_connections()
	for building in registered_buildings:
		building.connected_buildings.clear()
	# Build physical connections
	for i in range(registered_buildings.size()):
		for j in range(i + 1, registered_buildings.size()):
			var a = registered_buildings[i]
			var b = registered_buildings[j]
			if _are_relays_in_range(a, b):
				_connect_relays(a, b)
	# Update caches and power states after rebuilding
	_refresh_network_caches()
	_update_network_integrity() 


# Connects the newly registered building to all other buildings in range.
# Called only when a building is registered (added to the network).
# This ensures new buildings are physically connected to all valid neighbors.
func _update_connections_for(new_building: Building):
	for building in registered_buildings:
		if building == new_building:
			continue
		if _are_relays_in_range(building, new_building):
			_connect_relays(building, new_building)

func _are_relays_in_range(a: Building, b: Building) -> bool:
	if not a.is_relay and not b.is_relay:
		return false

	var key = str(a.get_instance_id()) + "_" + str(b.get_instance_id())
	if distance_cache.has(key):
		return distance_cache[key] <= min(a.connection_range, b.connection_range)

	var dist = a.global_position.distance_to(b.global_position)
	distance_cache[key] = dist
	return dist <= min(a.connection_range, b.connection_range)
	
# Helper for packet manager and generators
func are_connected(a: Building, b: Building) -> bool:
	if not reachable_cache.has(a):
		return false
	return b in reachable_cache[a]
	
# Public static-like helper for ghost preview: 
# checks if two buildings (or a ghost) would connect, given their types, positions, and is_relay flags.
static func can_buildings_connect(type_a: int, pos_a: Vector2, is_relay_a: bool, type_b: int, pos_b: Vector2, is_relay_b: bool) -> bool:
	if not is_relay_a and not is_relay_b:
		return false
	var range_a = DataTypes.get_connection_range(type_a)
	var range_b = DataTypes.get_connection_range(type_b)
	var dist = pos_a.distance_to(pos_b)
	return dist <= min(range_a, range_b)

func _connect_relays(a: Building, b: Building):
	a.connect_to(b)
	b.connect_to(a)
	if not _connection_exists(a, b):
		_create_connection_line(a, b)

func _connection_exists(a: Building, b: Building) -> bool:
	for c in connections:
		if (c.relay_a == a and c.relay_b == b) or (c.relay_a == b and c.relay_b == a):
			return true
	return false

# used only in unregister
func _clear_connections_for(building: Building):
	for c in connections:
		if c.relay_a == building or c.relay_b == building:
			if is_instance_valid(c.connection_line):
				c.connection_line.queue_free()
	connections = connections.filter(func(c): return c.relay_a != building and c.relay_b != building)

func _clear_all_connections():
	for c in connections:
		if is_instance_valid(c.connection_line):
			c.connection_line.queue_free()
	connections.clear()

func _create_connection_line(a: Building, b: Building):
	var line := Line2D.new()
	line.width = 1
	line.default_color = Color(0.3, 0.9, 1.0)
	line.points = [a.global_position, b.global_position]
	lines_2d_container.add_child(line)
	connections.append({"relay_a": a, "relay_b": b, "connection_line": line})

# -----------------------------------------
# --- Network Cache -----------------------
# -----------------------------------------
# Updates all pathfinding, reachability, and distance caches for the network.
# Call this after adding/removing buildings or when a relay is built/destroyed.
func _refresh_network_caches():
	path_cache.clear()
	distance_cache.clear()
	reachable_cache.clear()
	last_target_index.clear()

	for base in registered_buildings:
		if base is Command_Center:
			reachable_cache[base] = _get_reachable_relays(base)
			last_target_index[base] = 0

func _get_reachable_relays(base: Building) -> Array:
	var visited: Array = [base]
	var queue: Array = [base]

	while queue.size() > 0:
		var current: Building = queue.pop_front()
		for neighbor in current.connected_buildings:
			if not is_instance_valid(neighbor):
				continue
			# Always add neighbor to visited so unbuilt targets are discoverable
			if neighbor not in visited:
				visited.append(neighbor)
				# Only traverse through built neighbors (enqueue) so paths don't go through unbuilt relays
				if neighbor.is_built:
					queue.append(neighbor)

				# Cache path to neighbor (path may include unbuilt neighbor as final node)
				var key = str(base.get_instance_id()) + "_" + str(neighbor.get_instance_id())
				path_cache[key] = _find_path(base, neighbor)
	return visited

# -----------------------------------------
# --- Network Integrity -------------------
# -----------------------------------------
# Recalculates which buildings are powered, updates connection line colors, and handles cluster power state.
# Call this after any change to the network topology or after caches are refreshed.
func _update_network_integrity():
	var visited := {}
	var powered_map := {}

	for building in registered_buildings:
		if building in visited:
			continue

		var cluster := []
		var queue := [building]
		var cluster_has_cc := false

		while queue.size() > 0:
			var r = queue.pop_front()
			if r in visited:
				continue
			visited[r] = true
			cluster.append(r)
			if r is Command_Center:
				cluster_has_cc = true
			for n in r.connected_buildings:
				if is_instance_valid(n) and n not in visited:
					queue.append(n)

		# Reset construction progress if cluster is isolated
		if not cluster_has_cc:
			_reset_isolated_construction(cluster)

		# Set power state for cluster
		for r in cluster:
			# Only built buildings can be powered. An unbuilt relay should not appear powered.
			var powered_state = cluster_has_cc and r.is_built
			r.set_powered_state(powered_state)
			powered_map[r] = powered_state

	# Update connection visuals
	for c in connections:
		if not is_instance_valid(c.connection_line):
			continue
		var a_powered = powered_map.get(c.relay_a, false)
		var b_powered = powered_map.get(c.relay_b, false)
		# Valid (blue) if either endpoint is powered, invalid (red) only if both are unpowered
		c.connection_line.default_color = Color(0.3, 0.9, 1.0) if (a_powered or b_powered) else Color(1, 0.3, 0.3)

func _reset_isolated_construction(cluster: Array):
	for building in cluster:
		if not building.is_built:
			building.reset_packets_in_flight()

###############################
func _on_building_built() -> void:
	_refresh_network_caches()
	_update_network_integrity()
#############################
# -----------------------------------------
# --- CommandCenter Timer / Tick ----------
# -----------------------------------------

func _setup_cc_tick_timer(cc: Command_Center):
	cc.tick_timer.timeout.connect(_on_command_center_tick.bind(cc))

# -----------------------------------------
# --- Command_Center Tick -----------------
# -----------------------------------------
func _on_command_center_tick(command_center: Command_Center):
	if not command_center is Command_Center:
		return

	#print("--- TICK START ---")
	#print("Initial stored: ", command_center.stored_packets)

	var packets_produced: float = 0.0
	var packets_spent: float = 0.0
	var packets_consumed: float = 0.0
	var packets_allowed: int = MIN_PACKETS_PER_TICK 
	
	# --- Stage 1: Add all active buildings per tick packet consumption ---
	for building in registered_buildings:
		if building.is_powered and building.is_built:
			packets_consumed += building.consume_packets()
	
	# --- Stage 2: Add Generator bonuses to Command Center ---
	for generator in registered_buildings:
		if generator is EnergyGenerator and generator.is_powered and generator.is_built:
			generator.add_packet_production_bonus()

	# --- Stage 3: Command Center generates packets ---
	packets_produced = command_center.produce_packets()
	#print("Produced: ", packets_produced)
	#print("Stored after production: ", command_center.stored_packets)

	# --- Stage 3.5: Command Center consumes packets ---
	# Pay all active buildings per tick packet consumption
	command_center.deduct_buildings_consumption(packets_consumed)
	#print("Consumed (upkeep): ", packets_consumed)
	#print("Stored after upkeep: ", command_center.stored_packets)

	# Update smoothed energy ratio (asymmetric EMA) for this command center before computing quota
	var raw_ratio := command_center.available_ratio()
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
	packets_allowed = _compute_packet_quota(command_center)
	var packet_quota: int = packets_allowed
	#print(packet_quota)

	# --- Stage 4: Command Center starts packet propagation ---
	var packet_types := [
		DataTypes.PACKETS.BUILDING,
		DataTypes.PACKETS.ENERGY,
		DataTypes.PACKETS.AMMO,
		DataTypes.PACKETS.ORE,
		DataTypes.PACKETS.TECH
	]

	for pkt_type in packet_types:
		if packet_quota <= 0:
			break
		var packets_sent := packet_manager.start_packet_propagation(command_center, packet_quota, pkt_type)
		if packets_sent > 0 and command_center is Command_Center:
			var cc := command_center as Command_Center
			# Command_Center deducts stored packets
			cc.deduct_packets_sent(packets_sent)
			#print("Sent for ", pkt_type, ": ", packets_sent)
			#print("Stored after sending: ", command_center.stored_packets)
			# Track total packets spent for UI
			packets_spent += packets_sent 
			packet_quota -= packets_sent

	# --- Stage 5: Update packet stats and Ui ---
	# Calculate total consumption (packets spent + building consumption)
	var total_consumption: float = packets_spent + packets_consumed
	
	# Update raw net balance
	var net_balance: float = packets_produced - total_consumption

	#print("Final stored: ", command_center.stored_packets)
	#print("--- TICK END ---")

	# Update UI with proper values
	ui_update_packets.emit(
		command_center.stored_packets,  # current packets stored
		command_center.max_packet_capacity, # current max storage
		packets_produced,          # total produced
		total_consumption,         # total consumed
		net_balance                # net balance
	)


# Calculates how many packets the Command Center can send this tick.
# This is based on available stored packets, network size, and throttling for low energy.
func _compute_packet_quota(command_center: Command_Center) -> int:
	# 1. Compute the ratio of available packets to max capacity (energy_ratio).
	# Use the smoothed energy ratio (single CC) or fall back to raw
	var energy_ratio := _smoothed_energy_ratio if _smoothed_energy_ratio > 0.0 else command_center.available_ratio()
	
	# 2. Apply aggressive throttling if energy is low (throttle_ratio).
	# More aggressive throttling at low energy. Uses exported parameters for tuning.
	var throttle_ratio := pow(energy_ratio, throttle_exponent) if energy_ratio > critical_threshold else 0.5 * energy_ratio

	# 3. Scale the max packet limit by network size (network_size_factor).
	var network_size_factor := sqrt(float(registered_buildings.size()) / 20.0)  # Adjust divisor as needed
	var dynamic_packet_limit := MAX_PACKETS_PER_TICK * network_size_factor
	
	# 4. Determine the max number of packets that can be afforded (max_affordable).
	var max_affordable := int(floor(float(command_center.stored_packets) / 1.0 )) # 1 = packet cost
	# 5. The desired number of packets is the dynamic limit scaled by throttle_ratio.
	var desired_packets := int(floor(dynamic_packet_limit * throttle_ratio))

	# 6. The final quota is the minimum of desired_packets and max_affordable, clamped to allowed range.
	# DON'T force a minimum of 1 here. Allow zero when energy is too low or max_affordable == 0.
	var result: int = min(desired_packets, max_affordable)
	# Clamp to the allowed range but allow 0.
	var final_quota = clamp(result, MIN_PACKETS_PER_TICK, MAX_PACKETS_PER_TICK)

	# 7. Preventing a final quota of 0 if cc has at least 1 packet stored
	if final_quota == 0 and command_center.stored_packets >= 1:
		final_quota = 1
		
	##### DEBUG ######
	if enable_quota_debug:
		prints("[QuotaDebug] CC =", command_center, "raw_ratio =", command_center.available_ratio(), "smoothed =", energy_ratio, "throttle =", throttle_ratio, "dyn_limit =", dynamic_packet_limit, "desired =", desired_packets, "affordable =", max_affordable, "final =", final_quota)
	
	# Returns: The number of packets the Command Center is allowed to send this tick.
	return final_quota

# -----------------------------------------
# --- Pathfinding -------------------------
# -----------------------------------------
func _find_path(start: Building, goal: Building) -> Array[Building]:
	var queue: Array = [[start]]
	var visited: Array[Building] = [start]

	while queue.size() > 0:
		var path: Array = queue.pop_front()
		var current: Building = path[-1]
		if current == goal:
			var typed_path: Array[Building] = []
			for node in path:
				typed_path.append(node as Building)
			return typed_path
		for neighbor in current.connected_buildings:
			if is_instance_valid(neighbor) and neighbor not in visited:
				visited.append(neighbor)
				var new_path = path.duplicate()
				new_path.append(neighbor)
				queue.append(new_path)
	return []
