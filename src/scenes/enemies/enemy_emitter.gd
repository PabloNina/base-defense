class_name EnemyEmitter extends Node2D

@onready var emission_timer: Timer = $EmissionTimer

## Ooze amount emitted per tick
@export var emission_amount: float = 20.0
## Time between emissions in seconds
@export var emission_tick_rate: float = 1.0
## Reference to the TileMapLayer for coordinate conversion
@export var enemy_map_layer: TileMapLayer

var enemy_manager: EnemyManager

func _ready() -> void:
	# Get the EnemyManager.
	enemy_manager = get_tree().get_first_node_in_group("enemy_manager")
	# Timer Setup
	emission_timer.wait_time = emission_tick_rate
	emission_timer.autostart = true
	emission_timer.one_shot = false
	emission_timer.timeout.connect(_on_emission_timer_tick)

func _on_emission_timer_tick() -> void:
	# Ensure both the EnemyManager and the TileMapLayer are valid before proceeding.
	if not is_instance_valid(enemy_manager) or not is_instance_valid(enemy_map_layer):
		return

	# Convert the emitter's global position to a tile coordinate.
	var tile_coord: Vector2i = enemy_map_layer.local_to_map(global_position)
	# Calculate the amount of ooze to emit this frame.
	var amount_to_emit: float = emission_amount
	
	# Add the calculated ooze amount to the EnemyManager's map.
	enemy_manager.add_ooze(tile_coord, amount_to_emit)
