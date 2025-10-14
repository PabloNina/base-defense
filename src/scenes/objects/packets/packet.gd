# =========================================
# Packet.gd
# =========================================
class_name Packet
extends Node2D

# -------------------------------
# --- Packet Configuration ------
# -------------------------------
var path: Array[Relay] = []               # full path: base → ... → target
var speed: int = 0
var current_index: int = 0

@export var packet_type: DataTypes.PACKETS = DataTypes.PACKETS.NULL

signal packet_arrived(target: Relay, packet_type: DataTypes.PACKETS)  # Listener: NetworkManager

# -------------------------------
# --- Engine Callbacks ----------
# -------------------------------
func _ready():
	if path.size() < 2:
		return
	global_position = path[0].global_position
	current_index = 0

# -------------------------------
# --- Movement Logic -----------
# -------------------------------
func _process(delta):
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
			_cleanup_packet()

# -------------------------------
# --- Helper: Cleanup ----------
# -------------------------------
func _cleanup_packet():
	# Decrement packets_on_the_way for the target relay safely
	if path.size() > 0 and is_instance_valid(path[-1]):
		path[-1].packets_on_the_way = max(0, path[-1].packets_on_the_way - 1)
	queue_free()
