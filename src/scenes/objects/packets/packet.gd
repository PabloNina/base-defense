# =========================================
# Packet.gd
# =========================================
class_name Packet extends Node2D

const PACKET_SCENE: PackedScene = preload("res://src/scenes/objects/packets/base_packet.tscn")
const GREEN_TEXTURE: Texture2D = preload("res://assets/sprites/objects/energy_packet.png")
const RED_TEXTURE:Texture2D = preload("res://assets/sprites/objects/ammo_packet.png")
const BLUE_TEXTURE:Texture2D = preload("res://assets/sprites/objects/building_packet.png")
# -------------------------------
# --- Packet Configuration ------
# -------------------------------
var path: Array[Building] = [] # full path: base → ... → target
var current_index: int = 0
var speed: int = 0
var packet_type: DataTypes.PACKETS = DataTypes.PACKETS.NULL

@onready var sprite_2d: Sprite2D = $Sprite2D

# Listener: NetworkManager
signal packet_arrived(target: Building, packet_type: DataTypes.PACKETS)  

# -------------------------------
# --- Engine Callbacks ----------
# -------------------------------
func _ready():
	if path.size() < 2:
		return
	global_position = path[0].global_position
	current_index = 0
	_set_sprite()

func _process(delta: float):
	_follow_path(delta)

# ------------------------------------
# --- Public Methods / Constructor ---
# ------------------------------------
# Packet Constructor - uses the packet_pool singleton
static func new_packet(pkt_type: DataTypes.PACKETS, pkt_speed: int, pkt_path: Array[Building], pkt_position: Vector2) -> Packet:
	# Acquire a packet from the global pool.
	var packet: Packet = packet_pool.acquire_packet(pkt_type, pkt_speed, pkt_path, pkt_position)
	
	# The group is useful for debugging or broad interactions, so we add it here.
	if is_instance_valid(packet) and not packet.is_in_group("packets"):
		packet.add_to_group("packets")
		
	return packet

# -------------------------------
# --- Movement Logic -----------
# -------------------------------
func _follow_path(delta: float) -> void:
	if current_index >= path.size() - 1:
		return

	var next_relay = path[current_index + 1]

	# Cancel packet if next relay is destroyed
	if not is_instance_valid(next_relay):
		_cleanup_packet()
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
				packet_arrived.emit(path[-1], packet_type)
			# Release packet back to the pool
			packet_pool.release_packet(self)

# -----------------------
# --- Visuals -----------
# -----------------------
# Set sprite texture base on packet type
func _set_sprite() -> void:
	match packet_type:
		DataTypes.PACKETS.BUILDING:
			sprite_2d.texture = GREEN_TEXTURE
		DataTypes.PACKETS.AMMO:
			sprite_2d.texture = RED_TEXTURE
		DataTypes.PACKETS.ENERGY:
			sprite_2d.texture = BLUE_TEXTURE
		_:
			return  # Unsupported packet type

# -------------------------------
# --- Helper: Cleanup ----------
# -------------------------------
# Called when packet cant reach the final destination
func _cleanup_packet():
	# Decrement packets_on_flight for the target building safely
	if path.size() > 0 and is_instance_valid(path[-1]):
		path[-1].decrement_packets_in_flight()
	
	# Release packet back to the pool
	packet_pool.release_packet(self)
