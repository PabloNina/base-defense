class_name Packet
extends Node2D

# -------------------------------
# --- Packet Configuration ------
# -------------------------------
var path: Array[Relay] = [] # full path: base → ... → target
var speed: float = 1000.0
var current_index: int = 0

# Listener: 
signal packet_arrived(target: Relay)

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
	var direction = (next_relay.global_position - global_position).normalized()
	global_position += direction * speed * delta

	# check if reached the next relay
	if global_position.distance_to(next_relay.global_position) <= speed * delta:
		global_position = next_relay.global_position
		current_index += 1

		# reached final relay → consume packet
		if current_index >= path.size() - 1:
			packet_arrived.emit(path[-1])
			queue_free()
