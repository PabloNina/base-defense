# PacketPool - packet_pool.gd
# ============================================================================
# This script implements an object pooling pattern specifically for Packet
# objects. Its primary goal is to optimize game performance by minimizing the
# overhead associated with frequently creating and destroying Packet nodes.
#
# Key Responsibilities:
# - Pre-population: Initializes a pool of Packet instances at the start of the
#   game, making them ready for immediate use.
#
# - Dynamic Growth: Automatically expands the pool size if all available
#   packets are in use, ensuring a continuous supply without interruption.
#
# - Packet Acquisition: Provides a method to retrieve a pre-configured Packet
#   from the pool, initializing it with necessary data (type, speed, path, position).
#
# - Packet Return: Manages the return of used Packet objects to the pool,
#   resetting their state and making them available for future reuse.
#
# - Performance Optimization: By recycling Packet instances, it significantly
#   reduces garbage collection overhead and CPU spikes that would occur from
#   constant node instantiation/deletion, leading to smoother gameplay.
# ============================================================================
class_name PacketPool extends Node
# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
## The initial size of the pool.
@export var pool_size: int = 100
## The value to increment pool_size each time the pool goes empty.
@export var pool_grow_value: int = 25
# -----------------------------------------
# --- Runtime Data ------------------------
# -----------------------------------------
# The pool of available Packet objects.
var packet_pool: Array[Packet] = []
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Pre-populate the pool with packet instances.
	_populate_pool(pool_size)

# ---------------------------------
# --- Private Methods -------------
# ---------------------------------
# Pre-instantiates a number of Packets to have them ready for use.
func _populate_pool(size: int) -> void:
	for i in range(size):
		var packet: Packet = GlobalData.PACKET_SCENE.instantiate()
		# Disable the packet and add it to the pool.
		packet.process_mode = Node.PROCESS_MODE_DISABLED
		packet.visible = false
		packet_pool.append(packet)
		add_child(packet)

# -----------------------------------------
# --- Public Methods/Get&Return Packets ---
# -----------------------------------------
# Retrieves a Packet from the pool. If the pool is empty it creates more.
# Initializes the Packet with the provided parameters.
# Returns the configured Packet.
func get_packet(pkt_type: GlobalData.PACKETS, pkt_speed: int, pkt_path: Array[Building], pkt_position: Vector2) -> Packet:
	# Add more Packets if the pool runs dry.
	# This makes the pool grow dynamically as needed.
	if packet_pool.is_empty():
		print("Packet pool empty. Growing pool!")
		_populate_pool(pool_grow_value)

	# Get a Packet from the front of the pool.
	var packet: Packet = packet_pool.pop_front()

	# The Packet is a child of the pool remove it before handing it out.
	if packet.get_parent() == self:
		remove_child(packet)

	# Initialize the Packet's properties
	packet.packet_type = pkt_type
	packet.speed = pkt_speed
	packet.path = pkt_path
	packet.global_position = pkt_position

	# Reset internal state
	packet.current_index = 0
	packet.is_cleaned_up = false
	packet.set_sprite()

	# Enable the Packet for processing and visibility
	packet.process_mode = Node.PROCESS_MODE_INHERIT
	packet.visible = true

	return packet


# Returns a Packet back to the pool.
# Disables the Packet and makes it available for reuse.
func return_packet(packet: Packet) -> void:
	if not is_instance_valid(packet):
		return

	# Disable the Packet.
	packet.process_mode = Node.PROCESS_MODE_DISABLED
	packet.visible = false

	# Reparent the Packet to the pool to keep the scene tree clean.
	if packet.get_parent() != self:
		packet.get_parent().remove_child(packet)
		add_child(packet)

	# Add the Packet back to the pool.
	packet_pool.append(packet)
