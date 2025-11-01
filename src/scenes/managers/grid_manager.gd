# =========================================
# GridManager.gd
# =========================================
class_name GridManager extends Node
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
# --- Signals -----------------------------
# -----------------------------------------
signal ui_update_packets(pkt_stored: float, max_pkt_capacity: float , pkt_produced: float, pkt_consumed: float, net_balance: float)
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready():
	add_to_group("grid_manager")
	_rebuild_all_connections()

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
		new_building.update_packets.connect(_on_cc_update_packets)

	_refresh_network_caches()
	_update_network_integrity()


func unregister_relay(building: Building):
	if building not in registered_buildings:
		return

	# Clean up any packets that were using the destroyed relay
	for packet in get_tree().get_nodes_in_group("packets"):
		if packet is Packet and building in packet.path:
			packet._cleanup_packet()

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
	var range_a = GlobalData.get_connection_range(type_a)
	var range_b = GlobalData.get_connection_range(type_b)
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
	var powered_buildings := {}

	# Pass 1: Find all powered buildings by traversing from Command Centers
	for building in registered_buildings:
		if building is Command_Center:
			var queue := [building]
			var visited_in_pass1 := {building: true}
			powered_buildings[building] = true

			while queue.size() > 0:
				var current = queue.pop_front()
				for neighbor in current.connected_buildings:
					if is_instance_valid(neighbor) and neighbor.is_built and not visited_in_pass1.has(neighbor):
						visited_in_pass1[neighbor] = true
						powered_buildings[neighbor] = true
						queue.append(neighbor)

	# Pass 2: Set power state for all buildings and update visuals
	var powered_map := {}
	for building in registered_buildings:
		var is_powered = powered_buildings.has(building)
		building.set_powered_state(is_powered)
		powered_map[building] = is_powered
		
		# Reset packets in flight if building is isolated
		if not is_powered:
			building.reset_packets_in_flight()

	# Update connection visuals
	for c in connections:
		if not is_instance_valid(c.connection_line):
			continue
		var a_powered = powered_map.get(c.relay_a, false)
		var b_powered = powered_map.get(c.relay_b, false)
		c.connection_line.default_color = Color(0.3, 0.9, 1.0) if (a_powered or b_powered) else Color(1, 0.3, 0.3)

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

# -----------------------------------------
# --- Signals Handling --------------------
# -----------------------------------------
# Called when a registered building is built
func _on_building_built() -> void:
	_refresh_network_caches()
	_update_network_integrity()

# Called when cc finishes timer tick calculations and updates packets values
func _on_cc_update_packets(pkt_stored: float, max_pkt_capacity: float , pkt_produced: float, pkt_consumed: float, net_balance: float) -> void:
	ui_update_packets.emit(pkt_stored, max_pkt_capacity, pkt_produced, pkt_consumed, net_balance)
