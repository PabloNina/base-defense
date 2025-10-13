# =========================================
# NetworkManager.gd
# =========================================
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
signal ui_update_energy(current_energy: int, current_produced: int, current_spent: int)

var global_energy_pool: int = 100           # total energy stored
var max_stored_energy: int = 200
var net_balance: float = 0.0
var rolling_factor := 0.1                   # smoothing factor for net energy balance

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready():
	add_to_group("network_manager")
	initialize_network()

# -----------------------------------------
# --- Relay Registration ------------------
# -----------------------------------------
func register_relay(relay: Relay):
	if relay in relays:
		return
	relays.append(relay)
	_update_connections_for(relay)

	if relay.is_base:
		relay.set_powered(true)
		_setup_packet_timer(relay)

	_refresh_network_caches()
	_update_network_integrity()

	if relay.is_built:
		relay.set_powered(true)
		relay._update_power_visual()

func unregister_relay(relay: Relay):
	if relay not in relays:
		return

	# Remove all packets referencing this relay
	for packet in get_tree().get_nodes_in_group("packets"):
		if packet is Packet and relay in packet.path:
			# Only decrement in _cleanup_packet, prevent double-count
			packet.queue_free()

	# Remove relay from network
	relays.erase(relay)
	_clear_connections_for(relay)
	for other in relays:
		other.connected_relays.erase(relay)

	# Remove timers
	if base_timers.has(relay):
		base_timers[relay].queue_free()
		base_timers.erase(relay)

	# Rebuild network caches and connections
	_update_network_integrity()
	_refresh_network_caches()
	rebuild_all_connections()  # ensure paths are valid after removal

# -----------------------------------------
# --- Network Construction ----------------
# -----------------------------------------
func initialize_network():
	rebuild_all_connections()

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

func _update_connections_for(new_relay: Relay):
	for relay in relays:
		if relay == new_relay:
			continue
		if _are_relays_in_range(relay, new_relay):
			_connect_relays(relay, new_relay)

func _are_relays_in_range(a: Relay, b: Relay) -> bool:
	if a.network_only and b.network_only:
		return false

	var key = str(a.get_instance_id()) + "_" + str(b.get_instance_id())
	if distance_cache.has(key):
		return distance_cache[key] <= min(a.connection_range, b.connection_range)

	var dist = a.global_position.distance_to(b.global_position)
	distance_cache[key] = dist
	return dist <= min(a.connection_range, b.connection_range)

func _connect_relays(a: Relay, b: Relay):
	a.connect_to(b)
	b.connect_to(a)
	if not _connection_exists(a, b):
		_create_connection_line(a, b)

func _connection_exists(a: Relay, b: Relay) -> bool:
	for c in connections:
		if (c.relay_a == a and c.relay_b == b) or (c.relay_a == b and c.relay_b == a):
			return true
	return false

func _clear_connections_for(relay: Relay):
	for c in connections:
		if c.relay_a == relay or c.relay_b == relay:
			if is_instance_valid(c.connection_line):
				c.connection_line.queue_free()
	connections = connections.filter(func(c): return c.relay_a != relay and c.relay_b != relay)

func _clear_all_connections():
	for c in connections:
		if is_instance_valid(c.connection_line):
			c.connection_line.queue_free()
	connections.clear()

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
func _refresh_network_caches():
	path_cache.clear()
	distance_cache.clear()
	reachable_cache.clear()
	last_target_index.clear()

	for base in relays:
		if base.is_base:
			reachable_cache[base] = _get_reachable_relays(base)
			last_target_index[base] = 0

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

func are_connected(a: Relay, b: Relay) -> bool:
	if not reachable_cache.has(a):
		return false
	return b in reachable_cache[a]

# -----------------------------------------
# --- Network Integrity -------------------
# -----------------------------------------
func _update_network_integrity():
	var visited := {}
	var powered_map := {}

	for relay in relays:
		if relay in visited:
			continue

		var cluster := []
		var queue := [relay]
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

		for r in cluster:
			r.set_powered(cluster_has_cc)
			powered_map[r] = cluster_has_cc

	for c in connections:
		if not is_instance_valid(c.connection_line):
			continue
		var a_powered = powered_map.get(c.relay_a, false)
		var b_powered = powered_map.get(c.relay_b, false)
		c.connection_line.default_color = Color(0.3, 0.9, 1.0) if (a_powered and b_powered) else Color(1, 0.3, 0.3)

# -----------------------------------------
# --- Timer / Packet System ---------------
# -----------------------------------------
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

# -----------------------------------------
# --- Packet Tick -------------------------
# -----------------------------------------
func _on_packet_tick(base: Relay):
	if not base.is_base:
		return

	var energy_produced := 0
	var energy_spent := 0
	var packets_allowed := packets_per_tick

	# --- Stage 0: Generator bonuses ---
	for generator in relays:
		if generator is EnergyGenerator and generator.is_powered and generator.is_built:
			generator.provide_energy_bonus()

	# --- Stage 1: Command Center produces energy ---
	if base is Command_Center:
		var cc := base as Command_Center
		energy_produced = cc.produce_energy()
		packets_allowed = _compute_send_quota(cc)

	var quota := packets_allowed

	# --- Stage 2: Generic packet propagation ---
	var packet_types := [
		DataTypes.PACKETS.BUILDING,
		DataTypes.PACKETS.ENERGY,
		DataTypes.PACKETS.AMMO,
		DataTypes.PACKETS.ORE,
		DataTypes.PACKETS.TECH
	]

	for pkt_type in packet_types:
		if quota <= 0:
			break
		var sent := _start_packet_propagation(base, quota, pkt_type)
		if sent > 0 and base is Command_Center:
			var cc := base as Command_Center
			cc.spend_energy(pkt_type, sent)
			energy_spent += sent * cc.get_packet_cost(pkt_type)
			quota -= sent

	# --- Stage 3: Update rolling net balance ---
	net_balance = lerp(net_balance, float(energy_produced - energy_spent), rolling_factor)

	# --- Stage 4: Update UI ---
	ui_update_energy.emit(get_global_energy_pool(), energy_produced, energy_spent)

#func _on_packet_tick(base: Relay):
	#if not base.is_base:
		#return
#
	#var energy_produced := 0
	#var energy_spent := 0
	#var packets_allowed := packets_per_tick
#
	## Generator bonuses
	#for generator in relays:
		#if generator is EnergyGenerator and generator.is_powered and generator.is_built:
			#generator.provide_energy_bonus()
#
	## Command Center produces energy
	#if base is Command_Center:
		#var cc := base as Command_Center
		#energy_produced = cc.produce_energy()
		#packets_allowed = _compute_send_quota(cc)
#
	#var quota := packets_allowed
#
	#if quota > 0:
		#var build_sent := _start_building_propagation(base, quota)
		#if build_sent > 0 and base is Command_Center:
			#var cc := base as Command_Center
			#cc.spend_energy(DataTypes.PACKETS.BUILDING, build_sent)
			#energy_spent += build_sent * cc.get_packet_cost(DataTypes.PACKETS.BUILDING)
			#quota -= build_sent
#
	#if quota > 0:
		#var supply_sent := _start_supply_propagation(base, quota)
		#if supply_sent > 0 and base is Command_Center:
			#var cc := base as Command_Center
			#cc.spend_energy(DataTypes.PACKETS.ENERGY, supply_sent)
			#energy_spent += supply_sent * cc.get_packet_cost(DataTypes.PACKETS.ENERGY)
			#quota -= supply_sent
#
	#net_balance = lerp(net_balance, float(energy_produced - energy_spent), rolling_factor)
	#ui_update_energy.emit(get_global_energy_pool(), energy_produced, energy_spent)

func _compute_send_quota(cc: Command_Center) -> int:
	var energy_ratio := cc.available_ratio()
	var throttle_ratio := sqrt(energy_ratio)

	var max_affordable := int(floor(float(cc.stored_energy) / float(cc.get_packet_cost(DataTypes.PACKETS.ENERGY))))
	var desired_packets := int(floor(float(packets_per_tick) * throttle_ratio))

	return max(0, min(desired_packets, max_affordable))

# -----------------------------------------
# --- Packet Propagation ------------------
# -----------------------------------------
func _start_packet_propagation(base: Relay, quota: int, packet_type: DataTypes.PACKETS) -> int:
	var packets_sent := 0
	if quota <= 0 or not reachable_cache.has(base):
		return 0

	var targets := []
	for relay in reachable_cache[base]:
		if relay == base or not is_instance_valid(relay):
			continue
		# Determine if relay actually needs this type of packet
		match packet_type:
			DataTypes.PACKETS.BUILDING:
				if not relay.needs_packet(DataTypes.PACKETS.BUILDING):
					continue
				if relay.packets_on_the_way >= relay.cost_to_build:
					continue
			DataTypes.PACKETS.ENERGY:
				if not relay.needs_packet(DataTypes.PACKETS.ENERGY):
					continue
				if relay.cost_to_supply <= 0 or relay.packets_on_the_way >= relay.cost_to_supply:
					continue
			DataTypes.PACKETS.AMMO:
				if not relay.needs_packet(DataTypes.PACKETS.AMMO):
					continue
				# Add a max on-the-way check if needed: relay.packets_on_the_way >= relay.cost_to_ammo
			DataTypes.PACKETS.ORE:
				if not relay.needs_packet(DataTypes.PACKETS.ORE):
					continue
			DataTypes.PACKETS.TECH:
				if not relay.needs_packet(DataTypes.PACKETS.TECH):
					continue
			_:
				continue
		targets.append(relay)

	if targets.is_empty():
		return 0

	var index = last_target_index.get(base, 0)
	var n = targets.size()

	for i in range(n):
		if packets_sent >= quota:
			break
		var relay = targets[index % n]
		index += 1

		var key = str(base.get_instance_id()) + "_" + str(relay.get_instance_id())
		if not path_cache.has(key):
			continue
		var path = path_cache[key]
		if path.size() <= 1 or path.any(func(r): return not is_instance_valid(r)):
			continue
		if not are_connected(path[0], path[-1]):
			continue

		relay.packets_on_the_way += 1
		_spawn_packet_along_path(path, packet_type)
		packets_sent += 1

		# Special flags for building
		if packet_type == DataTypes.PACKETS.BUILDING and relay.packets_on_the_way >= relay.cost_to_build:
			relay.is_scheduled_to_build = true

	last_target_index[base] = index % n
	return packets_sent

#func _start_building_propagation(base: Relay, quota: int) -> int:
	#var packets_sent := 0
	#if quota <= 0 or not reachable_cache.has(base):
		#return 0
#
	## Step 0: use accurate in-flight count, no full resync
	#for relay in reachable_cache[base]:
		#if relay == base or not is_instance_valid(relay):
			#continue
		#relay.packets_on_the_way = max(0, relay.packets_on_the_way)
#
	## Step 1: Gather targets
	#var targets := []
	#for relay in reachable_cache[base]:
		#if relay == base or not is_instance_valid(relay):
			#continue
		#if not relay.needs_packet(DataTypes.PACKETS.BUILDING):
			#continue
		#if relay.packets_on_the_way >= relay.cost_to_build:
			#continue
		#targets.append(relay)
	#if targets.is_empty():
		#return 0
#
	## Step 2: Sort closest first
	#targets.sort_custom(func(a, b):
		#var key_a = str(base.get_instance_id()) + "_" + str(a.get_instance_id())
		#var key_b = str(base.get_instance_id()) + "_" + str(b.get_instance_id())
		#return distance_cache.get(key_a, INF) < distance_cache.get(key_b, INF)
	#)
#
	## Step 3: Send packets
	#for relay in targets:
		#if packets_sent >= quota:
			#break
		#var key = str(base.get_instance_id()) + "_" + str(relay.get_instance_id())
		#if not path_cache.has(key):
			#continue
		#var path = path_cache[key]
		#if path.size() <= 1 or path.any(func(r): return not is_instance_valid(r)):
			#continue
		## Only spawn if path is truly connected
		#if not are_connected(path[0], path[-1]):
			#continue
		#relay.packets_on_the_way += 1
		#_spawn_packet_along_path(path, DataTypes.PACKETS.BUILDING)
		#packets_sent += 1
		#if relay.packets_on_the_way >= relay.cost_to_build:
			#relay.is_scheduled_to_build = true
#
	#return packets_sent

# -----------------------------------------
# --- Packet spawning ---------------------
# -----------------------------------------
func _spawn_packet_along_path(path: Array[Relay], packet_type: DataTypes.PACKETS):
	# Safety checks
	if path.size() < 2:
		return
	if path.any(func(r): return not is_instance_valid(r)):
		return
	if not are_connected(path[0], path[-1]):
		return

	# Instantiate packet
	var packet = energy_packet_scene.instantiate()
	add_child(packet)

	#packet.path = path.duplicate()
	packet.path = path
	packet.packet_type = packet_type
	packet.speed = energy_packet_speed
	packet.global_position = path[0].global_position

	# Connect the arrival signal
	packet.packet_arrived.connect(_on_packet_arrived)
	packet.add_to_group("packets")  # ensures cleanup on relay destruction

#func _spawn_packet_along_path(path: Array[Relay], packet_type: DataTypes.PACKETS):
	## Only spawn if path is valid and connected
	#if path.any(func(r): return not is_instance_valid(r)):
		#return
	#if not are_connected(path[0], path[-1]):
		#return
#
	#var packet = energy_packet_scene.instantiate()
	#add_child(packet)
	#packet.path = path
	#packet.packet_type = packet_type
	#packet.speed = energy_packet_speed
	#packet.global_position = path[0].global_position
	#packet.packet_arrived.connect(_on_packet_arrived)
	#packet.add_to_group("packets")  # ensures we can find it on relay destruction

func _on_packet_arrived(target_relay: Relay, packet_type: DataTypes.PACKETS):
	# Safety check: ensure relay is still valid
	if not is_instance_valid(target_relay):
		return
	# Decrement in-flight packet count safely
	target_relay.packets_on_the_way = max(0, target_relay.packets_on_the_way - 1)
	# Relay processes the packet
	target_relay.receive_packet(packet_type)

# -----------------------------------------
# --- Pathfinding -------------------------
# -----------------------------------------
func _find_path(start: Relay, goal: Relay) -> Array[Relay]:
	var queue: Array = [[start]]
	var visited: Array[Relay] = [start]

	while queue.size() > 0:
		var path: Array = queue.pop_front()
		var current: Relay = path[-1]
		if current == goal:
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
	return []
#func _find_path(start: Relay, goal: Relay) -> Array[Relay]:
	#var queue: Array = [[start]]
	#var visited: Array[Relay] = [start]
#
	#while queue.size() > 0:
		#var path: Array = queue.pop_front()
		#var current: Relay = path[-1]
#
		#if current == goal:
			#var typed_path: Array[Relay] = []
			#for node in path:
				#typed_path.append(node as Relay)
			#return typed_path
#
		#for neighbor in current.connected_relays:
			#if is_instance_valid(neighbor) and neighbor not in visited:
				#visited.append(neighbor)
				#var new_path = path.duplicate()
				#new_path.append(neighbor)
				#queue.append(new_path)
#
	#return []
# -----------------------------------------
# --- Energy Tracking ---------------------
# -----------------------------------------
func get_global_energy_pool() -> int:
	var total := 0
	for relay in relays:
		if relay is Command_Center:
			total += relay.stored_energy
	return total



#class_name NetworkManager
#extends Node
#
## -----------------------------------------
## --- Editor Exports ----------------------
## -----------------------------------------
#@export var energy_packet_scene: PackedScene
#@export var energy_packet_speed: float = 150.0
#@export var packets_per_tick: int = 4
#
## -----------------------------------------
## --- Runtime Data ------------------------
## -----------------------------------------
#var relays: Array[Relay] = []               # All active relays in the network
#var connections: Array = []                 # Connection visuals between relays
#var base_timers: Dictionary = {}            # { base_relay: Timer } handles packet spawning timers
#
## -----------------------------------------
## --- Cached Data for Optimization --------
## -----------------------------------------
#var path_cache: Dictionary = {}             # { "aID_bID": [Relay path] } cached relay paths
#var distance_cache: Dictionary = {}         # { "aID_bID": float } cached relay distances
#var reachable_cache: Dictionary = {}        # { base: [reachable_relays] } which relays a base can reach
#var last_target_index: Dictionary = {}      # { base: int } tracks incremental target selection
#
## -----------------------------------------
## --- Energy Tracking ---------------------
## -----------------------------------------
#signal ui_update_energy(current_energy: int, current_produced: int, current_spent: int)
#
#var global_energy_pool: int = 100           # total energy stored
#var max_stored_energy: int = 200
#var net_balance: float = 0.0
#var rolling_factor := 0.1                   # smoothing factor for net energy balance
#
## -----------------------------------------
## --- Engine Callbacks --------------------
## -----------------------------------------
#func _ready():
	#add_to_group("network_manager")
	#initialize_network()
#
## -----------------------------------------
## --- Relay Registration ------------------
## -----------------------------------------
#func register_relay(relay: Relay):
	#if relay in relays:
		#return
#
	#relays.append(relay)
	#_update_connections_for(relay)
#
	## Base relays start powered and spawn packets
	#if relay.is_base:
		#relay.set_powered(true)
		#_setup_packet_timer(relay)
#
	## Refresh caches and visuals
	#_refresh_network_caches()
	#_update_network_integrity()  # cluster + power + connection color update
#
	## Ensure newly built relays update power visuals
	#if relay.is_built:
		#relay.set_powered(true)
		#relay._update_power_visual()
#
#
#func unregister_relay(relay: Relay):
	#if relay not in relays:
		#return
	#
	## Clean up all packets that reference this relay anywhere in their path
	#for packet in get_tree().get_nodes_in_group("packets"):
		#if packet is Packet and packet.path.size() > 0:
			#if relay in packet.path:
				## Decrement packets_on_the_way for the packet's target relay if valid
				#if is_instance_valid(packet.path[-1]):
					#packet.path[-1].packets_on_the_way = max(0, packet.path[-1].packets_on_the_way - 1)
				#packet.queue_free()  # remove the packet safely
	#
	## Remove relay from list
	#relays.erase(relay)
	#
	## Remove all visual connections
	#_clear_connections_for(relay)
#
	## Remove relay from others' connections
	#for other in relays:
		#other.connected_relays.erase(relay)
#
	## Remove associated timers
	#if base_timers.has(relay):
		#var t = base_timers[relay]
		#t.queue_free()
		#base_timers.erase(relay)
#
	## Refresh network integrity and caches
	#_update_network_integrity()
	#_refresh_network_caches()
#
#
## -----------------------------------------
## --- Network Construction ----------------
## -----------------------------------------
#func initialize_network():
	#rebuild_all_connections()
#
#
#func rebuild_all_connections():
	#_clear_all_connections()
#
	## Clear previous connections
	#for relay in relays:
		#relay.connected_relays.clear()
#
	## Reconnect relays within range
	#for i in range(relays.size()):
		#for j in range(i + 1, relays.size()):
			#var a = relays[i]
			#var b = relays[j]
			#if _are_relays_in_range(a, b):
				#_connect_relays(a, b)
#
	#_refresh_network_caches()
#
#
## Update connections for a newly registered relay
#func _update_connections_for(new_relay: Relay):
	#for relay in relays:
		#if relay == new_relay:
			#continue
		#if _are_relays_in_range(relay, new_relay):
			#_connect_relays(relay, new_relay)
#
#
## Check if two relays can connect based on distance and type
#func _are_relays_in_range(a: Relay, b: Relay) -> bool:
	## Prevent certain building types from connecting
	#if a.network_only and b.network_only:
		#return false
#
	#var key = str(a.get_instance_id()) + "_" + str(b.get_instance_id())
	#if distance_cache.has(key):
		#return distance_cache[key] <= min(a.connection_range, b.connection_range)
#
	#var dist = a.global_position.distance_to(b.global_position)
	#distance_cache[key] = dist
	#return dist <= min(a.connection_range, b.connection_range)
#
#
## Bidirectional connection between relays + optional visual
#func _connect_relays(a: Relay, b: Relay):
	#a.connect_to(b)
	#b.connect_to(a)
	#if not _connection_exists(a, b):
		#_create_connection_line(a, b)
#
#
## Check if a visual line already exists
#func _connection_exists(a: Relay, b: Relay) -> bool:
	#for c in connections:
		#if (c.relay_a == a and c.relay_b == b) or (c.relay_a == b and c.relay_b == a):
			#return true
	#return false
#
#
## Remove visuals involving a relay
#func _clear_connections_for(relay: Relay):
	#for c in connections:
		#if c.relay_a == relay or c.relay_b == relay:
			#if is_instance_valid(c.connection_line):
				#c.connection_line.queue_free()
	#connections = connections.filter(func(c): return c.relay_a != relay and c.relay_b != relay)
#
#
## Remove all connection visuals
#func _clear_all_connections():
	#for c in connections:
		#if is_instance_valid(c.connection_line):
			#c.connection_line.queue_free()
	#connections.clear()
#
#
## Create a visible connection line
#func _create_connection_line(a: Relay, b: Relay):
	#var line := Line2D.new()
	#line.width = 1
	#line.default_color = Color(0.3, 0.9, 1.0)  # powered color by default
	#line.points = [a.global_position, b.global_position]
	#add_child(line)
	#connections.append({"relay_a": a, "relay_b": b, "connection_line": line})
#
#
## -----------------------------------------
## --- Network Cache -----------------------
## -----------------------------------------
#func _refresh_network_caches():
	#path_cache.clear()
	#distance_cache.clear()
	#reachable_cache.clear()
	#last_target_index.clear()
#
	## Precompute reachable relays for each base
	#for base in relays:
		#if base.is_base:
			#reachable_cache[base] = _get_reachable_relays(base)
			#last_target_index[base] = 0
#
#
## BFS for reachable relays from a base, caching shortest paths
#func _get_reachable_relays(base: Relay) -> Array:
	#var visited: Array = [base]
	#var queue: Array = [base]
#
	#while queue.size() > 0:
		#var current: Relay = queue.pop_front()
		#for neighbor in current.connected_relays:
			#if is_instance_valid(neighbor) and neighbor not in visited:
				#visited.append(neighbor)
				#queue.append(neighbor)
				#var key = str(base.get_instance_id()) + "_" + str(neighbor.get_instance_id())
				#path_cache[key] = _find_path(base, neighbor)
	#return visited
#
#
## Helper: Are two relays reachable?
#func are_connected(a: Relay, b: Relay) -> bool:
	#if not reachable_cache.has(a):
		#return false
	#return b in reachable_cache[a]
#
#
## -----------------------------------------
## --- Network Integrity -------------------
## -----------------------------------------
## BFS clusters, assign power, update connection visuals
#func _update_network_integrity():
	#var visited := {}
	#var powered_map := {}  # relay -> powered bool
#
	## --- Step 1: BFS clusters ---
	#for relay in relays:
		#if relay in visited:
			#continue
#
		#var cluster := []
		#var queue := [relay]
		#var cluster_has_cc := false  # Contains a Command_Center?
#
		#while queue.size() > 0:
			#var r = queue.pop_front()
			#if r in visited:
				#continue
			#visited[r] = true
			#cluster.append(r)
#
			#if r is Command_Center:
				#cluster_has_cc = true
#
			#for n in r.connected_relays:
				#if is_instance_valid(n) and n not in visited:
					#queue.append(n)
#
		## Assign power state to the cluster
		#for r in cluster:
			#r.set_powered(cluster_has_cc)
			#powered_map[r] = cluster_has_cc
#
	## --- Step 2: Update connection visuals ---
	#for c in connections:
		#if not is_instance_valid(c.connection_line):
			#continue
#
		#var a_powered = powered_map.get(c.relay_a, false)
		#var b_powered = powered_map.get(c.relay_b, false)
		#c.connection_line.default_color = Color(0.3, 0.9, 1.0) if (a_powered and b_powered) else Color(1, 0.3, 0.3)
#
#
## -----------------------------------------
## --- Timer / Packet System ---------------
## -----------------------------------------
#func _setup_packet_timer(base: Relay):
	#if base in base_timers:
		#return
#
	#var timer = Timer.new()
	#timer.wait_time = 1.0 / packets_per_tick
	#timer.autostart = true
	#timer.one_shot = false
	#timer.connect("timeout", Callable(self, "_on_packet_tick").bind(base))
	#add_child(timer)
	#base_timers[base] = timer
#
#
## -----------------------------------------
## --- Packet Tick -------------------------
## -----------------------------------------
#func _on_packet_tick(base: Relay):
	#if not base.is_base:
		#return
#
	#var energy_produced := 0
	#var energy_spent := 0
	#var packets_allowed := packets_per_tick
#
	## --- Stage 0: Generator bonuses ---
	#for generator in relays:
		#if generator is EnergyGenerator and generator.is_powered and generator.is_built:
			#generator.provide_energy_bonus()
#
	## --- Stage 1: Command Center produces energy ---
	#if base is Command_Center:
		#var cc := base as Command_Center
		#energy_produced = cc.produce_energy()
		#packets_allowed = _compute_send_quota(cc)
#
	#var quota := packets_allowed
#
	## --- Stage 2: Building packets ---
	#if quota > 0:
		#var build_sent := _start_building_propagation(base, quota)
		#if build_sent > 0 and base is Command_Center:
			#var cc := base as Command_Center
			#cc.spend_energy(DataTypes.PACKETS.BUILDING, build_sent)
			#energy_spent += build_sent * cc.get_packet_cost(DataTypes.PACKETS.BUILDING)
			#quota -= build_sent
#
	## --- Stage 3: Supply packets ---
	#if quota > 0:
		#var supply_sent := _start_supply_propagation(base, quota)
		#if supply_sent > 0 and base is Command_Center:
			#var cc := base as Command_Center
			#cc.spend_energy(DataTypes.PACKETS.ENERGY, supply_sent)
			#energy_spent += supply_sent * cc.get_packet_cost(DataTypes.PACKETS.ENERGY)
			#quota -= supply_sent
#
	## --- Stage 4: Update rolling net balance ---
	#net_balance = lerp(net_balance, float(energy_produced - energy_spent), rolling_factor)
#
	## Notify UI
	#ui_update_energy.emit(get_global_energy_pool(), energy_produced, energy_spent)
#
#
#func _compute_send_quota(cc: Command_Center) -> int:
	#var energy_ratio := cc.available_ratio()
	#var throttle_ratio := sqrt(energy_ratio)
#
	#var max_affordable := int(floor(float(cc.stored_energy) / float(cc.get_packet_cost(DataTypes.PACKETS.ENERGY))))
	#var desired_packets := int(floor(float(packets_per_tick) * throttle_ratio))
#
	#return max(0, min(desired_packets, max_affordable))
#
#
## -----------------------------------------
## --- Packet Propagation ------------------
## -----------------------------------------
#func _start_building_propagation(base: Relay, quota: int) -> int:
	#var packets_sent := 0
	#if quota <= 0 or not reachable_cache.has(base):
		#return 0
#
	## -------------------------------
	## Step 0: Resynchronize packets_on_the_way
	## -------------------------------
	#for relay in reachable_cache[base]:
		#if relay == base or not is_instance_valid(relay):
			#continue
		#relay.packets_on_the_way = 0  # reset
	#for packet in get_tree().get_nodes_in_group("packets"):
		#if packet is Packet and packet.packet_type == DataTypes.PACKETS.BUILDING:
			#for r in packet.path:
				#if is_instance_valid(r):
					#r.packets_on_the_way += 1
#
	## -------------------------------
	## Step 1: Gather targets
	## -------------------------------
	#var targets := []
	#for relay in reachable_cache[base]:
		#if relay == base or not is_instance_valid(relay):
			#continue
		#if not relay.needs_packet(DataTypes.PACKETS.BUILDING):
			#continue
		#if relay.packets_on_the_way >= relay.cost_to_build:
			#continue
		#targets.append(relay)
#
	#if targets.is_empty():
		#return 0
#
	## -------------------------------
	## Step 2: Sort closest first
	## -------------------------------
	#targets.sort_custom(func(a, b):
		#var key_a = str(base.get_instance_id()) + "_" + str(a.get_instance_id())
		#var key_b = str(base.get_instance_id()) + "_" + str(b.get_instance_id())
		#return distance_cache.get(key_a, INF) < distance_cache.get(key_b, INF)
	#)
#
	## -------------------------------
	## Step 3: Send packets
	## -------------------------------
	#for relay in targets:
		#if packets_sent >= quota:
			#break
#
		#var key = str(base.get_instance_id()) + "_" + str(relay.get_instance_id())
		#if not path_cache.has(key):
			#continue
		#var path = path_cache[key]
		#if path.size() <= 1 or path.any(func(r): return not is_instance_valid(r)):
			#continue  # skip invalid path
#
		#relay.packets_on_the_way += 1
		#_spawn_packet_along_path(path, DataTypes.PACKETS.BUILDING)
		#packets_sent += 1
#
		#if relay.packets_on_the_way >= relay.cost_to_build:
			#relay.is_scheduled_to_build = true
#
	#return packets_sent
#
#
#func _start_supply_propagation(base: Relay, quota: int) -> int:
	#var packets_sent := 0
	#if quota <= 0 or not reachable_cache.has(base):
		#return 0
#
	## -------------------------------
	## Step 0: Resynchronize packets_on_the_way
	## -------------------------------
	#for relay in reachable_cache[base]:
		#if relay == base or not is_instance_valid(relay):
			#continue
		#relay.packets_on_the_way = 0  # reset
	#for packet in get_tree().get_nodes_in_group("packets"):
		#if packet is Packet and packet.packet_type == DataTypes.PACKETS.ENERGY:
			#for r in packet.path:
				#if is_instance_valid(r):
					#r.packets_on_the_way += 1
#
	## -------------------------------
	## Step 1: Gather targets
	## -------------------------------
	#var targets := []
	#for relay in reachable_cache[base]:
		#if relay == base or not is_instance_valid(relay):
			#continue
		#if not relay.needs_packet(DataTypes.PACKETS.ENERGY):
			#continue
		#if relay.cost_to_supply <= 0:
			#continue
		#if relay.packets_on_the_way >= relay.cost_to_supply:
			#continue
		#targets.append(relay)
#
	#if targets.is_empty():
		#return 0
#
	## -------------------------------
	## Step 2: Sort farthest first
	## -------------------------------
	#targets.sort_custom(func(a, b):
		#var key_a = str(base.get_instance_id()) + "_" + str(a.get_instance_id())
		#var key_b = str(base.get_instance_id()) + "_" + str(b.get_instance_id())
		#return distance_cache.get(key_a, 0) > distance_cache.get(key_b, 0)
	#)
#
	## -------------------------------
	## Step 3: Send packets
	## -------------------------------
	#for relay in targets:
		#if packets_sent >= quota:
			#break
#
		#var key = str(base.get_instance_id()) + "_" + str(relay.get_instance_id())
		#if not path_cache.has(key):
			#continue
		#var path = path_cache[key]
		#if path.size() <= 1 or path.any(func(r): return not is_instance_valid(r)):
			#continue  # skip invalid path
#
		#relay.packets_on_the_way += 1
		#_spawn_packet_along_path(path, DataTypes.PACKETS.ENERGY)
		#packets_sent += 1
#
	#return packets_sent
#
#
## -----------------------------------------
## --- Packet Logic ------------------------
## -----------------------------------------
#func _spawn_packet_along_path(path: Array[Relay], packet_type: DataTypes.PACKETS):
	## Skip spawn if any relay in the path is destroyed
	#if path.any(func(r): return not is_instance_valid(r)):
		#return
	#
	#var packet = energy_packet_scene.instantiate()
	#add_child(packet)
	#packet.path = path
	#packet.packet_type = packet_type
	#packet.speed = energy_packet_speed
	#packet.global_position = path[0].global_position
	#packet.packet_arrived.connect(_on_packet_arrived)
	#packet.add_to_group("packets")  # <-- ensures we can find it on relay destruction
#
#func _on_packet_arrived(target_relay: Relay, packet_type: DataTypes.PACKETS):
	## Safety check: ensure relay is still valid
	#if not is_instance_valid(target_relay):
		#return
#
	## Decrement in-flight packet count
	#target_relay.packets_on_the_way = max(0, target_relay.packets_on_the_way - 1)
#
	## Relay processes the packet normally
	#target_relay.receive_packet(packet_type)
#
#
## -----------------------------------------
## --- Pathfinding -------------------------
## -----------------------------------------
#func _find_path(start: Relay, goal: Relay) -> Array[Relay]:
	#var queue: Array = [[start]]
	#var visited: Array[Relay] = [start]
#
	#while queue.size() > 0:
		#var path: Array = queue.pop_front()
		#var current: Relay = path[-1]
#
		#if current == goal:
			#var typed_path: Array[Relay] = []
			#for node in path:
				#typed_path.append(node as Relay)
			#return typed_path
#
		#for neighbor in current.connected_relays:
			#if is_instance_valid(neighbor) and neighbor not in visited:
				#visited.append(neighbor)
				#var new_path = path.duplicate()
				#new_path.append(neighbor)
				#queue.append(new_path)
#
	#return []
#
#
## -----------------------------------------
## --- Energy Tracking ---------------------
## -----------------------------------------
#func get_global_energy_pool() -> int:
	#var total := 0
	#for relay in relays:
		#if relay is Command_Center:
			#total += relay.stored_energy
	#return total
