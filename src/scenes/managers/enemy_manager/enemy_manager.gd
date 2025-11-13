class_name EnemyManager extends Node
# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
## The TileMap layer used for ooze coordinate conversion and rendering.
@export var enemy_layer: TileMapLayer
## The TileMap layer that contains the ground and wall terrain information.
@export var ground_layer: TileMapLayer
## The terrain ID of wall tiles. Ooze will not flow into tiles with this terrain ID.
@export var wall_terrain_id: int = 1
## Determines how quickly ooze spreads. A higher value means faster flow.
@export var flow_rate: float = 0.25
## Ooze levels below this threshold are removed from the simulation to optimize performance.
@export var min_ooze_threshold: float = 0.01
## The maximum amount of ooze that can accumulate on a single tile.
@export var max_ooze_per_tile: float = 100.0
## The color of the ooze. The alpha component will be updated based on depth.
@export var ooze_color: Color = Color.PURPLE
# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
# A reference to the MultiMeshInstance2D node in the scene tree.
# This node is configured in the editor and used for rendering all ooze visuals.
@onready var ooze_multi_mesh: MultiMeshInstance2D = $OozeMultiMesh
# -----------------------------------------
# --- Private Variables -------------------
# -----------------------------------------
# The MultiMesh resource that holds the geometry and instance data for rendering.
var multimesh: MultiMesh
# A dictionary mapping tile coordinates (Vector2i) to ooze depth (float).
# This stores the core simulation data, separate from the visuals.
var ooze_map: Dictionary = {}

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Add to group for easy access from other nodes (like emitters).
	add_to_group("enemy_manager")
	
	# Ensure the multimesh instance is valid before proceeding.
	if not is_instance_valid(ooze_multi_mesh):
		push_error("MultiMeshInstance2D node not found!")
		return

	# Get the multimesh resource from the instance node.
	multimesh = ooze_multi_mesh.multimesh
	# Ensure the multimesh is cleared at the start.
	multimesh.instance_count = 0
	# Set the multimesh mesh size
	multimesh.mesh.size = GlobalData.TILE_SIZE_VECTOR2

func _physics_process(delta: float) -> void:
	# Only run the simulation if there is ooze on the map.
	if not ooze_map.is_empty():
		# This dictionary will store the amount of ooze to be added or removed from each tile in the current frame.
		# This prevents race conditions and ensures calculations for a frame are based on the state at the start of the frame.
		var flow_deltas: Dictionary = {}
		
		# 1. Calculate Flow: Determine ooze movement between tiles based on pressure differences.
		_calculate_map_flow(delta, flow_deltas)
		# 2. Apply Flow: Update the ooze map with the calculated movements.
		_apply_map_flow(flow_deltas)
	
	# 3. After the map simulation, update the visual representation of the ooze.
	_update_ooze_visuals()

# --------------------------------------------------
# ---------------- Public Methods ------------------
# --------------------------------------------------

## Adds a specified amount of ooze to a given tile.
## This is the primary way other nodes (like emitters) interact with the ooze simulation.
## This function handles overflow by distributing excess ooze to neighbors.
func add_ooze(tile_coord: Vector2i, amount: float) -> void:
	# Use a queue to process ooze additions, allowing for cascading overflows.
	var processing_queue: Array[Dictionary] = [{"coord": tile_coord, "amount": amount}]
	# Keep track of how many times we've processed a coordinate in this call to prevent infinite loops.
	var process_counts: Dictionary = {}

	while not processing_queue.is_empty():
		var current_job: Dictionary = processing_queue.pop_front()
		var coord: Vector2i = current_job["coord"]
		var job_amount: float = current_job["amount"]

		# Stop if a tile is being processed too many times in one frame, which indicates a feedback loop.
		# The limit (8) is chosen to be higher than the maximum number of neighbors (4) to allow for some back-and-forth.
		process_counts[coord] = process_counts.get(coord, 0) + 1
		if process_counts[coord] > 8:
			continue

		# Do not add ooze to walls.
		if _is_wall(coord):
			continue
			
		var current_ooze: float = ooze_map.get(coord, 0.0)
		var new_ooze_amount: float = current_ooze + job_amount
		
		if new_ooze_amount <= max_ooze_per_tile:
			# The tile can hold the new ooze without overflowing.
			ooze_map[coord] = new_ooze_amount
		else:
			# The tile overflows. Set it to max and distribute the excess.
			ooze_map[coord] = max_ooze_per_tile
			var overflow_amount: float = new_ooze_amount - max_ooze_per_tile
			
			# Find valid neighbors to receive the overflow.
			var neighbors: Array[Vector2i] = enemy_layer.get_surrounding_cells(coord)
			var valid_neighbors: Array[Vector2i] = []
			for neighbor_coord in neighbors:
				if not _is_wall(neighbor_coord):
					valid_neighbors.append(neighbor_coord)
			
			# If there are valid neighbors, add the overflow amount to the queue for processing.
			if not valid_neighbors.is_empty():
				var amount_per_neighbor: float = overflow_amount / valid_neighbors.size()
				for neighbor_coord in valid_neighbors:
					processing_queue.append({"coord": neighbor_coord, "amount": amount_per_neighbor})

# --------------------------------------------------
# ---------------- Private Methods -----------------
# --------------------------------------------------

# -----------------------------------------
# --- Wall Detection ----------------------
# -----------------------------------------
## Checks if a given tile coordinate corresponds to a wall.
func _is_wall(tile_coord: Vector2i) -> bool:
	# If the ground layer isn't set or the wall terrain ID is not set, assume nothing is a wall.
	if not is_instance_valid(ground_layer) or wall_terrain_id == -1:
		return false

	# Get the data resource for the tile at the given coordinate.
	var tile_data: TileData = ground_layer.get_cell_tile_data(tile_coord)
	# If there is no tile data (e.g., an empty cell), it's not a wall.
	if not is_instance_valid(tile_data):
		return false

	# Check the terrain ID of the tile against the configured wall terrain ID.
	return tile_data.terrain == wall_terrain_id

# -----------------------------------------
# --- Flow Simulation ---------------------
# -----------------------------------------
## Calculates the flow of ooze between adjacent tiles for one physics frame.
## It populates the `flow_deltas` dictionary with the changes.
func _calculate_map_flow(delta: float, flow_deltas: Dictionary) -> void:
	# Iterate over a copy of keys, as the underlying ooze_map can change if a tile is added mid-frame.
	for tile_coord in ooze_map.keys():
		var current_ooze: float = ooze_map[tile_coord]

		# Get the 4 direct neighbors of the current tile.
		var neighbors: Array[Vector2i] = enemy_layer.get_surrounding_cells(tile_coord)
		var valid_lower_neighbors: Array[Vector2i] = []
		var total_potential_flow_to_lower: float = 0.0

		# First pass: Identify valid lower neighbors and calculate the total amount of ooze that
		# could potentially flow out of the current tile.
		for neighbor_coord in neighbors:
			if _is_wall(neighbor_coord):
				continue # Skip walls entirely

			var neighbor_ooze: float = ooze_map.get(neighbor_coord, 0.0)

			if current_ooze > neighbor_ooze:
				valid_lower_neighbors.append(neighbor_coord)
				var diff: float = current_ooze - neighbor_ooze
				# The amount of flow is proportional to half the difference, which creates a stable equalization effect.
				# Multiplying by 'delta' makes the flow rate independent of the frame rate.
				var potential_flow: float = (diff / 2.0) * flow_rate * delta
				total_potential_flow_to_lower += potential_flow
		
		if valid_lower_neighbors.is_empty() or total_potential_flow_to_lower <= 0:
			continue # Nothing to flow, or no valid places to flow to

		# Determine the actual amount of ooze that can flow out from the current tile.
		# It's either the total potential flow, or all the ooze on the tile, whichever is smaller.
		var actual_flow_out: float = min(current_ooze, total_potential_flow_to_lower)
		
		# Second pass: Distribute the actual flow among the valid lower neighbors.
		# The flow to each neighbor is proportional to its pressure difference relative to the total.
		for neighbor_coord in valid_lower_neighbors:
			var neighbor_ooze: float = ooze_map.get(neighbor_coord, 0.0)
			var diff: float = current_ooze - neighbor_ooze
			var potential_flow: float = (diff / 2.0) * flow_rate * delta
			
			# Scale the flow to this neighbor based on its proportion of the total potential flow.
			var scaled_flow: float = 0.0
			if total_potential_flow_to_lower > 0: # Avoid division by zero
				scaled_flow = actual_flow_out * (potential_flow / total_potential_flow_to_lower)
			
			# Record the change in ooze for both the current tile and its neighbor.
			flow_deltas[neighbor_coord] = flow_deltas.get(neighbor_coord, 0.0) + scaled_flow
			flow_deltas[tile_coord] = flow_deltas.get(tile_coord, 0.0) - scaled_flow

# -----------------------------------------
# --- State Update & Sync -----------------
# -----------------------------------------
## Applies the calculated flow amounts from `flow_deltas` to the main `ooze_map`.
## Also handles clamping values and removing tiles with negligible ooze.
func _apply_map_flow(flow_deltas: Dictionary) -> void:
	var tiles_to_remove: Array[Vector2i] = []
	for tile_coord in flow_deltas.keys():
		var new_amount: float = ooze_map.get(tile_coord, 0.0) + flow_deltas[tile_coord]
		
		# Clamp the new value to ensure it's within the valid range [0, max_ooze_per_tile].
		ooze_map[tile_coord] = clamp(new_amount, 0, max_ooze_per_tile)

		# If the ooze level on a tile drops below the minimum threshold, mark it for removal.
		if ooze_map[tile_coord] <= min_ooze_threshold:
			tiles_to_remove.append(tile_coord)
	
	# Clean up: remove all tiles that were marked for removal to keep the simulation efficient.
	for tile_coord in tiles_to_remove:
		if ooze_map.has(tile_coord) and ooze_map[tile_coord] <= min_ooze_threshold:
			ooze_map.erase(tile_coord)

## Updates the MultiMesh to reflect the current state of the `ooze_map`.
## This function is the bridge between the simulation data and the visuals.
func _update_ooze_visuals() -> void:
	# Set the number of instances to be rendered to match the number of tiles with ooze.
	multimesh.instance_count = ooze_map.size()
	if ooze_map.is_empty():
		return

	var idx: int = 0
	# Iterate through every tile that has ooze.
	for tile_coord in ooze_map.keys():
		var depth: float = ooze_map[tile_coord]
		
		# Set the position for this instance.
		var position: Vector2 = enemy_layer.map_to_local(tile_coord)
		var transform := Transform2D(0.0, position)
		multimesh.set_instance_transform_2d(idx, transform)
		
		# Set the color for this instance, modulating alpha based on ooze depth.
		var color: Color = ooze_color
		# The alpha is proportional to the ooze depth. Here, it reaches full opacity at half the max depth.
		color.a = clamp(depth / (max_ooze_per_tile / 2.0), 0.1, 1.0)
		multimesh.set_instance_color(idx, color)
		
		idx += 1
