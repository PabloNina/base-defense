class_name EnemyManager extends Node
# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
## Used for coordinate conversion
@export var enemy_map_layer: TileMapLayer
## Determines how quickly ooze spreads from higher-depth tiles to lower-depth adjacent tiles.
## A higher value means faster equalization of ooze levels.
@export var flow_rate: float = 0.1 
## The minimum amount of ooze a tile must have to be considered "active" and remain in the ooze_map.
## Tiles with ooze levels below this threshold are removed to optimize performance and clean up negligible amounts.
@export var min_ooze_threshold: float = 0.01 
# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
@onready var active_ooze_container: Node = $ActiveOozeContainer
@onready var ooze_pool: OozePool = $OozePool
# -----------------------------------------
# --- Runtime Data ------------------------
# -----------------------------------------
# A dictionary mapping tile coordinates (Vector2i) to ooze depth (float).
# Holds the pure simulation data. All the physics and flow calculations operate only on this data.
var ooze_map: Dictionary = {}
# A dictionary to keep track of instantiated EnemyOoze objects, mapped by their tile coordinates.
# The visual objects that the player sees.
var ooze_instances: Dictionary = {}

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	add_to_group("enemy_manager")

func _physics_process(delta: float) -> void:
	# Temporary dictionary to store changes in ooze levels for the current frame.
	# This prevents modifying ooze_map while iterating over it, ensuring stable calculations.
	var flow_deltas: Dictionary = {}
	# List to keep track of tiles that should be removed after processing,
	# typically because their ooze level has dropped below the minimum threshold.
	var tiles_to_remove: Array[Vector2i] = []

	# The simulation is done in three main steps for stability and clarity.
	if not ooze_map.is_empty():
		# 1. Calculate Flow: Determine ooze movement between tiles without changing the map yet.
		_calculate_map_flow(delta, flow_deltas, tiles_to_remove)
		# 2. Apply Flow: Update the ooze map with the calculated movements.
		_apply_map_flow(flow_deltas, tiles_to_remove)
		# 3. Cleanup: Remove tiles with negligible amounts of ooze to keep the simulation efficient.
		_cleanup_map(tiles_to_remove)
	
	# After the map simulation step, update the visual representation of the ooze on the tilemap.
	_update_ooze_visuals()


# --------------------------------------------------
# ---------------- Public Methods ------------------
# --------------------------------------------------

# Adds a specified amount of ooze to a given tile.
# If the tile already has ooze, the amount is added to the existing value.
func add_ooze(tile_coord: Vector2i, amount: float) -> void:
	if ooze_map.has(tile_coord):
		ooze_map[tile_coord] += amount
	else:
		ooze_map[tile_coord] = amount


# --------------------------------------------------
# ---------------- Private Methods -----------------
# --------------------------------------------------

# -----------------------------------------
# --- Flow Simulation Data ----------------
# -----------------------------------------
# First pass: Calculate all flow amounts between adjacent tiles.
# We iterate over a copy of the keys to safely modify the map later.
func _calculate_map_flow(delta: float, flow_deltas: Dictionary, tiles_to_remove: Array[Vector2i]) -> void:
	for tile_coord in ooze_map.keys():
		var current_ooze: float = ooze_map[tile_coord]
		
		# If a tile's ooze is below the threshold, mark it for removal and skip processing.
		if current_ooze <= min_ooze_threshold:
			tiles_to_remove.append(tile_coord)
			continue

		# Get the surrounding cells for flow calculation.
		var neighbors: Array[Vector2i] = enemy_map_layer.get_surrounding_cells(tile_coord)

		for neighbor_coord in neighbors:
			# Get neighbor's ooze level, defaulting to 0.0 if the neighbor has no ooze yet.
			var neighbor_ooze: float = ooze_map.get(neighbor_coord, 0.0)

			# If the current tile has more ooze than its neighbor, calculate flow.
			if current_ooze > neighbor_ooze:
				var diff: float = current_ooze - neighbor_ooze
				# The amount of ooze to flow is proportional to the difference, flow_rate, and delta time.
				var flow_amount: float = diff * flow_rate * delta

				# Accumulate flow changes in flow_deltas.
				# Ooze flows from current tile to neighbor.
				flow_deltas[neighbor_coord] = flow_deltas.get(neighbor_coord, 0.0) + flow_amount
				flow_deltas[tile_coord] = flow_deltas.get(tile_coord, 0.0) - flow_amount


# Second pass: Apply all calculated flow amounts to the ooze_map.
func _apply_map_flow(flow_deltas: Dictionary, tiles_to_remove: Array[Vector2i]) -> void:
	for tile_coord in flow_deltas.keys():
		ooze_map[tile_coord] = ooze_map.get(tile_coord, 0.0) + flow_deltas[tile_coord]
		# After applying flow, if a tile's ooze drops below threshold, mark for removal.
		if ooze_map[tile_coord] <= min_ooze_threshold:
			tiles_to_remove.append(tile_coord)


# Clean up tiles marked for removal.
func _cleanup_map(tiles_to_remove: Array[Vector2i]) -> void:
	for tile_coord in tiles_to_remove:
		# Ensure the tile still exists and is below threshold before erasing,
		# as it might have been re-added or increased by another flow in the same frame.
		if ooze_map.has(tile_coord) and ooze_map[tile_coord] <= min_ooze_threshold:
			ooze_map.erase(tile_coord)

# -----------------------------------------
# --- Flow Visual Synchronization ---------
# -----------------------------------------
# Manages the visual representation of ooze, creating, updating, and removing ooze instances as needed.
func _update_ooze_visuals() -> void:
	if not is_instance_valid(enemy_map_layer):
		return

	# Assume all existing instances will be removed until we confirm they are still active.
	var instances_to_remove: Array[Vector2i]
	instances_to_remove.assign(ooze_instances.keys())
	
	# Create new ooze instances for tiles that don't have one, and update existing ones.
	# Active instances are removed from the 'instances_to_remove' list.
	_synchronize_ooze_instances(instances_to_remove)
	
	# Remove any ooze instances that are no longer in the ooze_map.
	_cleanup_inactive_instances(instances_to_remove)


# Ensures that there is an ooze instance for every tile in ooze_map and updates its visuals.
# It also tracks which instances are still active by removing them from the 'instances_to_remove' list.
func _synchronize_ooze_instances(instances_to_remove: Array[Vector2i]) -> void:
	for tile_coord in ooze_map.keys():
		var depth: float = ooze_map[tile_coord]
		var ooze_instance: EnemyOoze = ooze_instances.get(tile_coord)

		if not is_instance_valid(ooze_instance):
			# If no instance exists for this tile, create a new one.
			ooze_instance = _get_ooze_from_pool(tile_coord)
			active_ooze_container.add_child(ooze_instance)

		# Update the visuals of the instance.
		ooze_instance.update_visuals(depth)

		# This instance is active, so we remove it from the list of instances to be removed.
		instances_to_remove.erase(tile_coord)


# Creates a new EnemyOoze instance at a specific tile coordinate and returns it.
func _create_ooze_instance(tile_coord: Vector2i) -> EnemyOoze:
	var ooze_instance: EnemyOoze = GlobalData.ENEMY_OOZE_SCENE.instantiate()
	active_ooze_container.add_child(ooze_instance)
	ooze_instance.position = enemy_map_layer.map_to_local(tile_coord)# + Vector2(enemy_map_layer.tile_set.tile_size) / 2.0 # Center on tile
	ooze_instances[tile_coord] = ooze_instance
	return ooze_instance


# Removes all ooze instances that are marked for removal.
# These are instances that were not found in the active ooze_map during the update cycle.
func _cleanup_inactive_instances(instances_to_remove: Array[Vector2i]) -> void:
	for tile_coord in instances_to_remove:
		var ooze_instance: EnemyOoze = ooze_instances[tile_coord]
		if is_instance_valid(ooze_instance):
			_return_ooze_to_pool(ooze_instance)
		ooze_instances.erase(tile_coord)


# -------------------------------
# --- Ooze Pool Wrappers --------
# -------------------------------
# Creates a new EnemyOoze instance at a specific tile coordinate and returns it.
func _get_ooze_from_pool(tile_coord: Vector2i) -> EnemyOoze:
	var ooze_instance: EnemyOoze = ooze_pool.get_ooze()
	ooze_instance.position = enemy_map_layer.map_to_local(tile_coord)
	# add it to ooze_instances dictionary
	ooze_instances[tile_coord] = ooze_instance
	return ooze_instance


func _return_ooze_to_pool(ooze: EnemyOoze) -> void:
	ooze_pool.return_ooze(ooze)
