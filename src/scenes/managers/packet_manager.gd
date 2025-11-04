class_name PacketManager extends Node

@export var grid_manager: GridManager
@export_group("Packets")
@export var current_packet_speed: int = 150
@export var enable_packed_debug: bool = false

@onready var active_packets_container: Node = $ActivePacketsContainer
@onready var packet_pool: PacketPool = $PacketPool

func _ready() -> void:
	add_to_group("packet_manager")

# -------------------------------
# --- Packet Pool Wrappers ------
# -------------------------------
func _get_packet_from_pool(pkt_type: GlobalData.PACKETS, pkt_speed: int, pkt_path: Array[Building], pkt_position: Vector2) -> Packet:
	var packet: Packet = packet_pool.get_packet(pkt_type, pkt_speed, pkt_path, pkt_position)
	if is_instance_valid(packet) and not packet.is_in_group("packets"):
		packet.add_to_group("packets")
	return packet

# Called by Packet
func return_packet_to_pool(packet: Packet) -> void:
	if packet.packet_arrived.is_connected(_on_packet_arrived):
		packet.packet_arrived.disconnect(_on_packet_arrived)
	packet_pool.return_packet(packet)

# -----------------------------------------
# --- Packet Propagation ------------------
# -----------------------------------------
func start_packet_propagation(command_center: Command_Center, quota: int, packet_type: GlobalData.PACKETS) -> int:
	var packets_sent := 0
	if quota <= 0 or not grid_manager.reachable_from_base_cache.has(command_center):
		return 0

	var targets := []
	for building in grid_manager.reachable_from_base_cache[command_center]:
		if building == command_center or not is_instance_valid(building):
			continue

		# Use building's built-in needs_packet check
		if not building.needs_packet(packet_type):
			continue

		# Prevent over-queuing: skip building that already have enough packets on the way
		# use the correct target limit depending on packet type
		match packet_type:
			GlobalData.PACKETS.BUILDING:
				if building.is_scheduled_to_build or building.is_built:
					continue
			GlobalData.PACKETS.AMMO:
				if building.is_scheduled_to_full_ammo or building.is_full_ammo:
					continue
			# other packet types
			#_:
				# Default check

		targets.append(building)

	if targets.is_empty():
		return 0

	# Round-robin selection over the filtered targets
	var index = grid_manager.last_target_index.get(command_center, 0)
	var n = targets.size()
	
	#
	var spawn_delay_step: float = 0.1  # seconds between packets
	var delay_accum: float = 0.0
	
	for i in range(n):
		if packets_sent >= quota:
			break

		var building = targets[index % n]
		index += 1

		# Skip again if target became invalid or has now enough in-flight packets (race-safe)
		if not is_instance_valid(building):
			continue
		match packet_type:
			GlobalData.PACKETS.BUILDING:
				if building.is_scheduled_to_build or building.is_built:
					continue
			GlobalData.PACKETS.AMMO:
				if building.is_scheduled_to_full_ammo or building.is_full_ammo:
					continue


		var key = str(command_center.get_instance_id()) + "_" + str(building.get_instance_id())
		if not grid_manager.path_cache.has(key):
			continue

		var path = grid_manager.path_cache[key]
		if path.size() <= 1 or path.any(func(r): return not is_instance_valid(r)):
			continue

		if not grid_manager.are_connected(path[0], path[-1]):
			continue

		# Check if the path is traversable before incrementing in-flight packets and spawning.
		if not _is_path_traversable(path, packet_type):
			continue

		# Increment in-flight AFTER the final checks and BEFORE spawning the packet.
		# This ensures other bases/ticks see the incremented value immediately.
		building.increment_packets_in_flight()

		_spawn_packet_along_path(path, packet_type, delay_accum)
		delay_accum += spawn_delay_step
		packets_sent += 1

	grid_manager.last_target_index[command_center] = index % n
	return packets_sent

# -----------------------------------------
# --- Packet spawning ---------------------
# -----------------------------------------
func _is_path_traversable(path: Array[Building], packet_type: GlobalData.PACKETS) -> bool:
	# A path must have at least a start and an end.
	if path.size() < 2:
		return false

	# The start and end nodes must be connected in the grid.
	if not grid_manager.are_connected(path[0], path[-1]):
		return false

	# Check the validity of each edge in the path.
	for i in range(path.size() - 1):
		var a = path[i]
		var b = path[i+1]

		# Both nodes in an edge must be valid instances.
		if not is_instance_valid(a) or not is_instance_valid(b):
			return false

		# Check if the nodes are built. There's a special case for building packets.
		var is_final_edge = (i == path.size() - 2)
		if is_final_edge and packet_type == GlobalData.PACKETS.BUILDING:
			# For the final edge of a building packet, only the source (a) must be built.
			if not a.is_built:
				return false
		else:
			# For all other cases, both nodes must be built.
			if not a.is_built or not b.is_built:
				return false

		# At least one of the two nodes in an edge must be powered.
		if not a.is_powered and not b.is_powered:
			return false
			
	return true

func _spawn_packet_along_path(path: Array[Building], packet_type: GlobalData.PACKETS, delay_offset :float = 0.0) -> void:
	# Use a small delay to prevent packets from stacking on top of each other.
	if delay_offset > 0.0:
		await get_tree().create_timer(delay_offset).timeout
	
	# Acquire a new packet from the pool and set it up.
	var packet: Packet = _get_packet_from_pool(packet_type, current_packet_speed, path.duplicate(), path[0].global_position)
	
	# Connect to the packet's signals to manage its lifecycle.
	if not packet.packet_arrived.is_connected(_on_packet_arrived):
		packet.packet_arrived.connect(_on_packet_arrived)

	# Add the packet to active_packets_container.
	#packet.reparent(active_packets_container)
	active_packets_container.add_child(packet)

func _on_packet_arrived(packet: Packet):
	if packet.is_cleaned_up:
		return
	packet.is_cleaned_up = true

	var target_building = packet.path[-1]
	var packet_type = packet.packet_type

	# Safety check: ensure building is still valid
	if not is_instance_valid(target_building):
		return
	# Relay processes the packet
	target_building.received_packet(packet_type)
	# Decrement in-flight packet count safely
	target_building.decrement_packets_in_flight()
	# Release the packet
	return_packet_to_pool(packet)

func _on_path_broken(packet: Packet):
	packet._cleanup_packet()
