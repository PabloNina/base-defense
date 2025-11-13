class_name EnemyManager extends Node
# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
## Used for coordinate conversion and getting tile size.
@export var enemy_map_layer: TileMapLayer
## Determines how quickly ooze spreads. A higher value means faster flow.
@export var flow_rate: float = 0.25
## Ooze levels below this threshold are removed to optimize performance.
@export var min_ooze_threshold: float = 0.01
## The maximum amount of ooze that can accumulate on a single tile.
@export var max_ooze_per_tile: float = 100.0
## The color of the ooze. The alpha component will be updated based on depth.
@export var ooze_color: Color = Color.PURPLE

# -----------------------------------------
# --- Private Variables -------------------
# -----------------------------------------
# A dictionary mapping tile coordinates (Vector2i) to ooze depth (float).
# This stores the core simulation data, separate from the visuals.
var ooze_map: Dictionary = {}
# The MultiMeshInstance used to render all ooze visuals in a single draw call.
# This is highly performant as it avoids managing thousands of individual nodes.
var _multimesh_instance: MultiMeshInstance2D
# The MultiMesh resource that holds the geometry and instance data for rendering.
var _multimesh: MultiMesh

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Add to group for easy access from other nodes (like emitters).
	add_to_group("enemy_manager")
	# Programmatically create and configure the MultiMesh for rendering ooze.
	_setup_multimesh()

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
func add_ooze(tile_coord: Vector2i, amount: float) -> void:
	var current_ooze: float = ooze_map.get(tile_coord, 0.0)
	# Add the new amount and ensure it does not exceed the maximum allowed value.
	var new_ooze_amount: float = clamp(current_ooze + amount, 0, max_ooze_per_tile)
	ooze_map[tile_coord] = new_ooze_amount

# --------------------------------------------------
# ---------------- Private Methods -----------------
# --------------------------------------------------

# -----------------------------------------
# --- Multimesh Setup ---------------------
# -----------------------------------------
## Sets up the MultiMeshInstance2D node and the MultiMesh resource programmatically.
## This is called once when the manager is ready.
func _setup_multimesh() -> void:
	# Create the node that will render our multimesh.
	_multimesh_instance = MultiMeshInstance2D.new()
	# Create the multimesh resource itself.
	_multimesh = MultiMesh.new()
	_multimesh_instance.multimesh = _multimesh
	add_child(_multimesh_instance)

	# Configure the multimesh resource.
	# We need Transform (position, rotation, scale) and Color data for each instance.
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_colors = true
	
	# Create a simple quad mesh to represent the ooze on a single tile.
	# All instances in the multimesh will share this same mesh geometry.
	var quad_mesh := QuadMesh.new()
	var tile_size: Vector2 = enemy_map_layer.tile_set.tile_size
	quad_mesh.size = tile_size
	_multimesh.mesh = quad_mesh

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
		var neighbors: Array[Vector2i] = enemy_map_layer.get_surrounding_cells(tile_coord)
		var total_flow_out: float = 0.0

		for neighbor_coord in neighbors:
			var neighbor_ooze: float = ooze_map.get(neighbor_coord, 0.0)

			# Ooze only flows from a tile with more ooze to one with less.
			if current_ooze > neighbor_ooze:
				var diff: float = current_ooze - neighbor_ooze
				# The amount of flow is proportional to half the difference, which creates a stable equalization effect.
				# Multiplying by 'delta' makes the flow rate independent of the frame rate.
				var flow_amount: float = (diff / 2.0) * flow_rate * delta
				
				# Precaution: ensure we don't try to flow more ooze than is available on the current tile.
				flow_amount = min(flow_amount, current_ooze - total_flow_out)
				if flow_amount <= 0:
					continue

				# Record the change in ooze for both the current tile and its neighbor.
				flow_deltas[neighbor_coord] = flow_deltas.get(neighbor_coord, 0.0) + flow_amount
				flow_deltas[tile_coord] = flow_deltas.get(tile_coord, 0.0) - flow_amount
				total_flow_out += flow_amount

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

# -----------------------------------------
# --- Visual Synchronization --------------
# -----------------------------------------
## Updates the MultiMesh to reflect the current state of the `ooze_map`.
## This function is the bridge between the simulation data and the visuals.
func _update_ooze_visuals() -> void:
	var ooze_tile_count: int = ooze_map.size()
	# Set the number of instances to be rendered.
	_multimesh.instance_count = ooze_tile_count

	# If there's no ooze, there's nothing to draw.
	if ooze_tile_count == 0:
		return

	var idx: int = 0
	# Iterate through every tile that has ooze.
	for tile_coord in ooze_map.keys():
		var depth: float = ooze_map[tile_coord]
		
		# Set the position for this instance.
		var position: Vector2 = enemy_map_layer.map_to_local(tile_coord)
		var transform := Transform2D(0.0, position)
		_multimesh.set_instance_transform_2d(idx, transform)
		
		# Set the color for this instance, modulating alpha based on ooze depth.
		var color: Color = ooze_color
		# The alpha is proportional to the ooze depth. Here, it reaches full opacity at half the max depth.
		color.a = clamp(depth / (max_ooze_per_tile / 2.0), 0.1, 1.0)
		_multimesh.set_instance_color(idx, color)
		
		idx += 1
