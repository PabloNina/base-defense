# packet_pool.gd
# Singleton that manages a pool of reusable packet objects to optimize performance
# by avoiding frequent instantiation and destruction.
class_name PacketPool extends Node

# The packet scene to be used for creating the pool.
const PACKET_SCENE: PackedScene = preload("res://src/scenes/objects/packets/base_packet.tscn")
# The initial size of the object pool.
@export var pool_size: int = 100

# The pool of available packet objects.
var _pool: Array[Packet] = []


func _ready() -> void:
	# Pre-populate the pool with packet instances.
	for i in range(pool_size):
		var packet: Packet = PACKET_SCENE.instantiate()
		# Disable the packet and add it to the pool.
		packet.process_mode = Node.PROCESS_MODE_DISABLED
		packet.visible = false
		_pool.append(packet)
		add_child(packet)


# Acquires a packet from the pool.
# Initializes the packet with the provided parameters.
# Returns the configured packet.
func acquire_packet(pkt_type: DataTypes.PACKETS, pkt_speed: int, pkt_path: Array[Building], pkt_position: Vector2) -> Packet:
	var packet: Packet
	if _pool.is_empty():
		# Pool is empty, so we create a new packet on the fly.
		# This makes the pool grow dynamically as needed.
		print("Packet pool empty. Growing pool.")
		packet = PACKET_SCENE.instantiate()
		# Add the new packet as a child of the pool so it's tracked.
		add_child(packet)
	else:
		# Get a packet from the front of the pool.
		packet = _pool.pop_front()

	# Initialize the packet's properties
	packet.packet_type = pkt_type
	packet.speed = pkt_speed
	packet.path = pkt_path
	packet.global_position = pkt_position
	
	# Reset internal state
	packet.current_index = 0
	packet._set_sprite()

	# Enable the packet for processing and visibility
	packet.process_mode = Node.PROCESS_MODE_INHERIT
	packet.visible = true
	
	return packet


# Releases a packet back to the pool.
# Disables the packet and makes it available for reuse.
func release_packet(packet: Packet) -> void:
	if not is_instance_valid(packet):
		return

	# Add the packet back to the pool.
	_pool.append(packet)

	# Disable the packet.
	packet.process_mode = Node.PROCESS_MODE_DISABLED
	packet.visible = false
	
	# Reparent the packet to the pool to keep the scene tree clean.
	if packet.get_parent() != self:
		packet.get_parent().remove_child(packet)
		add_child(packet)
