class_name EnemyEmitter extends Node2D

@export var emission_rate: float = 20.0 # Ooze units emitted per second
@export var enemy_map_layer: TileMapLayer # Reference to the TileMapLayer for coordinate conversion

var enemy_manager: EnemyManager

func _ready() -> void:
	# Get the EnemyManager.
	enemy_manager = get_tree().get_first_node_in_group("enemy_manager")

func _physics_process(delta: float) -> void:
	# Ensure both the EnemyManager and the TileMapLayer are valid before proceeding.
	if not is_instance_valid(enemy_manager) or not is_instance_valid(enemy_map_layer):
		return

	# Convert the emitter's global position to a tile coordinate.
	var tile_coord: Vector2i = enemy_map_layer.local_to_map(global_position)
	# Calculate the amount of ooze to emit this frame.
	var amount_to_emit: float = emission_rate * delta
	
	# Add the calculated ooze amount to the EnemyManager's map.
	enemy_manager.add_ooze(tile_coord, amount_to_emit)
