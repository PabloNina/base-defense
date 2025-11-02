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
var registered_buildings: Array[Building] = [] # All active buildings in the grid
var current_connections: Array[ConnectionLine] = [] # Connection visuals between buildings
# -----------------------------------------
# --- Cached Data for Optimization --------
# -----------------------------------------
var path_cache: Dictionary = {}                 # { "aID_bID": [Relay path] } cached buildings paths
var distance_cache: Dictionary = {}             # { "aID_bID": float } cached buildings distances
var reachable_from_base_cache: Dictionary = {}  # { base: [reachable_buildings] } which buildings a base can reach
var last_target_index: Dictionary = {}          # { base: int } tracks incremental target selection
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
# Registers a new building to the grid.
# This connects the building to the grid management system, updates connections to nearby buildings,
# and refreshes the grid's overall state, including power and pathfinding caches.
func register_to_grid(new_building: Building):
	if new_building in registered_buildings:
		return
	
	# Prevents connecting multiple times the same signal when moving buildings
	if not new_building.finish_building.is_connected(_on_building_built):
		new_building.finish_building.connect(_on_building_built)
	
	# Add building to grid and update connections
	registered_buildings.append(new_building)
	_update_connections_for(new_building)

	# If is CC start powered and connect signals
	if new_building is Command_Center:
		new_building.set_powered_state(true)
		new_building.update_packets.connect(_on_cc_update_packets)

	# Update grid state (order is important)
	_refresh_grid_caches() # clears all cached data Dictionaries
	_update_grid_integrity()

# Unregisters a building from the grid, typically when it's destroyed.
# This involves cleaning up any active packets targeting the building, removing it from the list of registered buildings,
# and then updating the grid caches and power states to reflect the change.
# This approach is more efficient than a full rebuild for a single building removal.
func unregister_to_grid(building: Building):
	if building not in registered_buildings:
		return

	# Clean up any packets that were using the destroyed relay
	var packet_manager = get_tree().get_first_node_in_group("packet_manager")
	if packet_manager:
		for packet in packet_manager.active_packets_container.get_children():
			if packet is Packet and building in packet.path:
				packet._cleanup_packet()

	# Remove building from grid
	registered_buildings.erase(building)
	
	# Clear connections first
	_clear_connections_for(building)
	for other in registered_buildings:
		other.connected_buildings.erase(building)

	# Update grid state (order is important)
	_refresh_grid_caches()
	_update_grid_integrity()

# -----------------------------------------
# --- Grid Construction ----------------
# -----------------------------------------
# Fully clears and rebuilds all physical connections in the grid.
# This is more expensive and is only needed after mass changes or a full reset.
# Usually you only need to call _refresh_grid_caches and _update_grid_integrity for incremental changes.
func _rebuild_all_connections():
	_clear_all_connections()
	for building in registered_buildings:
		building.connected_buildings.clear()
	# Build physical connections
	for i in range(registered_buildings.size()):
		for j in range(i + 1, registered_buildings.size()):
			var a = registered_buildings[i]
			var b = registered_buildings[j]
			if _are_buildings_in_range(a, b):
				_connect_buildings(a, b)
	# Update caches and power states after rebuilding
	_refresh_grid_caches() # clears all cached data Dictionaries
	_update_grid_integrity() 


# Connects the newly registered building to all other buildings in range.
# Called only when a building is registered (added to the grid).
# This ensures new buildings are physically connected to all valid neighbors.
func _update_connections_for(new_building: Building):
	for building in registered_buildings:
		if building == new_building:
			continue
		if _are_buildings_in_range(building, new_building):
			_connect_buildings(building, new_building)

# Checks if two buildings are within each other's connection range.
# For a connection to be possible, at least one of the buildings must be a relay.
# The result is cached to avoid repeated distance calculations.
func _are_buildings_in_range(building_a: Building, building_b: Building) -> bool:
	if not building_a.is_relay and not building_b.is_relay:
		return false

	var key = str(building_a.get_instance_id()) + "_" + str(building_b.get_instance_id())
	if distance_cache.has(key):
		return distance_cache[key] <= min(building_a.connection_range, building_b.connection_range)

	var dist = building_a.global_position.distance_to(building_b.global_position)
	distance_cache[key] = dist
	return dist <= min(building_a.connection_range, building_b.connection_range)
	
# Helper for packet manager
# Checks if building is connected to the grid
func are_connected(base: Command_Center, building: Building) -> bool:
	if not reachable_from_base_cache.has(base):
		return false
	return building in reachable_from_base_cache[base]
	
# Public static-like helper for placement preview: 
# checks if two buildings (or a ghost) would connect, given their types, positions, and is_relay flags.
static func can_buildings_connect(type_a: int, pos_a: Vector2, is_relay_a: bool, type_b: int, pos_b: Vector2, is_relay_b: bool) -> bool:
	if not is_relay_a and not is_relay_b:
		return false
	var range_a = GlobalData.get_connection_range(type_a)
	var range_b = GlobalData.get_connection_range(type_b)
	var dist = pos_a.distance_to(pos_b)
	return dist <= min(range_a, range_b)

# Establishes a bidirectional connection between two buildings and creates the visual line for it.
func _connect_buildings(building_a: Building, building_b: Building):
	building_a.connect_to(building_b)
	building_b.connect_to(building_a)
	if not _connection_exists(building_a, building_b):
		var ConnectionLineScene = load("res://src/scenes/objects/connection_lines/connection_line.tscn")
		var connection_line: ConnectionLine = ConnectionLineScene.instantiate()
		lines_2d_container.add_child(connection_line)
		connection_line.setup_connection(building_a, building_b)
		current_connections.append(connection_line)

# Checks if a visual connection line already exists between two buildings.
func _connection_exists(building_a: Building, building_b: Building) -> bool:
	for connection in current_connections:
		if (connection.building_a == building_a and connection.building_b == building_b) or (connection.building_a == building_b and connection.building_b == building_a):
			return true
	return false

# used only in unregister
func _clear_connections_for(building: Building):
	var remaining_connections: Array[ConnectionLine] = []
	for connection in current_connections:
		if connection.building_a == building or connection.building_b == building:
			connection.destroy()
		else:
			remaining_connections.append(connection)
	current_connections = remaining_connections

# Removes all connection visuals and clears the list of current connections.
func _clear_all_connections():
	for connection in current_connections:
		connection.destroy()
	current_connections.clear()

# -----------------------------------------
# --- Grid Cache -----------------------
# -----------------------------------------
# Updates all pathfinding, reachability, and distance caches for the grid.
# Call this after adding/removing buildings or when a relay is built/destroyed.
func _refresh_grid_caches():
	path_cache.clear()
	distance_cache.clear()
	reachable_from_base_cache.clear()
	last_target_index.clear()

	for base in registered_buildings:
		if base is Command_Center:
			reachable_from_base_cache[base] = _get_reachable_buildings_from_base(base)
			last_target_index[base] = 0

# Performs a breadth-first search starting from a base building to find all reachable buildings.
# This function simultaneously calculates the shortest path (in terms of number of hops) to each reachable building
# and caches these paths for later use by the PacketManager.
# The traversal for pathfinding only considers built buildings as intermediate nodes.
# Unbuilt buildings can only be the final node in a path, making them reachable for construction packets.
func _get_reachable_buildings_from_base(base: Building) -> Array:
	var visited: Array = [base]
	# The queue stores an array of paths. Each path is an array of buildings.
	var queue: Array = [[base]] 

	while queue.size() > 0:
		var path: Array = queue.pop_front()
		var current: Building = path[-1]

		for neighbor in current.connected_buildings:
			if not is_instance_valid(neighbor):
				continue

			if neighbor not in visited:
				visited.append(neighbor)
				var new_path = path.duplicate()
				new_path.append(neighbor)

				# Cache the path from the base to the neighbor.
				var key = str(base.get_instance_id()) + "_" + str(neighbor.get_instance_id())
				
				var typed_path: Array[Building] = []
				for node in new_path:
					typed_path.append(node as Building)
				path_cache[key] = typed_path

				# Only built buildings can be intermediate nodes in a path, so we only add paths ending in a built building to the queue.
				if neighbor.is_built:
					queue.append(new_path)
	return visited

# -----------------------------------------
# --- Grid Integrity -------------------
# -----------------------------------------
# Recalculates which buildings are powered, updates connection line colors, and handles cluster power state.
# Call this after any change to the grid topology or after caches are refreshed.
func _update_grid_integrity():
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

	# Pass 2: Set power state for all buildings and update connection visuals
	var powered_map := {}
	for building in registered_buildings:
		var is_powered = powered_buildings.has(building)
		building.set_powered_state(is_powered)
		powered_map[building] = is_powered
		
		# Reset packets in flight if building is isolated
		if not is_powered:
			building.reset_packets_in_flight()

	# Update connection visuals
	for connection in current_connections:
		connection.update_power_status(powered_map)

# -----------------------------------------
# --- Signals Handling --------------------
# -----------------------------------------
# Called when a registered building is built
func _on_building_built() -> void:
	_refresh_grid_caches()
	_update_grid_integrity()

# Called when cc finishes timer tick calculations and updates packets values
func _on_cc_update_packets(pkt_stored: float, max_pkt_capacity: float , pkt_produced: float, pkt_consumed: float, net_balance: float) -> void:
	ui_update_packets.emit(pkt_stored, max_pkt_capacity, pkt_produced, pkt_consumed, net_balance)
