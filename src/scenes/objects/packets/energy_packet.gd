class_name Packet
extends Node2D

var target: Relay
var start_pos: Vector2
var end_pos: Vector2
var speed: float = 100.0

signal packet_arrived(target)

func _process(delta):
	if not is_instance_valid(self):
		return
		
	var direction = (end_pos - start_pos).normalized()
	position += direction * speed * delta
	
	# Check if packet has reached the destination
	if start_pos.distance_to(position) >= start_pos.distance_to(end_pos):
		#emit_signal("packet_arrived")
		packet_arrived.emit(target)
		queue_free()
