class_name Bullet extends Node2D

@export var speed: int = 500


var flow_manager: FlowManager
var target_tile: Vector2i = Vector2i.ZERO

func _ready() -> void:
	set_as_top_level(true)


func _physics_process(delta: float) -> void:
	_fly_towards_target_tile(delta)


func _fly_towards_target_tile(delta: float) -> void:
	# Convert target tile coords
	var target_position: Vector2 = flow_manager.ooze_tilemap_layer.map_to_local(target_tile)
	# Move towards the target position at a constant speed
	global_position = global_position.move_toward(target_position, speed * delta)

	# Check if the bullet has reached the target
	if global_position.is_equal_approx(target_position):
		print("Bullet hit: " + str(target_tile))
		# Remove ooze
		flow_manager.remove_ooze([target_tile], 100)
		# Remove the bullet node
		queue_free()
