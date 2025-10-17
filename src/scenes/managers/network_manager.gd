# =========================================
# NetworkManager.gd
# =========================================
class_name NetworkManager
extends Node

# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
@export var building_packet_scene: PackedScene
@export var energy_packet_scene: PackedScene
@export var ammo_packet_scene: PackedScene
@export var current_packet_speed: int = 150

# -----------------------------------------
# --- Runtime Data ------------------------
# -----------------------------------------
var registered_buildings: Array[Building] = [] # All active buildings in the network
var connections: Array = []                 # Connection visuals between buildings
var base_timers: Dictionary = {}            # { base_relay: Timer } handles packet spawning timers

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
signal ui_update_energy(current_energy: float, produced: float, consumed: float, net_balance: float)

var net_balance: float = 0.0  # Raw net balance

const MIN_PACKETS_PER_TICK := 1
const MAX_PACKETS_PER_TICK := 8
const ENERGY_CRITICAL_THRESHOLD := 0.1  # 10% energy
const BASE_TICK_RATE := 0.5  # 2 ticks per second

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready():
	add_to_group("network_manager")
	initialize_network()

# -----------------------------------------
# --- Relay Registration ------------------
# -----------------------------------------
func register_relay(new_building: Building):
	if new_building in registered_buildings:
		return
	registered_buildings.append(new_building)
	_update_connections_for(new_building)

	if new_building is Command_Center:
		new_building.set_powered(true)
		_setup_packet_timer(new_building)

	_refresh_network_caches()
	_update_network_integrity()

	if new_building.is_built:
		new_building.set_powered(true)
		new_building._updates_visuals()

func unregister_relay(building: Building):
	if building not in registered_buildings:
		return

	# Remove all packets referencing this relay
	for packet in get_tree().get_nodes_in_group("packets"):
		if packet is Packet and building in packet.path:
			packet.queue_free()

	# Remove relay from network
	registered_buildings.erase(building)
	
	# Clear connections first
	_clear_connections_for(building)
	for other in registered_buildings:
		other.connected_relays.erase(building)

	# Remove timers
	if base_timers.has(building):
		base_timers[building].queue_free()
		base_timers.erase(building)

	# Update network state (order is important)
	_refresh_network_caches() # clears all cashed data Dictionaries
	_rebuild_all_connections() # handles both connections and power states 

# -----------------------------------------
# --- Network Construction ----------------
# -----------------------------------------
func initialize_network():
	_rebuild_all_connections()

func _rebuild_all_connections():
	_clear_all_connections()
	for building in registered_buildings:
		building.connected_relays.clear()
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

# used only in register
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


# Public static-like helper for ghost preview: checks if two buildings (or a ghost) would connect, given their types, positions, and is_relay flags.
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
	add_child(line)
	connections.append({"relay_a": a, "relay_b": b, "connection_line": line})

# -----------------------------------------
# --- Network Cache -----------------------
# -----------------------------------------
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
		for neighbor in current.connected_relays:
			if is_instance_valid(neighbor) and neighbor not in visited:
				visited.append(neighbor)
				queue.append(neighbor)
				var key = str(base.get_instance_id()) + "_" + str(neighbor.get_instance_id())
				path_cache[key] = _find_path(base, neighbor)
	return visited

func are_connected(a: Building, b: Building) -> bool:
	if not reachable_cache.has(a):
		return false
	return b in reachable_cache[a]

# -----------------------------------------
# --- Network Integrity -------------------
# -----------------------------------------
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
			for n in r.connected_relays:
				if is_instance_valid(n) and n not in visited:
					queue.append(n)

		# Reset construction progress if cluster is isolated
		if not cluster_has_cc:
			_reset_isolated_construction(cluster)

		# Set power state for cluster
		for r in cluster:
			r.set_powered(cluster_has_cc)
			powered_map[r] = cluster_has_cc

	# Update connection visuals
	for c in connections:
		if not is_instance_valid(c.connection_line):
			continue
		var a_powered = powered_map.get(c.relay_a, false)
		var b_powered = powered_map.get(c.relay_b, false)
		c.connection_line.default_color = Color(0.3, 0.9, 1.0) if (a_powered and b_powered) else Color(1, 0.3, 0.3)

func _reset_isolated_construction(cluster: Array):
	for building in cluster:
		if not building.is_built:
			building.packets_on_the_way = 0
			building.is_scheduled_to_build = false

# -----------------------------------------
# --- Timer / Packet System ---------------
# -----------------------------------------
var base_tick_rate := BASE_TICK_RATE
var tick_rate_multiplier := 1.0

func _setup_packet_timer(base: Building):
	if base in base_timers:
		return
	var timer: Timer = Timer.new()
	timer.wait_time = base_tick_rate / tick_rate_multiplier
	timer.autostart = true
	timer.one_shot = false
	#timer.connect("timeout", Callable(self, "_on_packet_tick").bind(base))
	timer.timeout.connect(_on_packet_tick.bind(base))
	add_child(timer)
	base_timers[base] = timer

# Adjust tick rate dynamically
func adjust_network_speed(multiplier: float):
	tick_rate_multiplier = clampf(multiplier, 0.5, 2.0)
	for timer in base_timers.values():
		timer.wait_time = base_tick_rate / tick_rate_multiplier

# -----------------------------------------
# --- Packet Tick -------------------------
# -----------------------------------------
func _on_packet_tick(command_center: Building):
	if not command_center is Command_Center:
		return

	var energy_produced: float = 0.0
	var energy_spent: float = 0.0
	var energy_consumed: float = 0.0
	var packets_allowed: int = MIN_PACKETS_PER_TICK  # amout of packet to be spawned
	
	# --- Stage 0: Add all active buildings energy consumption ---
	for building in registered_buildings:
		if building.is_powered and building.is_built:
			energy_consumed += building.consume_energy()
	
	# --- Stage 1: Add Generator bonuses ---
	for generator in registered_buildings:
		if generator is EnergyGenerator and generator.is_powered and generator.is_built:
			generator.provide_energy_bonus()

	# --- Stage 2: Command Center produces energy ---
	if command_center is Command_Center:
		var cc := command_center as Command_Center
		energy_produced = cc.produce_energy()
		
		# --- Stage 2.5: Command Center consumes energy ---
		cc.spend_energy_on_buildings(energy_consumed)
		# Compute packet quota with updated Command_Center stored energy
		packets_allowed = _compute_packet_quota(cc)

	var packet_quota: int = packets_allowed

	# --- Stage 3: Command Center starts packet propagation ---
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
		var sent := _start_packet_propagation(command_center, packet_quota, pkt_type)
		if sent > 0 and command_center is Command_Center:
			var cc := command_center as Command_Center
			cc.spend_energy_on_packets(pkt_type, sent)
			energy_spent += sent * cc.get_packet_cost(pkt_type)
			packet_quota -= sent

	# --- Stage 4: Update energy values and Ui ---
	# Calculate total consumption (packets spent + building consumption)
	var total_consumption: float = energy_spent + energy_consumed
	
	# Update raw net balance
	net_balance = energy_produced - total_consumption

	# Update UI with proper values
	ui_update_energy.emit(
		get_global_energy_pool(),  # current energy
		energy_produced,           # total produced
		total_consumption,         # total consumed
		net_balance                # net balance
	)

# -----------------------------------------
# Determines how many packets a base can send this tick
# -----------------------------------------
func _compute_packet_quota(command_center: Command_Center) -> int:
	var energy_ratio := command_center.available_ratio()

	# More aggressive throttling at low energy
	var throttle_ratio := pow(energy_ratio, 1.5) if energy_ratio > ENERGY_CRITICAL_THRESHOLD else 0.5 * energy_ratio

	# Dynamic packet limit based on network size
	var network_size_factor := sqrt(float(registered_buildings.size()) / 10.0)  # Adjust divisor as needed
	var dynamic_packet_limit := MAX_PACKETS_PER_TICK * network_size_factor

	var max_affordable := int(floor(float(command_center.stored_energy) / float(command_center.get_packet_cost(DataTypes.PACKETS.ENERGY))))
	var desired_packets := int(floor(dynamic_packet_limit * throttle_ratio))

	# DON'T force a minimum of 1 here. Allow zero when energy is too low or max_affordable == 0.
	var result: int = min(desired_packets, max_affordable)
	# Clamp to the allowed range but allow 0.
	return clamp(result, MIN_PACKETS_PER_TICK, MAX_PACKETS_PER_TICK)

# -----------------------------------------
# --- Packet Propagation ------------------
# -----------------------------------------
# -----------------------------------------
# Generic propagation for any packet type
# -----------------------------------------
func _start_packet_propagation(command_center: Command_Center, quota: int, packet_type: DataTypes.PACKETS) -> int:
	var packets_sent := 0
	if quota <= 0 or not reachable_cache.has(command_center):
		return 0

	var targets := []
	for building in reachable_cache[command_center]:
		if building == command_center or not is_instance_valid(building):
			continue

		# Use building's built-in needs_packet check
		if not building.needs_packet(packet_type):
			continue

		# Prevent over-queuing: skip building that already have enough packets on the way
		# (use the correct target limit depending on packet type)
		match packet_type:
			DataTypes.PACKETS.BUILDING:
				if building.packets_on_the_way >= building.cost_to_build:
					continue
			DataTypes.PACKETS.ENERGY:
				if building.packets_on_the_way >= building.cost_to_supply:
					continue
			# for other packet types you may add custom checks here
			_:
				# Default conservative check: avoid oversending if packets_on_the_way >= 1
				if building.packets_on_the_way >= building.cost_to_build and building.cost_to_build > 0:
					continue

		targets.append(building)

	if targets.is_empty():
		return 0

	# Round-robin selection over the filtered targets
	var index = last_target_index.get(command_center, 0)
	var n = targets.size()

	for i in range(n):
		if packets_sent >= quota:
			break

		var building = targets[index % n]
		index += 1

		# Skip again if target became invalid or has now enough in-flight packets (race-safe)
		if not is_instance_valid(building):
			continue
		match packet_type:
			DataTypes.PACKETS.BUILDING:
				if building.packets_on_the_way >= building.cost_to_build:
					continue
			DataTypes.PACKETS.ENERGY:
				if building.packets_on_the_way >= building.cost_to_supply:
					continue

		var key = str(command_center.get_instance_id()) + "_" + str(building.get_instance_id())
		if not path_cache.has(key):
			continue

		var path = path_cache[key]
		if path.size() <= 1 or path.any(func(r): return not is_instance_valid(r)):
			continue

		if not are_connected(path[0], path[-1]):
			continue

		var spawn_delay_step: float = 0.1  # seconds between packets
		var delay_accum: float = 0.0
		# Increment in-flight AFTER the final checks and BEFORE spawning the packet.
		# This ensures other bases/ticks see the incremented value immediately.
		building.packets_on_the_way += 1
		_spawn_packet_along_path(path, packet_type, delay_accum)
		delay_accum += spawn_delay_step
		packets_sent += 1

		# Mark scheduled state for building packets specifically
		if packet_type == DataTypes.PACKETS.BUILDING and building.packets_on_the_way >= building.cost_to_build:
			building.is_scheduled_to_build = true

	last_target_index[command_center] = index % n
	return packets_sent

# -----------------------------------------
# --- Packet spawning ---------------------
# -----------------------------------------
func _spawn_packet_along_path(path: Array[Building], packet_type: DataTypes.PACKETS, delay_offset :float = 0.0) -> void:
	# Safety checks
	if path.size() < 2:
		return
	if path.any(func(r): return not is_instance_valid(r)):
		return
	if not are_connected(path[0], path[-1]):
		return
	
	# small per-packet delay to avoid packet stacking
	if delay_offset > 0.0:
		await get_tree().create_timer(delay_offset).timeout
	
	# Create the actual packet
	var packet_scene: PackedScene
	match packet_type:
		DataTypes.PACKETS.BUILDING:
			packet_scene = building_packet_scene
		DataTypes.PACKETS.ENERGY:
			packet_scene = energy_packet_scene
		DataTypes.PACKETS.AMMO:
			packet_scene = ammo_packet_scene
		_:
			return  # Unsupported packet type
	
	# Instance and setup the packet
	var packet: Packet = packet_scene.instantiate()
	packet.path = path.duplicate()
	packet.speed = current_packet_speed
	packet.packet_type = packet_type
	packet.global_position = path[0].global_position  # ensure world position
	packet.packet_arrived.connect(_on_packet_arrived)
	add_child(packet)
	packet.add_to_group("packets")


func _on_packet_arrived(target_building: Building, packet_type: DataTypes.PACKETS):
	# Safety check: ensure building is still valid
	if not is_instance_valid(target_building):
		return
	# Decrement in-flight packet count safely
	target_building.packets_on_the_way = max(0, target_building.packets_on_the_way - 1)
	# Relay processes the packet
	target_building.receive_packet(packet_type)

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
		for neighbor in current.connected_relays:
			if is_instance_valid(neighbor) and neighbor not in visited:
				visited.append(neighbor)
				var new_path = path.duplicate()
				new_path.append(neighbor)
				queue.append(new_path)
	return []


# -----------------------------------------
# --- Energy Tracking ---------------------
# -----------------------------------------
func get_global_energy_pool() -> float:
	var total := 0
	for building in registered_buildings:
		if building is Command_Center:
			total += building.stored_energy
	return total
