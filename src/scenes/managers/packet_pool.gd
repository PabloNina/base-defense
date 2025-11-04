# =========================================
# packet_pool.gd
# =========================================
# Manages a pool of reusable Packet objects to optimize performance
# by avoiding frequent instantiation and destruction.
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

# ---------------------------------
# --- Public Methods --------------
# ---------------------------------
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
