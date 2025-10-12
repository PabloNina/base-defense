class_name NetworkManager
extends Node

# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
@export var energy_packet_scene: PackedScene
@export var energy_packet_speed: float = 150.0
@export var packets_per_tick: int = 4

# -----------------------------------------
# --- Runtime Data ------------------------
# -----------------------------------------
var relays: Array[Relay] = []               # All active relays in the network
var connections: Array = []                 # Connection visuals between relays
var base_timers: Dictionary = {}            # { base_relay: Timer } handles packet spawning timers

# -----------------------------------------
# --- Cached Data for Optimization --------
# -----------------------------------------
var path_cache: Dictionary = {}             # { "aID_bID": [Relay path] } cached relay paths
var distance_cache: Dictionary = {}         # { "aID_bID": float } cached relay distances
var reachable_cache: Dictionary = {}        # { base: [reachable_relays] } which relays a base can reach
var last_target_index: Dictionary = {}      # { base: int } tracks incremental target selection
# -----------------------------------------
# --- Energy Tracking ---------------------
# -----------------------------------------
# Listener: User_interface
# Emitted when a base relay spends or gains energy -> on tick
signal ui_update_energy(current_energy: int, current_produced: int, current_spent: int)

var global_energy_pool: int = 100  # total energy stored
var max_stored_energy: int = 150

var net_balance: float = 0.0
var rolling_factor := 0.1  # for smoothing net balance over time
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready():
	add_to_group("network_manager")
	initialize_network()

# -----------------------------------------
# --- Relay Registration ------------------
# -----------------------------------------
# Registers a new relay into the network and updates all caches & visuals
func register_relay(relay: Relay):
	if relay in relays:
		return

	relays.append(relay)
	_update_connections_for(relay)

	# Power setup for base relays
	if relay.is_base:
		relay.set_powered(true)
		_setup_packet_timer(relay)

	# Refresh network topology and power visuals
	_refresh_network_caches()
	refresh_power_states()

	if relay.is_built:
		relay.set_powered(true)
		relay._update_power_visual()

# Removes a relay from network and updates visuals and caches
func unregister_relay(relay: Relay):
	if relay not in relays:
		return

	relays.erase(relay)
	_clear_connections_for(relay)

	# Remove relay from others’ connections
	for other in relays:
		other.connected_relays.erase(relay)

	# Clear any timers associated with this relay
	if base_timers.has(relay):
		var t = base_timers[relay]
		t.queue_free()
		base_timers.erase(relay)

	# Rebuild cache and power state
	_refresh_network_caches()
	refresh_power_states()

# -----------------------------------------
# --- Network Construction ----------------
# -----------------------------------------
# Initializes the relay network at game start
func initialize_network():
	rebuild_all_connections()

# Rebuilds all relay-to-relay connections and refreshes caches
func rebuild_all_connections():
	_clear_all_connections()

	for relay in relays:
		relay.connected_relays.clear()

	for i in range(relays.size()):
		for j in range(i + 1, relays.size()):
			var a = relays[i]
			var b = relays[j]
			if _are_relays_in_range(a, b):
				_connect_relays(a, b)

	_refresh_network_caches()

# Creates connection lines for a newly registered relay
func _update_connections_for(new_relay: Relay):
	for relay in relays:
		if relay == new_relay:
			continue
		if _are_relays_in_range(relay, new_relay):
			_connect_relays(relay, new_relay)

# Determines if two relays are close enough to connect (uses distance cache)
func _are_relays_in_range(a: Relay, b: Relay) -> bool:
	var key = str(a.get_instance_id()) + "_" + str(b.get_instance_id())
	if distance_cache.has(key):
		return distance_cache[key] <= min(a.connection_range, b.connection_range)

	var dist = a.global_position.distance_to(b.global_position)
	distance_cache[key] = dist
	return dist <= min(a.connection_range, b.connection_range)

# Connects two relays bidirectionally and creates a visual line if needed
func _connect_relays(a: Relay, b: Relay):
	a.connect_to(b)
	b.connect_to(a)
	if not _connection_exists(a, b):
		_create_connection_line(a, b)

# Checks if a visual connection line already exists between two relays
func _connection_exists(a: Relay, b: Relay) -> bool:
	for c in connections:
		if (c.relay_a == a and c.relay_b == b) or (c.relay_a == b and c.relay_b == a):
			return true
	return false

# Removes all connections involving a specific relay
func _clear_connections_for(relay: Relay):
	for c in connections:
		if c.relay_a == relay or c.relay_b == relay:
			if is_instance_valid(c.connection_line):
				c.connection_line.queue_free()
	connections = connections.filter(func(c): return c.relay_a != relay and c.relay_b != relay)

# Removes all connection visuals from the scene
func _clear_all_connections():
	for c in connections:
		if is_instance_valid(c.connection_line):
			c.connection_line.queue_free()
	connections.clear()

# Creates the visible connection line between two relays
func _create_connection_line(a: Relay, b: Relay):
	var line := Line2D.new()
	line.width = 1
	line.default_color = Color(0.3, 0.9, 1.0)
	line.points = [a.global_position, b.global_position]
	add_child(line)
	connections.append({"relay_a": a, "relay_b": b, "connection_line": line})

# -----------------------------------------
# --- Network Cache -----------------------
# -----------------------------------------
# Refreshes all cached pathfinding and reachability data
func _refresh_network_caches():
	path_cache.clear()
	distance_cache.clear()
	reachable_cache.clear()
	last_target_index.clear()

	# Compute reachable relays for each base
	for base in relays:
		if base.is_base:
			reachable_cache[base] = _get_reachable_relays(base)
			last_target_index[base] = 0

# BFS that finds all reachable relays from a given base and stores shortest paths
func _get_reachable_relays(base: Relay) -> Array:
	var visited: Array = [base]
	var queue: Array = [base]

	while queue.size() > 0:
		var current: Relay = queue.pop_front()
		for neighbor in current.connected_relays:
			if is_instance_valid(neighbor) and neighbor not in visited:
				visited.append(neighbor)
				queue.append(neighbor)
				var key = str(base.get_instance_id()) + "_" + str(neighbor.get_instance_id())
				path_cache[key] = _find_path(base, neighbor)
	return visited

# -----------------------------------------
# --- Power Propagation -------------------
# -----------------------------------------
# Resets and re-applies power states from all bases
func refresh_power_states():
	for relay in relays:
		if not relay.is_base:
			relay.set_powered(false)

	for base in relays:
		if base.is_base:
			_propagate_power_from(base)

# DFS-like power propagation across connected powered relays
func _propagate_power_from(source: Relay):
	var visited: Array = []
	var stack: Array = [source]

	while stack.size() > 0:
		var current: Relay = stack.pop_back()
		if current in visited:
			continue
		visited.append(current)

		if current.is_built or current.is_base:
			current.set_powered(true)

		for neighbor in current.connected_relays:
			if is_instance_valid(neighbor) and (neighbor.is_built or neighbor.is_base):
				stack.append(neighbor)

# -----------------------------------------
# --- Timer / Packet System ---------------
# -----------------------------------------
# Sets up periodic packet emission for each base
func _setup_packet_timer(base: Relay):
	if base in base_timers:
		return

	var timer = Timer.new()
	timer.wait_time = 1.0 / packets_per_tick
	timer.autostart = true
	timer.one_shot = false
	timer.connect("timeout", Callable(self, "_on_packet_tick").bind(base))
	add_child(timer)
	base_timers[base] = timer


# Triggered each tick to propagate packets from bases with enough energy
func _on_packet_tick(base: Relay):
	if not base.is_base:
		return

	var energy_produced := 0
	var energy_spent := 0

	# --- Stage 1: Energy Production ---
	if base is Command_Center:
		var cc := base as Command_Center
		energy_produced = cc.produce_energy()

	# --- Stage 2: Building Propagation ---
	if base.has_method("has_enough_energy") and base.has_enough_energy():
		var build_packets_sent := _start_building_propagation(base)
		var cost: int = build_packets_sent * base.packet_cost
		if cost > 0 and base.has_method("spend_energy"):
			base.spend_energy()
		energy_spent += cost

	# --- Stage 3: Supply Propagation ---
	var supply_packets_sent := _start_supply_propagation(base)
	if supply_packets_sent > 0:
		var cost: int = supply_packets_sent * base.packet_cost
		if base.has_method("spend_energy"):
			base.spend_energy()
		energy_spent += cost

	# --- Rolling Average Net Balance ---
	var delta := float(energy_produced - energy_spent)
	net_balance = lerp(net_balance, delta, rolling_factor)

	# --- Emit Aggregated UI Data ---
	var global_energy := get_global_energy_pool()
	ui_update_energy.emit(global_energy, energy_produced, energy_spent)
	
#func _on_packet_tick(base: Relay):
	#if not base.is_base:
		#return
#
	#var energy_produced: int = 0
	#var energy_spent: int = 0
#
	## --- Stage 1: Energy Production ---
	#if base is Command_Center:
		#var command_center := base as Command_Center
		#energy_produced = command_center.produce_energy()
		#global_energy_pool = command_center.stored_energy  # keep global and internal in sync
		#global_energy_pool = clamp(global_energy_pool, 0, max_stored_energy)
#
	## --- Stage 2: Supply Propagation (continuous) ---
	## Supply packets do not stop when low on energy; they just slow down naturally
	#var supply_packets_sent = _start_supply_propagation(base)
	#if supply_packets_sent > 0:
		#var cost = supply_packets_sent * base.packet_cost
		#global_energy_pool = max(global_energy_pool - cost, 0)
		#energy_spent += cost
#
	## --- Stage 3: Building Propagation (only if enough energy available) ---
	#if global_energy_pool >= base.packet_cost:
		#var construction_packets_sent = _start_building_propagation(base)
		#var cost = construction_packets_sent * base.packet_cost
		#global_energy_pool = max(global_energy_pool - cost, 0)
		#energy_spent += cost
#
	## --- Emit UI Updates ---
	#ui_update_energy.emit(global_energy_pool, energy_produced, energy_spent)

			


# -----------------------------------------
# --- Incremental Packet Propagation ------
# -----------------------------------------
# Gradually sends packets to unpowered relays, cycling through targets
func _start_building_propagation(base: Relay) -> int:
	var packets_sent = 0

	if not reachable_cache.has(base):
		return 0

	var targets = reachable_cache[base]
	if targets.is_empty():
		return 0

	var start_index = last_target_index[base]

	for i in range(targets.size()):
		var idx = (start_index + i) % targets.size()
		var relay = targets[idx]

		if relay.is_powered or relay.is_scheduled:
			continue

		var key = str(base.get_instance_id()) + "_" + str(relay.get_instance_id())
		var path = path_cache.get(key, [])
		if path.size() <= 1:
			continue

		if relay.packets_on_the_way < relay.cost_to_build:
			relay.packets_on_the_way += 1
			_spawn_packet_along_path(path, DataTypes.PACKETS.BUILDING)
			packets_sent += 1

			if relay.packets_on_the_way == relay.cost_to_build:
				relay.is_scheduled = true

			last_target_index[base] = (idx + 1) % targets.size()
			break

	return packets_sent


# --- Continuous Supply Packets ---
# Gradually sends packets from a base to powered relays to simulate ongoing energy supply
func _start_supply_propagation(base: Relay) -> int:
	var packets_sent = 0
	if not reachable_cache.has(base):
		return 0

	for relay in reachable_cache[base]:
		if relay == base:
			continue

		if relay.is_built and relay.is_powered and relay.cost_to_supply > 0:
			if relay.packets_on_the_way < relay.cost_to_supply:
				var key = str(base.get_instance_id()) + "_" + str(relay.get_instance_id())
				if not path_cache.has(key):
					continue

				var path = path_cache[key]
				if path.size() <= 1:
					continue

				relay.packets_on_the_way += 1
				_spawn_packet_along_path(path, DataTypes.PACKETS.ENERGY)
				packets_sent += 1

	return packets_sent



# -----------------------------------------
# --- Packet Logic ------------------------
# -----------------------------------------
# Spawns an energy packet that travels along a path of relays
func _spawn_packet_along_path(path: Array[Relay], packet_type: DataTypes.PACKETS):
	var packet = energy_packet_scene.instantiate()
	add_child(packet)
	packet.path = path
	packet.packet_type = packet_type
	packet.speed = energy_packet_speed
	packet.global_position = path[0].global_position
	packet.packet_arrived.connect(_on_packet_arrived)

# Called when a packet reaches its target relay
func _on_packet_arrived(target_relay: Relay, packet_type: DataTypes.PACKETS):
	if is_instance_valid(target_relay):
		target_relay.receive_packet(packet_type)


# -----------------------------------------
# --- Pathfinding -------------------------
# -----------------------------------------
# BFS shortest path search between two relays with typed return
func _find_path(start: Relay, goal: Relay) -> Array[Relay]:
	var queue: Array = [[start]]
	var visited: Array[Relay] = [start]

	while queue.size() > 0:
		var path: Array = queue.pop_front()
		var current: Relay = path[-1]

		if current == goal:
			# Return a properly typed copy of the path
			var typed_path: Array[Relay] = []
			for node in path:
				typed_path.append(node as Relay)
			return typed_path

		for neighbor in current.connected_relays:
			if is_instance_valid(neighbor) and neighbor not in visited:
				visited.append(neighbor)
				var new_path = path.duplicate()
				new_path.append(neighbor)
				queue.append(new_path)

	# Return an empty typed array if no path found
	return []

# -----------------------------------------
# --- Energy Tracking ---------------------
# -----------------------------------------

# Derived from all command centers
func get_global_energy_pool() -> int:
	var total := 0
	for relay in relays:
		if relay is Command_Center:
			total += relay.stored_energy
	return total
