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
var current_connections: Array = []             # Connection visuals between buildings
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
	_rebuild_all_connections() # handles both connections and power states 


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

func _connect_buildings(building_a: Building, building_b: Building):
	building_a.connect_to(building_b)
	building_b.connect_to(building_a)
	if not _connection_exists(building_a, building_b):
		_create_connection_line(building_a, building_b)

func _connection_exists(building_a: Building, building_b: Building) -> bool:
	for connection in current_connections:
		if (connection.building_a == building_a and connection.building_b == building_b) or (connection.building_a == building_b and connection.building_b == building_a):
			return true
	return false

# used only in unregister
func _clear_connections_for(building: Building):
	for connection in current_connections:
		if connection.building_a == building or connection.building_b == building:
			if is_instance_valid(connection.connection_line):
				connection.connection_line.queue_free()
	current_connections = current_connections.filter(func(connection): return connection.building_a != building and connection.building_b != building)

func _clear_all_connections():
	for connection in current_connections:
		if is_instance_valid(connection.connection_line):
			connection.connection_line.queue_free()
	current_connections.clear()

func _create_connection_line(building_a: Building, building_b: Building):
	var line := Line2D.new()
	line.width = 1
	line.default_color = Color(0.3, 0.9, 1.0)
	line.points = [building_a.global_position, building_b.global_position]
	lines_2d_container.add_child(line)
	current_connections.append({"building_a": building_a, "building_b": building_b, "connection_line": line})

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

func _get_reachable_buildings_from_base(base: Building) -> Array:
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
		if not is_instance_valid(connection.connection_line):
			continue
		var a_powered = powered_map.get(connection.building_a, false)
		var b_powered = powered_map.get(connection.building_b, false)
		connection.connection_line.default_color = Color(0.3, 0.9, 1.0) if (a_powered or b_powered) else Color(1, 0.3, 0.3)

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
	_refresh_grid_caches()
	_update_grid_integrity()

# Called when cc finishes timer tick calculations and updates packets values
func _on_cc_update_packets(pkt_stored: float, max_pkt_capacity: float , pkt_produced: float, pkt_consumed: float, net_balance: float) -> void:
	ui_update_packets.emit(pkt_stored, max_pkt_capacity, pkt_produced, pkt_consumed, net_balance)
