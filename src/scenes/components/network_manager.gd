class_name NetworkManager
extends Node

# All active relay nodes
var relays: Array[Relay] = []

# Each entry holds a connection dictionary: { "relay_a": Relay, "relay_b": Relay, "connection_line": Line2D }
var connections: Array = []


func _ready():
	add_to_group("network_manager")


# Called by a Relay node when it spawns
func register_relay(relay: Relay):
	if relay not in relays:
		relays.append(relay)
	update_network()


# Called by a Relay node before it is destroyed
func unregister_relay(relay: Relay):
	# Remove relay from relays Array
	relays.erase(relay)

	# Remove any existing connection lines involving this relay
	for connection_data in connections:
		if connection_data.relay_a == relay or connection_data.relay_b == relay:
			if is_instance_valid(connection_data.connection_line):
				connection_data.connection_line.queue_free()

	# Keep only valid connections
	connections = connections.filter(
		func(c): return c.relay_a != relay and c.relay_b != relay
	)

	update_network()


func update_network():
	# Remove all existing connection visuals
	for connection_data in connections:
		if is_instance_valid(connection_data.connection_line):
			connection_data.connection_line.queue_free()
	connections.clear()

	# Clear existing connection data on all relays
	for relay in relays:
		relay.connected_relays.clear()

	# Recalculate connections between all relay pairs
	for index_a in range(relays.size()):
		for index_b in range(index_a + 1, relays.size()):
			var relay_a: Relay = relays[index_a]
			var relay_b: Relay = relays[index_b]

			if not is_instance_valid(relay_a) or not is_instance_valid(relay_b):
				continue

			var distance_between_relays: float = relay_a.global_position.distance_to(relay_b.global_position)
			var max_connection_distance: float = min(relay_a.connection_range, relay_b.connection_range)

			if distance_between_relays <= max_connection_distance:
				relay_a.connect_to(relay_b)
				relay_b.connect_to(relay_a)
				create_connection_line(relay_a, relay_b)
	
	# Once the network is rebuilt update power states
	propagate_power_from_bases()

func create_connection_line(relay_a: Relay, relay_b: Relay):
	var connection_line := Line2D.new()
	connection_line.width = 2
	connection_line.default_color = Color(0.3, 0.9, 1.0)
	connection_line.points = [relay_a.global_position, relay_b.global_position]
	add_child(connection_line)

	connections.append({
		"relay_a": relay_a,
		"relay_b": relay_b,
		"connection_line": connection_line
	})

func propagate_power_from_bases():
	# Set all relays as unpowered
	for relay in relays:
		relay.set_powered(false)

	# Find base relays
	var base_relays = relays.filter(func(r): return r.is_base)

	# Traverse the network starting from all bases
	var visited: Array = []
	var queue: Array = base_relays.duplicate()

	while not queue.is_empty():
		var current_relay: Node2D = queue.pop_front()
		if current_relay in visited:
			continue
		visited.append(current_relay)

		current_relay.set_powered(true)

		for neighbor in current_relay.connected_relays:
			if neighbor not in visited:
				queue.append(neighbor)
