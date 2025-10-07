class_name NetworkManager
extends Node

@export var energy_packet_scene: PackedScene
#@export var energy_transfer_interval: float = 1.0
@export var energy_packet_speed: float = 150.0
#var _energy_timer := 0.0


# All active relay nodes
var relays: Array[Relay] = []
# Each entry holds a connection dictionary: { "relay_a": Relay, "relay_b": Relay, "connection_line": Line2D }
var connections: Array = []


func _ready():
	add_to_group("network_manager")


# -----------------------
# Relay registration
# -----------------------

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

# -----------------------
# Network construction
# -----------------------

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
	
	# Reset power states and start packet-driven propagation
	#propagate_power_from_bases()
	reset_power_states()
	start_energy_propagation()

# -----------------------
# Line creation
# -----------------------

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

# -----------------------
# Power propagation
# -----------------------

func reset_power_states():
	for relay in relays:
		relay.set_powered(false)

func start_energy_propagation():
	for relay in relays:
		if relay.is_base:
			relay.set_powered(true)
			for neighbor in relay.connected_relays:
				if not neighbor.is_powered:
					_spawn_energy_packet(relay.global_position, neighbor.global_position, neighbor)


# -----------------------
# Packet spawning
# -----------------------

func _spawn_energy_packet(from_pos: Vector2, to_pos: Vector2, target_relay: Relay):
	if not energy_packet_scene or target_relay == null:
		return

	var packet: Packet = energy_packet_scene.instantiate() as Packet
	add_child(packet)

	packet.start_pos = from_pos
	packet.end_pos = to_pos
	packet.global_position = from_pos
	packet.speed = energy_packet_speed
	packet.target = target_relay
	
	
	packet.packet_arrived.connect(Callable(self, "_on_packet_arrived"))
	#packet.packet_arrived.connect(_on_packet_arrived)

# -----------------------
# Packet arrival handler
# -----------------------

func _on_packet_arrived(target_relay: Relay):
	if not target_relay.is_powered:
		target_relay.set_powered(true)
		for neighbor in target_relay.connected_relays:
			if not neighbor.is_powered:
				_spawn_energy_packet(target_relay.global_position, neighbor.global_position, neighbor)
