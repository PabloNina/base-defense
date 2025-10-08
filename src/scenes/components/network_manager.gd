# -------------------------------
# NetworkManager.gd
# -------------------------------
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
var base_packet_rate: float = 1.0 # packets per second

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
			connection_data.connection_line.points = [
				connection_data.relay_a.global_position,
				connection_data.relay_b.global_position
			]

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
			if not _connection_exists(relay, new_relay):
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
	line.width = 2
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
# Simple BFS to find shortest relay path
func _find_path(start: Relay, goal: Relay) -> Array[Relay]:
	var queue: Array = [[start]]
	var visited: Array[Relay] = [start]

	while queue.size() > 0:
		var path = queue.pop_front()
		var node: Relay = path[-1]

		if node == goal and path.size() > 1:  # ensure path includes at least start + goal
			var typed_path: Array[Relay] = []
			for relay in path:
				typed_path.append(relay)
				#print("✅ Path found:", typed_path)
			return typed_path

		for neighbor in node.connected_relays:
			if neighbor not in visited:
				visited.append(neighbor)
				var new_path = path.duplicate()
				new_path.append(neighbor)
				queue.append(new_path)

	# no valid path found
	#print("⚠️ No path found from", start.name, "to", goal.name)
	return []
	
# -------------------------------
# --- Energy Propagation -------
# -------------------------------
func _start_propagation_from_base(base: Relay):
	if not base.is_base:
		return

	for relay in relays:
		if not relay.is_powered and not relay.is_scheduled:
			var path = _find_path(base, relay)
			if path.size() > 1:
				relay.is_scheduled = true
				_spawn_packet_along_path(path)
				break  # only spawn one packet per timer tick
				
func _spawn_packet_along_path(path: Array[Relay]):
	# spawn one packet that will move from base → relay → ... → target
	var packet = energy_packet_scene.instantiate()
	add_child(packet)

	packet.path = path
	packet.speed = energy_packet_speed
	packet.global_position = path[0].global_position
	packet.packet_arrived.connect(_on_packet_arrived)
	

func _on_packet_arrived(target_relay: Relay):
	if not target_relay.is_powered:
		target_relay.set_powered(true)

	target_relay.is_scheduled = false
