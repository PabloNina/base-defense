class_name FlowManager extends Node
# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
@export_group("Manager Configuration")
## The TileMap layer used for ooze coordinate conversion and rendering.
@export var ooze_tilemap_layer: TileMapLayer
## The TileMap layer that contains the ground and wall terrain information.
@export var ground_tilemap_layer: TileMapLayer
## The BuildingManager node, used to get a list of all buildings.
@export var building_manager: BuildingManager
@export_group("Flow Configuration")
## Determines how quickly ooze spreads. A higher value means faster flow.
@export var flow_rate: float = 0.25
## Ooze levels below this threshold are removed from the simulation to optimize performance.
@export var min_ooze_per_tile: float = 0.01
## The maximum amount of ooze that can accumulate on a single tile.
@export var max_ooze_per_tile: float = 100.0
@export_group("Simulation Configuration")
## How many times per second the ooze flow simulation should run.
## A lower value increases performance but makes the simulation less granular.
@export var simulation_steps_per_second: int = 10
@export_group("Ooze Visuals")
## The color of the ooze. The alpha component will be updated based on depth.
@export var ooze_color: Color = Color.YELLOW
@export var ooze_min_alpha: float = 0.2
@export var ooze_max_alpha: float = 1.0
# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
# This node is configured in the editor and used for rendering all ooze visuals.
@onready var ooze_multimesh_instance: MultiMeshInstance2D = $OozeMultiMesh
# This timer controls the frequency of the expensive flow simulation.
@onready var flow_simulation_timer: Timer = $FlowSimulationTimer

# -----------------------------------------
# --- Private Variables -------------------
# -----------------------------------------
# The terrain ID of wall tiles. Ooze will not flow into tiles with this terrain ID.
var wall_terrain_id: int = -1
# The tile ID for buildable ground. Ooze can only flow on these tiles.
var buildable_tile_id: int = -1
# The MultiMesh resource that holds the geometry and instance data for rendering.
var multimesh: MultiMesh
# A dictionary mapping tile coordinates (Vector2i) to ooze depth (float).
# This stores the core simulation data, separate from the visuals.
var ooze_map: Dictionary = {}
# --- Tiles Active List Optimization ---
# A dictionary (used as a set) of tile coordinates that need to be processed in the current simulation step.
# This prevents iterating over the entire ooze_map, providing a significant performance boost.
var active_list: Dictionary = {}
# A dictionary to build up the list of active tiles for the *next* simulation step.
var next_step_active_list: Dictionary = {}

# A dictionary mapping tile coordinates (Vector2i) to terrain height (int).
var terrain_height_map: Dictionary = {}
# A constant to map terrain IDs from GlobalData to integer height values.
const TERRAIN_ID_TO_HEIGHT: Dictionary = {
	GlobalData.GROUND_LVL1_TERRAIN_ID: 1,
	GlobalData.GROUND_LVL2_TERRAIN_ID: 2,
	GlobalData.GROUND_LVL3_TERRAIN_ID: 3,
	GlobalData.GROUND_LVL4_TERRAIN_ID: 4,
	GlobalData.GROUND_LVL5_TERRAIN_ID: 5,
}

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Get tile and terrain ids from global data
	wall_terrain_id = GlobalData.WALL_TERRAIN_ID
	buildable_tile_id = GlobalData.BUILDABLE_TILE_ID
	# Add to group for easy access from other nodes (like emitters).
	add_to_group("enemy_manager")
	# Setup the terrain height map, ooze multimesh, and the simulation timer.
	_create_terrain_height_map()
	_config_ooze_multimesh()
	_config_flow_simulation_timer()

# --------------------------------------------------
# ---------------- Public Methods ------------------
# --------------------------------------------------

## Adds a specified amount of ooze to a given tile.
## This is the primary way other nodes (like emitters) interact with the ooze simulation.
func add_ooze(tile_coord: Vector2i, amount: float) -> void:
	# Do not add ooze to non-buildable tiles.
	if not _is_valid_tile(tile_coord):
		return
		
	# Get the current ooze, add the new amount, and update the map.
	# We allow the ooze to temporarily go above 'max_ooze_per_tile'.
	# The main simulation loop will resolve and spread this "over-pressure" smoothly.
	var current_ooze: float = ooze_map.get(tile_coord, 0.0)
	ooze_map[tile_coord] = current_ooze + amount
	
	# Mark this tile and its neighbors as active so the main simulation
	# can process the new ooze on the next step.
	_activate_tile_and_neighbors(tile_coord)


## Removes a specified amount of ooze from a given list of tiles.
## This can be used for single-tile removal or for area-of-effect weapons.
func remove_ooze(tile_coords: Array[Vector2i], amount_per_tile: float) -> void:
	# Iterate through each tile coordinate provided.
	for tile_coord in tile_coords:
		# Only try to remove ooze if the tile exists in the map.
		if ooze_map.has(tile_coord):
			# Mark this tile and its neighbors as active since its state is changing.
			_activate_tile_and_neighbors(tile_coord)
			
			var new_amount: float = ooze_map[tile_coord] - amount_per_tile
			print("Removed " + str(amount_per_tile) + " Ooze from " + str(tile_coord) + " Current Ooze: " + str(ooze_map.get(tile_coord)))

			# If the ooze drops below the threshold, remove the tile completely.
			if new_amount <= min_ooze_per_tile:
				ooze_map.erase(tile_coord)
			else:
				# Otherwise, just update the amount.
				ooze_map[tile_coord] = new_amount


## Finds the nearest ooze tile to a given position within a specified range.
## This function is used by weapons to identify ooze targets.
## Returns Vector2i(-1, -1) if no ooze tile is found.
func get_nearest_ooze_tile(position: Vector2, max_distance: float) -> Vector2i:
	var closest_tile: Vector2i = Vector2i(-1, -1)
	var min_dist_sq: float = -1.0

	for tile_coord in ooze_map.keys():
		var tile_pos: Vector2 = ooze_tilemap_layer.map_to_local(tile_coord)
		var dist_sq: float = position.distance_squared_to(tile_pos)

		if dist_sq <= max_distance * max_distance:
			if min_dist_sq == -1.0 or dist_sq < min_dist_sq:
				min_dist_sq = dist_sq
				closest_tile = tile_coord
	
	return closest_tile
# --------------------------------------------------
# ---------------- Private Methods -----------------
# --------------------------------------------------

# -----------------------------------------
# --- Timer Configuration ---------------
# -----------------------------------------
## Configures and starts the timer for the flow simulation.
func _config_flow_simulation_timer() -> void:
	# Set the timer's wait time based on the desired steps per second.
	# This ensures the simulation runs at a consistent rate.
	flow_simulation_timer.wait_time = 1.0 / simulation_steps_per_second
	# Connect the timer's timeout signal to the function that runs the simulation step.
	flow_simulation_timer.timeout.connect(_run_simulation_step)
	# Start the timer.
	flow_simulation_timer.start()

# -----------------------------------------
# --- Terrain Height Map Creation ---------
# -----------------------------------------
## Creates a map of terrain heights for every cell in the ground layer.
## This is called once at the start to optimize flow calculations.
func _create_terrain_height_map() -> void:
	if not is_instance_valid(ground_tilemap_layer):
		push_error("FlowManager: Ground TileMapLayer is not assigned!")
		return

	# Iterate over all cells that have tiles on them in the ground layer.
	var used_cells: Array[Vector2i] = ground_tilemap_layer.get_used_cells()
	for cell_coord in used_cells:
		var tile_data: TileData = ground_tilemap_layer.get_cell_tile_data(cell_coord)
		
		# Ensure tile data is valid before proceeding.
		if not is_instance_valid(tile_data):
			continue

		var terrain_id: int = tile_data.terrain
		# Check if the terrain ID has a corresponding height in our map.
		if TERRAIN_ID_TO_HEIGHT.has(terrain_id):
			terrain_height_map[cell_coord] = TERRAIN_ID_TO_HEIGHT[terrain_id]


# -----------------------------------------
# --- Ooze MultiMesh Configuration --------
# -----------------------------------------
func _config_ooze_multimesh() -> void:
	# Ensure the multimesh instance is valid before proceeding.
	if not is_instance_valid(ooze_multimesh_instance):
		push_error("MultiMeshInstance2D node not found!")
		return

	# Get the multimesh resource from the instance node.
	multimesh = ooze_multimesh_instance.multimesh
	# Ensure the multimesh is cleared at the start.
	multimesh.instance_count = 0
	# Set the multimesh mesh size to match game tile size
	multimesh.mesh.size = GlobalData.TILE_SIZE_VECTOR2

# -----------------------------------------
# --- Wall Detection ----------------------
# -----------------------------------------
# NOT BEING USED ATM
## Checks if a given tile coordinate corresponds to a wall.
func _is_wall(tile_coord: Vector2i) -> bool:
	# If the ground layer isn't set or the wall terrain ID is not set, assume nothing is a wall.
	if not is_instance_valid(ground_tilemap_layer) or wall_terrain_id == -1:
		return false

	# Get the data resource for the tile at the given coordinate.
	var tile_data: TileData = ground_tilemap_layer.get_cell_tile_data(tile_coord)
	# If there is no tile data (e.g., an empty cell), it's not a wall.
	if not is_instance_valid(tile_data):
		return false

	# Check the terrain ID of the tile against the configured wall terrain ID.
	return tile_data.terrain == wall_terrain_id

# -----------------------------------------
# --- Buildable Tile Detection ------------
# -----------------------------------------
## Checks if a given tile coordinate is a valid ground tile for ooze to exist on.
func _is_valid_tile(tile_coord: Vector2i) -> bool:
	# If the ground layer isn't set, assume it's not valid.
	if not is_instance_valid(ground_tilemap_layer):
		return false

	# Get the tile source ID. If it's -1, the cell is empty.
	var source_id: int = ground_tilemap_layer.get_cell_source_id(tile_coord)

	# Check if the source ID matches the configured buildable tile ID.
	return source_id == buildable_tile_id

# -----------------------------------------
# --- Active List Management --------------
# -----------------------------------------
## Marks a tile and its direct neighbors as "active" for the next simulation step.
## This is the core of the active list optimization.
func _activate_tile_and_neighbors(tile_coord: Vector2i) -> void:
	# Add the tile itself to the next active list.
	next_step_active_list[tile_coord] = true
	# Add all its valid neighbors.
	var neighbors: Array[Vector2i] = ooze_tilemap_layer.get_surrounding_cells(tile_coord)
	for neighbor_coord in neighbors:
		if _is_valid_tile(neighbor_coord):
			next_step_active_list[neighbor_coord] = true

# --------------------------------------------------
# ---------------- Main Flow Logic -----------------
# --------------------------------------------------

# -----------------------------------------
# --- Flow Simulation Step ----------------
# -----------------------------------------
## This function is called by the timer and executes one step of the ooze flow simulation.
## It contains the expensive calculations that are now decoupled from the physics frame rate.
func _run_simulation_step() -> void:
	# Active List Swap the list for the next step becomes the list for the current step.
	active_list = next_step_active_list.duplicate(true)
	# Clear the next step's list so it can be repopulated during this step.
	next_step_active_list.clear()
	
	# If there are no active tiles to process, we can skip the simulation for this step.
	if active_list.is_empty():
		return
		
	# This dictionary will store the amount of ooze to be added or removed from each tile in this simulation step.
	var flow_deltas: Dictionary = {}
	# The delta value is the timer's wait time, ensuring the flow rate is consistent
	# regardless of the simulation frequency.
	var delta: float = flow_simulation_timer.wait_time
	
	# 1. Calculate Flow: Determine ooze movement only for the active tiles.
	_calculate_ooze_map_flow(delta, flow_deltas)
	# 2. Apply Flow: Update the ooze map with the calculated movements.
	_apply_ooze_map_flow(flow_deltas)
	# 3. Show Visuals: Update ooze multi mesh using ooze map data 
	_update_ooze_visuals()
	# 4. Check for Buildings: See if any buildings are on ooze and destroy them.
	_check_for_buildings_on_ooze()


## Calculates the flow of ooze between adjacent tiles for one physics frame.
## It populates the `flow_deltas` dictionary with the changes.
## This function now only iterates over the `active_list`, not the entire `ooze_map`.
func _calculate_ooze_map_flow(delta: float, flow_deltas: Dictionary) -> void:
	# Iterate only over the active tiles for this simulation step.
	for tile_coord in active_list.keys():
		# The terrain height map may not contain the tile if it's outside the defined map area.
		if not terrain_height_map.has(tile_coord):
			continue
			
		var current_ooze: float = ooze_map.get(tile_coord, 0.0)
		var current_terrain_height: int = terrain_height_map[tile_coord]
		var current_total_height: float = current_terrain_height + current_ooze

		# Get the 4 direct neighbors of the current tile.
		var neighbors: Array[Vector2i] = ooze_tilemap_layer.get_surrounding_cells(tile_coord)
		var valid_lower_neighbors: Array[Vector2i] = []
		var total_potential_flow_to_lower: float = 0.0

		# First pass: Identify valid lower neighbors and calculate potential flow.
		for neighbor_coord in neighbors:
			# Ensure the neighbor is on the map and has a defined height.
			if not terrain_height_map.has(neighbor_coord):
				continue

			var neighbor_ooze: float = ooze_map.get(neighbor_coord, 0.0)
			var neighbor_terrain_height: int = terrain_height_map[neighbor_coord]
			var neighbor_total_height: float = neighbor_terrain_height + neighbor_ooze

			if current_total_height > neighbor_total_height:
				valid_lower_neighbors.append(neighbor_coord)
				var diff: float = current_total_height - neighbor_total_height
				# The division by the number of neighbors is now handled in the second pass
				# to correctly distribute the available ooze.
				var potential_flow: float = (diff / 2.0) * flow_rate * delta
				total_potential_flow_to_lower += potential_flow
		
		if valid_lower_neighbors.is_empty() or total_potential_flow_to_lower <= 0:
			continue # Nothing to flow, or no valid places to flow to

		# Determine the actual amount of ooze that can flow out from the current tile.
		# A tile cannot flow more ooze than it currently has.
		var actual_flow_out: float = min(current_ooze, total_potential_flow_to_lower)
		
		# Second pass: Distribute the actual flow among the valid lower neighbors
		# proportionally to their potential to receive ooze.
		for neighbor_coord in valid_lower_neighbors:
			var neighbor_ooze: float = ooze_map.get(neighbor_coord, 0.0)
			var neighbor_terrain_height: int = terrain_height_map[neighbor_coord]
			var neighbor_total_height: float = neighbor_terrain_height + neighbor_ooze
			
			var diff: float = current_total_height - neighbor_total_height
			var potential_flow: float = (diff / 2.0) * flow_rate * delta
			
			# Distribute the actual flow proportionally.
			var scaled_flow: float = 0.0
			if total_potential_flow_to_lower > 0: # Avoid division by zero
				scaled_flow = actual_flow_out * (potential_flow / total_potential_flow_to_lower)
			
			# Record the change in ooze for both the current tile and its neighbor.
			flow_deltas[neighbor_coord] = flow_deltas.get(neighbor_coord, 0.0) + scaled_flow
			flow_deltas[tile_coord] = flow_deltas.get(tile_coord, 0.0) - scaled_flow


# -----------------------------------------
# --- Flow Update & Sync ------------------
# -----------------------------------------
## Applies the calculated flow amounts from `flow_deltas` to the main `ooze_map`.
## Also handles clamping values and removing tiles with negligible ooze.
## Crucially also marks affected tiles as active for the next simulation step.
func _apply_ooze_map_flow(flow_deltas: Dictionary) -> void:
	var tiles_to_remove: Array[Vector2i] = []
	for tile_coord in flow_deltas.keys():
		# Any tile with a flow delta is inherently active, so activate it and its neighbors.
		_activate_tile_and_neighbors(tile_coord)
		
		var new_amount: float = ooze_map.get(tile_coord, 0.0) + flow_deltas[tile_coord]
		
		# Clamp the new value to ensure it's within the valid range [0, max_ooze_per_tile].
		ooze_map[tile_coord] = clamp(new_amount, 0, max_ooze_per_tile)

		# If the ooze level on a tile drops below the minimum threshold, mark it for removal.
		if ooze_map[tile_coord] <= min_ooze_per_tile:
			tiles_to_remove.append(tile_coord)
	
	# Clean up: remove all tiles that were marked for removal to keep the simulation efficient.
	for tile_coord in tiles_to_remove:
		if ooze_map.has(tile_coord) and ooze_map[tile_coord] <= min_ooze_per_tile:
			# Also activate tiles being removed to update their neighbors.
			_activate_tile_and_neighbors(tile_coord)
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
		var position: Vector2 = ooze_tilemap_layer.map_to_local(tile_coord)
		var transform := Transform2D(0.0, position)
		multimesh.set_instance_transform_2d(idx, transform)
		
		# Set the color for this instance, modulating alpha based on ooze depth.
		var color: Color = ooze_color
		# The alpha is proportional to the ooze depth. Here, it reaches full opacity at half the max depth.
		color.a = clamp(depth / (max_ooze_per_tile / 2.0), ooze_min_alpha, ooze_max_alpha)
		multimesh.set_instance_color(idx, color)
		
		idx += 1

# -----------------------------------------
# --- Building Destruction ----------------
# -----------------------------------------
## Checks if any buildings are on tiles with ooze and calls the BuildingManager to destroy them.
func _check_for_buildings_on_ooze() -> void:
	# Ensure the BuildingManager is set and valid before proceeding.
	if not is_instance_valid(building_manager):
		return

	var buildings_to_destroy: Array[Building] = []
	# We must get a fresh copy of the buildings array, as the original array might be modified
	# by the destroy() method, which would cause issues while iterating.
	var all_buildings: Array[Building] = building_manager.get("buildings").duplicate()

	# Iterate over all buildings to check their position against the ooze map.
	for building in all_buildings:
		if not is_instance_valid(building):
			continue

		var building_tile_coord: Vector2i = ooze_tilemap_layer.local_to_map(building.global_position)
		# If a building is on a tile that has ooze, add it to the destruction list.
		if ooze_map.has(building_tile_coord):
			buildings_to_destroy.append(building)
	
	# If there are buildings to destroy, call the manager to handle their removal.
	if not buildings_to_destroy.is_empty():
		#building_manager.call("destroy_buildings", buildings_to_destroy)
		building_manager.destroy_buildings(buildings_to_destroy)
