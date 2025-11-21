class_name OozeEmitter extends Node2D
# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
## Ooze amount added per emission
@export var emission_amount: float = 20.0
## Number of emissions per second
@export var emissions_per_second: int = 1
## Reference to the TileMapLayer for coordinate conversion
@export var ooze_tilemap_layer: TileMapLayer
# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
@onready var emission_timer: Timer = $EmissionTimer
# -----------------------------------------
# --- Private Variables -------------------
# -----------------------------------------
var flow_manager: FlowManager
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Get the FlowManager.
	flow_manager = get_tree().get_first_node_in_group("flow_manager")
	# Timer Setup
	_config_emission_timer()

# --------------------------------------------------
# ---------------- Private Methods -----------------
# --------------------------------------------------
func _config_emission_timer() -> void:
	emission_timer.wait_time = 1.0 / emissions_per_second
	emission_timer.timeout.connect(_on_emission_timer_tick)
	emission_timer.start()


func _on_emission_timer_tick() -> void:
	# Ensure both the FlowManager and the TileMapLayer are valid before proceeding.
	if not is_instance_valid(flow_manager) or not is_instance_valid(ooze_tilemap_layer):
		return

	# Convert the emitter's global position to a tile coordinate.
	var tile_coord: Vector2i = ooze_tilemap_layer.local_to_map(global_position)
	# Calculate the amount of ooze to emit this frame.
	var amount_to_emit: float = emission_amount
	
	# Add the calculated ooze amount to the FlowManager's map.
	flow_manager.add_ooze(tile_coord, amount_to_emit)
