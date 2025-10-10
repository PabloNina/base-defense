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
var relays: Array[Relay] = []              # All active relays
var connections: Array = []                # Connection visuals: {relay_a, relay_b, connection_line}
var base_timers: Dictionary = {}           # Base relay -> Timer
var base_packet_rate: int = 2              # Packets per second
signal update_energy(current_energy: int)  # UI update

# -------------------------------
# --- Engine Callbacks ----------
# -------------------------------
func _ready():
	add_to_group("network_manager")
	initialize_network()

func _process(_delta):
	_update_connection_lines()

# -------------------------------
# --- Relay Registration -------
# -------------------------------
func register_relay(relay: Relay):
	if relay in relays:
		return
	relays.append(relay)
	_update_connections_for(relay)

	if relay.is_base:
		relay.set_powered(true)
		_setup_packet_timer(relay)

	_refresh_network()

	if relay.is_built:
		relay.set_powered(true)
		relay._update_power_visual()

func unregister_relay(relay: Relay):
	if relay not in relays:
		return
	relays.erase(relay)
	_clear_connections_for(relay)

	for other in relays:
		other.connected_relays.erase(relay)

	if base_timers.has(relay):
		base_timers[relay].queue_free()
		base_timers.erase(relay)

	_refresh_network()

# -------------------------------
# --- Network Construction -----
# -------------------------------
func initialize_network():
	_refresh_network()

func _refresh_network():
	rebuild_all_connections()
	refresh_power_states()

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

func _update_connections_for(new_relay: Relay):
	for relay in relays:
		if relay == new_relay:
			continue
		if _are_relays_in_range(relay, new_relay):
			_connect_relays(relay, new_relay)

# -------------------------------
# --- Connection Helpers -------
# -------------------------------
func _are_relays_in_range(a: Relay, b: Relay) -> bool:
	return a.global_position.distance_to(b.global_position) <= min(a.connection_range, b.connection_range)

func _connect_relays(a: Relay, b: Relay):
	a.connect_to(b)
	b.connect_to(a)
	if not _connection_exists(a, b):
		create_connection_line(a, b)

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

# -------------------------------
# --- Connection Lines / Visuals -
# -------------------------------
func create_connection_line(a: Relay, b: Relay):
	var line := Line2D.new()
	line.width = 1
	line.default_color = Color(0.3, 0.9, 1.0)
	line.points = [a.global_position, b.global_position]
	add_child(line)
	connections.append({"relay_a": a, "relay_b": b, "connection_line": line})

func _update_connection_lines():
	for c in connections:
		if not is_instance_valid(c.connection_line):
			continue
		var a = c.relay_a
		var b = c.relay_b
		var line = c.connection_line
		line.points = [a.global_position, b.global_position]

		if a.is_powered and b.is_powered:
			line.default_color = Color(0.1, 1.0, 0.3, 1.0)
			line.default_color.a = 0.7 + 0.3 * sin(Time.get_ticks_msec() / 200.0)
		else:
			line.default_color = Color(1.0, 0.2, 0.2)

# -------------------------------
# --- Power Propagation ---------
# -------------------------------
func refresh_power_states():
	for relay in relays:
		if not relay.is_base:
			relay.set_powered(false)

	for base in relays:
		if base.is_base:
			_propagate_power_from(base)

func _propagate_power_from(source: Relay):
	var visited: Array = []
	var stack: Array = [source]

	while stack.size() > 0:
		var current: Relay = stack.pop_back()
		if current in visited:
			continue
		visited.append(current)

		if current.is_base or current.is_built:
			current.set_powered(true)
			for neighbor in current.connected_relays:
				if is_instance_valid(neighbor) and (neighbor.is_base or neighbor.is_built):
					stack.append(neighbor)

# -------------------------------
# --- Timer / Packet Spawn -----
# -------------------------------
func _setup_packet_timer(base: Relay):
	if base in base_timers:
		return
	var timer = Timer.new()
	timer.wait_time = 1.0 / base_packet_rate
	timer.one_shot = false
	timer.autostart = true
	timer.connect("timeout", Callable(self, "_on_packet_spawn_tick").bind(base))
	add_child(timer)
	base_timers[base] = timer

func _on_packet_spawn_tick(base: Relay):
	if not base.is_base:
		return
	base.regen_energy()
	if base.has_enough_energy():
		_start_propagation_from_base(base)
	update_energy.emit(base.energy)

# -------------------------------
# --- Packet Propagation -------
# -------------------------------
func _start_propagation_from_base(base: Relay):
	var unpowered_targets: Array = []
	for relay in relays:
		if not relay.is_powered and not relay.is_scheduled:
			var path = _find_path(base, relay)
			if path.size() > 1:
				unpowered_targets.append({"relay": relay, "path": path})

	unpowered_targets.sort_custom(func(a, b): return a.path.size() < b.path.size())

	if unpowered_targets.size() > 0:
		var target_data = unpowered_targets[0]
		if target_data.relay.packets_on_the_way < target_data.relay.cost_to_build:
			target_data.relay.packets_on_the_way += 1
			_spawn_packet_along_path(target_data.path)
			base.spend_energy()
		if target_data.relay.packets_on_the_way == target_data.relay.cost_to_build:
			target_data.relay.is_scheduled = true

func _spawn_packet_along_path(path: Array[Relay]):
	var packet = energy_packet_scene.instantiate()
	add_child(packet)
	packet.path = path
	packet.speed = energy_packet_speed
	packet.global_position = path[0].global_position
	packet.packet_arrived.connect(_on_packet_arrived)

func _on_packet_arrived(target_relay: Relay):
	if not target_relay.is_built:
		target_relay.packets_received += 1
		if target_relay.packets_received >= target_relay.cost_to_build:
			target_relay.is_built = true
			target_relay.set_powered(true)
			target_relay._update_power_visual()

# -------------------------------
# --- Pathfinding --------------
# -------------------------------
func _find_path(start: Relay, target: Relay) -> Array[Relay]:
	var visited: Array = []
	var queue: Array = [start]
	var parent_map: Dictionary = {}
	
	visited.append(start)
	parent_map[start] = null

	while queue.size() > 0:
		var current: Relay = queue.pop_front()

		if current == target:
			var path: Array[Relay] = []
			var node: Relay = target
			while node != null:
				path.insert(0, node)
				node = parent_map.get(node)
			return path

		for neighbor in current.connected_relays:
			if not is_instance_valid(neighbor):
				continue
			if (neighbor.is_powered or neighbor == target) and neighbor not in visited:
				visited.append(neighbor)
				queue.append(neighbor)
				parent_map[neighbor] = current

	return []
