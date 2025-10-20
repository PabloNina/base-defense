class_name PacketManager extends Node

@export var network_manager: NetworkManager
@export_group("Packets")
@export var current_packet_speed: int = 150
@export var enable_packed_debug: bool = false

@onready var packets_container: Node = $PacketsContainer

# -----------------------------------------
# --- Packet Propagation ------------------
# -----------------------------------------
func start_packet_propagation(command_center: Command_Center, quota: int, packet_type: DataTypes.PACKETS) -> int:
	var packets_sent := 0
	if quota <= 0 or not network_manager.reachable_cache.has(command_center):
		return 0

	var targets := []
	for building in network_manager.reachable_cache[command_center]:
		if building == command_center or not is_instance_valid(building):
			continue

		# Use building's built-in needs_packet check
		if not building.needs_packet(packet_type):
			continue

		# Prevent over-queuing: skip building that already have enough packets on the way
		# use the correct target limit depending on packet type
		match packet_type:
			DataTypes.PACKETS.BUILDING:
				if building.is_scheduled_to_build:
					continue
			DataTypes.PACKETS.ENERGY:
				if building.packets_in_flight >= building.cost_to_supply:
					continue
			DataTypes.PACKETS.AMMO:
				if building.is_full_ammo:
					continue
			# for other packet types you may add custom checks here
			#_:
				# Default check

		targets.append(building)

	if targets.is_empty():
		return 0

	# Round-robin selection over the filtered targets
	var index = network_manager.last_target_index.get(command_center, 0)
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
			DataTypes.PACKETS.BUILDING:
				if building.is_scheduled_to_build:
					continue
			DataTypes.PACKETS.ENERGY:
				if building.packets_in_flight >= building.cost_to_supply:
					continue

		var key = str(command_center.get_instance_id()) + "_" + str(building.get_instance_id())
		if not network_manager.path_cache.has(key):
			continue

		var path = network_manager.path_cache[key]
		if path.size() <= 1 or path.any(func(r): return not is_instance_valid(r)):
			continue

		if not network_manager.are_connected(path[0], path[-1]):
			continue

		# Increment in-flight AFTER the final checks and BEFORE spawning the packet.
		# This ensures other bases/ticks see the incremented value immediately.
		building.increment_packets_in_flight()

		####### DEBUG ###############
		if enable_packed_debug:
			print("[DEBUG]", building.name, 
			" inflight=", building.packets_in_flight,
			" scheduled=", building.is_scheduled_to_build,
			" built=", building.is_built,
			" cost=", building.cost_to_build)
	
		_spawn_packet_along_path(path, packet_type, delay_accum)
		delay_accum += spawn_delay_step
		packets_sent += 1

	network_manager.last_target_index[command_center] = index % n
	return packets_sent

# -----------------------------------------
# --- Packet spawning ---------------------
# -----------------------------------------
func _spawn_packet_along_path(path: Array[Building], packet_type: DataTypes.PACKETS, delay_offset :float = 0.0) -> void:
	# Safety checks
	if path.size() < 2:
		return
	# Prevent packets from traversing through unbuilt relays **except** allow the final target
	# to be unbuilt when sending BUILDING packets (so CC can send building packets to construct new buildings).
	if path.size() >= 2:
		# Check intermediate nodes only (exclude last node)
		for i in range(path.size() - 1):
			var inter = path[i]
			if not is_instance_valid(inter) or not inter.is_built:
				return
	if not network_manager.are_connected(path[0], path[-1]):
		return

	# Additionally ensure each edge in the path is traversable.
	# An edge between path[i] and path[i+1] is traversable if both nodes are built
	# and at least one of the two endpoints is powered.
	for i in range(path.size() - 1):
		var a = path[i]
		var b = path[i+1]
		# If this edge is the final edge and packet_type == BUILDING, allow b to be unbuilt
		var is_final_edge = (i == path.size() - 2)
		if is_final_edge and packet_type == DataTypes.PACKETS.BUILDING:
			if not (is_instance_valid(a) and is_instance_valid(b) and a.is_built):
				return
		else:
			if not (is_instance_valid(a) and is_instance_valid(b) and a.is_built and b.is_built):
				return
		# Determine powered map from current network integrity (best-effort). If either is powered allow traversal.
		var a_powered := false
		var b_powered := false
		# powered_map may not be directly accessible here; check building state as a fallback
		if a.has_method("is_powered"):
			a_powered = a.is_powered
		else:
			a_powered = a.is_powered
		if b.has_method("is_powered"):
			b_powered = b.is_powered
		else:
			b_powered = b.is_powered
		if not (a_powered or b_powered):
			# both endpoints unpowered -> edge not traversable
			return
	
	# small per-packet delay to avoid packet stacking
	if delay_offset > 0.0:
		await get_tree().create_timer(delay_offset).timeout
	
	# Instance and setup the packet
	var packet: Packet = Packet.new_packet(packet_type, current_packet_speed, path.duplicate(), path[0].global_position)
	# Connect signals
	packet.packet_arrived.connect(_on_packet_arrived)
	# Add to container
	packets_container.add_child(packet)


func _on_packet_arrived(target_building: Building, packet_type: DataTypes.PACKETS):
	# Safety check: ensure building is still valid
	if not is_instance_valid(target_building):
		return
	# Relay processes the packet
	target_building.received_packet(packet_type)
	# Decrement in-flight packet count safely
	target_building.decrement_packets_in_flight()
