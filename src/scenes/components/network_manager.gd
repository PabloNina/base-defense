class_name NetworkManager
extends Node

# -------------------------------
# --- Editor Exports -----------
# -------------------------------
@export var energy_packet_scene: PackedScene
@export var energy_packet_speed: float = 150.0

# -------------------------------
# --- Runtime Data -------------
# -------------------------------
var relays: Array[Relay] = []  # all active relays
var connections: Array = []    # connection visuals {relay_a, relay_b, connection_line}

# -------------------------------
# --- Base Packet Rate Control ---
# -------------------------------
var base_timers: Dictionary = {}  # base relay -> Timer
var base_packet_rate: int = 2 # packets per second

# -------------------------------
# --- Engine Callbacks ----------
# -------------------------------
func _ready():
	add_to_group("network_manager")
	initialize_network()
	# initialize timers for existing bases
	for base in relays:
		if base.is_base:
			_setup_base_timer(base)


func _process(_delta):
	# Update visual lines if relays move
	for connection_data in connections:
		if is_instance_valid(connection_data.connection_line):
			var a = connection_data.relay_a
			var b = connection_data.relay_b
			var line = connection_data.connection_line

			# Update line position
			line.points = [a.global_position, b.global_position]

			# --- Debug color overlay ---
			if a.is_powered and b.is_powered:
				line.default_color = Color(0.1, 1.0, 0.3)  # bright green = active
				line.default_color.a = 0.7 + 0.3 * sin(Time.get_ticks_msec() / 200.0)
			else:
				line.default_color = Color(1.0, 0.2, 0.2)  # red = inactive


# -------------------------------
# --- Base Timer Setup ----------
# -------------------------------
func _setup_base_timer(base: Relay):
	if base in base_timers:
		return

	var timer = Timer.new()
	timer.wait_time = 1.0 / base_packet_rate
	timer.one_shot = false
	timer.autostart = true
	timer.connect("timeout", Callable(self, "_on_base_timeout").bind(base))
	add_child(timer)
	base_timers[base] = timer

# -------------------------------
# --- Base Packet Spawn Timer ---
# -------------------------------
func _on_base_timeout(base: Relay):
	# send packets along paths to all unpowered relays
	_start_propagation_from_base(base)


# -------------------------------
# --- Relay Registration -------
# -------------------------------
func register_relay(relay: Relay):
	if relay not in relays:
		relays.append(relay)

	_update_connections_for(relay)

	if relay.is_base:
		relay.set_powered(true)
		_setup_base_timer(relay)


func unregister_relay(relay: Relay):
	if relay not in relays:
		return

	relays.erase(relay)

	for connection_data in connections:
		if connection_data.relay_a == relay or connection_data.relay_b == relay:
			if is_instance_valid(connection_data.connection_line):
				connection_data.connection_line.queue_free()

	connections = connections.filter(func(c): return c.relay_a != relay and c.relay_b != relay)

# -------------------------------
# --- Network Construction -----
# -------------------------------
func initialize_network():
	rebuild_all_connections()

	# power bases only, do not spawn packets manually
	for base in relays:
		if base.is_base:
			base.set_powered(true)
			_setup_base_timer(base)


func rebuild_all_connections():
	for connection_data in connections:
		if is_instance_valid(connection_data.connection_line):
			connection_data.connection_line.queue_free()
	connections.clear()

	for relay in relays:
		relay.connected_relays.clear()

	for i in range(relays.size()):
		for j in range(i + 1, relays.size()):
			var relay_a: Relay = relays[i]
			var relay_b: Relay = relays[j]
			var distance = relay_a.global_position.distance_to(relay_b.global_position)
			var max_dist = min(relay_a.connection_range, relay_b.connection_range)

			if distance <= max_dist:
				relay_a.connect_to(relay_b)
				relay_b.connect_to(relay_a)
				create_connection_line(relay_a, relay_b)



func _update_connections_for(new_relay: Relay):
	for relay in relays:
		if relay == new_relay:
			continue

		var distance = relay.global_position.distance_to(new_relay.global_position)
		var max_dist = min(relay.connection_range, new_relay.connection_range)

		if distance <= max_dist:
			relay.connect_to(new_relay)
			new_relay.connect_to(relay)
			if _connection_exists(relay, new_relay) == false:
				create_connection_line(relay, new_relay)

func _connection_exists(a: Relay, b: Relay) -> bool:
	for connection_data in connections:
		if (connection_data.relay_a == a and connection_data.relay_b == b) \
		or (connection_data.relay_a == b and connection_data.relay_b == a):
			return true
	return false

# -------------------------------
# --- Visual Lines -------------
# -------------------------------
func create_connection_line(relay_a: Relay, relay_b: Relay):
	var line := Line2D.new()
	line.width = 1
	line.default_color = Color(0.3, 0.9, 1.0)
	line.points = [relay_a.global_position, relay_b.global_position]
	add_child(line)

	connections.append({
		"relay_a": relay_a,
		"relay_b": relay_b,
		"connection_line": line
	})
# -------------------------------
# --- Pathfinding --------------
# -------------------------------
# Type-safe BFS that only travels through powered relays and find shortest path(except the target)
func _find_path(start: Relay, target: Relay) -> Array[Relay]:
	var visited: Array[Relay] = []
	var queue: Array = []  # can't type this as Array[Array[Relay]]

	queue.append([start])

	while queue.size() > 0:
		var path_untyped: Array = queue.pop_front()

		# convert untyped path to typed Array[Relay]
		var path: Array[Relay] = []
		for r in path_untyped:
			path.append(r)

		var current: Relay = path[-1]

		if current == target:
			# debug: build names array the GDScript way (no list comprehensions)
			var names: Array = []
			for rel in path:
				names.append(rel.name)
				print("✅ Path found: ", names)
			return path

		if current in visited:
			continue
			
		visited.append(current)

		# Only expand neighbors that are powered — except for the target
		for neighbor in current.connected_relays:
			if neighbor == target or neighbor.is_powered:
				if neighbor not in visited:
					var new_path: Array[Relay] = path.duplicate()
					new_path.append(neighbor)
					queue.append(new_path)

	# no valid path found
	#print("⚠️ No path found from", start.name, "to", target.name)
	return []
# -------------------------------
# --- Energy Propagation -------
# -------------------------------
func _start_propagation_from_base(base: Relay):
	if not base.is_base:
		return

	# Collect all reachable unpowered relays
	var unpowered_targets: Array = []
	for relay in relays:
		if not relay.is_powered and not relay.is_scheduled:
			var path = _find_path(base, relay)
			if path.size() > 1:
				unpowered_targets.append({"relay": relay, "path": path})

	# Sort by path length (number of hops)
	unpowered_targets.sort_custom(func(a, b):
		return a.path.size() < b.path.size()
	)

	# Spawn only one packet per timer tick
	if unpowered_targets.size() > 0:
		var target_data = unpowered_targets[0]
		target_data.relay.is_scheduled = true
		_spawn_packet_along_path(target_data.path)


func _spawn_packet_along_path(path: Array[Relay]):
	# spawn one packet that will move from base → relay → ... → target
	var packet = energy_packet_scene.instantiate()
	add_child(packet)

	packet.path = path
	packet.speed = energy_packet_speed
	packet.global_position = path[0].global_position
	packet.packet_arrived.connect(_on_packet_arrived)
	

func _on_packet_arrived(target_relay: Relay):
	if target_relay.is_powered == false:
		target_relay.set_powered(true)

	target_relay.is_scheduled = false
