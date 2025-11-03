# =========================================
# packet_pool.gd
# =========================================
# Manages a pool of reusable Packet objects to optimize performance
# by avoiding frequent instantiation and destruction.
class_name PacketPool extends Node

## The initial size of the packet_pool.
@export var pool_size: int = 100
# The pool of available Packet objects.
var packet_pool: Array[Packet] = []


func _ready() -> void:
	# Pre-populate the pool with packet instances.
	_populate_pool(pool_size)

# Pre-instantiates a number of Packets to have them ready for use.
func _populate_pool(size: int) -> void:
	for i in range(size):
		var packet: Packet = GlobalData.PACKET_SCENE.instantiate()
		# Disable the packet and add it to the pool.
		packet.process_mode = Node.PROCESS_MODE_DISABLED
		packet.visible = false
		packet_pool.append(packet)
		add_child(packet)

# Retrieves a packet from the pool. If the pool is empty it creates more.
# Initializes the packet with the provided parameters.
# Returns the configured packet.
func acquire_packet(pkt_type: GlobalData.PACKETS, pkt_speed: int, pkt_path: Array[Building], pkt_position: Vector2) -> Packet:
	var packet: Packet
	if packet_pool.is_empty():
		# Add more Packets if the pool runs dry.
		# This makes the pool grow dynamically as needed.
		print("Packet pool empty. Growing pool!")
		packet = GlobalData.PACKET_SCENE.instantiate()
		# Add the new packet as a child of the pool so it's tracked.
		add_child(packet)
	else:
		# Get a packet from the front of the pool.
		packet = packet_pool.pop_front()

	# Initialize the packet's properties
	packet.packet_type = pkt_type
	packet.speed = pkt_speed
	packet.path = pkt_path
	packet.global_position = pkt_position
	
	# Reset internal state
	packet.current_index = 0
	packet.is_cleaned_up = false
	packet._set_sprite()

	# Enable the packet for processing and visibility
	packet.process_mode = Node.PROCESS_MODE_INHERIT
	packet.visible = true
	
	return packet


# Returns a packet back to the pool.
# Disables the packet and makes it available for reuse.
func release_packet(packet: Packet) -> void:
	if not is_instance_valid(packet):
		return

	# Add the packet back to the pool.
	packet_pool.append(packet)

	# Disable the packet.
	packet.process_mode = Node.PROCESS_MODE_DISABLED
	packet.visible = false
	
	# Reparent the packet to the pool to keep the scene tree clean.
	if packet.get_parent() != self:
		packet.get_parent().remove_child(packet)
		add_child(packet)
