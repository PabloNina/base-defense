# Packet - packet.gd
# ============================================================================
# This is the base class for all packet types (Energy, Ammo, Building) that
# traverse the grid network. Packets are responsible for moving along a
# predefined path between buildings, delivering resources, and managing their
# own lifecycle, including self-cleanup if their path becomes invalid.
#
# Key Responsibilities:
# - Path Traversal: Moves along a sequence of Building nodes, from a source
#   (e.g., Command Center) to a target building.
#
# - Resource Delivery: Upon reaching its destination, it notifies the target
#   building to process the delivered resource.
#
# - Self-Cleanup: Monitors the validity of its path and target buildings. If
#   any part of its path becomes invalid (e.g., a building is destroyed), the
#   packet initiates its own cleanup process.
#
# - Visual Representation: Displays the appropriate sprite based on its packet
#   type (Energy, Ammo, Building).
#
# - Lifecycle Signals: Emits signals to the PacketManager upon arrival at its
#   destination or when it needs to be cleaned up and returned to the PacketPool.
# ============================================================================
@abstract
class_name Packet extends Node2D
# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
@onready var sprite_2d: Sprite2D = $Sprite2D
# -----------------------------------------
# --- Signals -----------------------------
# -----------------------------------------
## Emited when packet reaches its target building
## Listener PacketManager
signal packet_arrived(packet: Packet)
# Emited in _cleanup_packet
# Listener PacketManager
signal packet_cleanup(packet: Packet)
# -------------------------------
# --- Packet Configuration ------
# -------------------------------
var path: Array[Building] = [] # full path: base → ... → target
var current_index: int = 0
var speed: int = 0
var packet_type: GlobalData.PACKETS = GlobalData.PACKETS.NULL
var is_cleaned_up: bool = false
# -------------------------------
# --- Engine Callbacks ----------
# -------------------------------
func _ready():
	is_cleaned_up = false
	if path.size() < 2:
		return
	global_position = path[0].global_position
	current_index = 0

func _process(delta: float):
	_follow_path(delta)

# ----------------------------------------------
# --- Public Methods / Cleanup&SpriteSetting ---
# ----------------------------------------------
# Called by GridManager when a building unregisters
# called on every packet that was using the destroyed building
func cleanup_packet() -> void:
	_return_to_pool()

# Called by PacketPool before giving it to PacketManager
# Set sprite texture base on packet type
func set_sprite() -> void:
	match packet_type:
		GlobalData.PACKETS.BUILDING:
			sprite_2d.texture = GlobalData.GREEN_PACKET_TEXTURE
		GlobalData.PACKETS.AMMO:
			sprite_2d.texture = GlobalData.RED_PACKET_TEXTURE
		GlobalData.PACKETS.ENERGY:
			sprite_2d.texture = GlobalData.BLUE_PACKET_TEXTURE
		_:
			return  # Unsupported packet type

# -------------------------------
# --- Return to Pool ------------
# -------------------------------
func _return_to_pool() -> void:
	if is_cleaned_up:
		return
	is_cleaned_up = true
	packet_cleanup.emit(self)

# -------------------------------
# --- Movement Logic ------------
# -------------------------------
func _follow_path(delta: float) -> void:
	if current_index >= path.size() - 1:
		return

	var next_relay = path[current_index + 1]

	# Cancel packet if next relay is destroyed
	if not is_instance_valid(next_relay):
		_return_to_pool()
		return

	var direction = (next_relay.global_position - global_position).normalized()
	global_position += direction * speed * delta

	# Check if reached the next relay
	if global_position.distance_to(next_relay.global_position) <= speed * delta:
		global_position = next_relay.global_position
		current_index += 1

		# Final relay reached
		if current_index >= path.size() - 1:
			if is_instance_valid(path[-1]):
				packet_arrived.emit(self)
			else:
				_return_to_pool()
