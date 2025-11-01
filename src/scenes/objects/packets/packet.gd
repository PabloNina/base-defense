# =========================================
# Packet.gd
# =========================================
class_name Packet extends Node2D

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

# Signals
signal packet_arrived(packet: Packet)
signal path_broken(packet: Packet)

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

# -------------------------------
# --- Movement Logic -----------
# -------------------------------
func _follow_path(delta: float) -> void:
	if current_index >= path.size() - 1:
		return

	var next_relay = path[current_index + 1]

	# Cancel packet if next relay is destroyed
	if not is_instance_valid(next_relay):
		path_broken.emit(self)
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
				path_broken.emit(self)

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
