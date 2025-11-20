# GhostPreview - ghost_preview.gd
# ============================================================================
# This script manages the visual representation of a building during the
# placement phase. It displays a semi-transparent "ghost" of the building
# along with visual indicators for its potential connections and operational
# range. It also determines and communicates the validity of the current
# placement location.
#
# Key Responsibilities:
# - Visual Feedback: Renders a semi-transparent preview of the building,
#   its connection lines to existing structures, and its operational range
#   (e.g., fire range for turrets).
#
# - Placement Validation: Utilizes Area2D for overlap detection to ensure
#   the proposed placement does not conflict with other objects or invalid
#   terrain.
#
# - Status Communication: Emits signals to inform the BuildingManager about
#   the current placement validity, allowing for appropriate UI responses.
#
# - Dynamic Updates: Continuously updates its position and visual feedback
#   as the player moves the ghost preview around the grid.
# ============================================================================
class_name GhostPreview extends Node2D
# --------------------------------------------
# --- Signals --------------------------------
# --------------------------------------------
## Emitted when placement validity changes passing itself for identification.
## Listener BuildingManager
signal is_placeable(is_valid: bool, preview: GhostPreview)
# --------------------------------------------
# --- Onready References ---------------------
# --------------------------------------------
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D
@onready var connection_lines_container: Node = $ConnectionLinesContainer
# --------------------------------------------
# --- Preview Configuration ------------------
# --------------------------------------------
# The type of building this preview represents.
var building_type: GlobalData.BUILDING_TYPE = GlobalData.BUILDING_TYPE.NULL
# Manager references for checking connections and ooze.
var grid_manager: GridManager
var flow_manager: FlowManager
# Reference to TileMap ground layer and buildable tile for placement validity
var ground_layer: TileMapLayer
var buildable_tile_id: int = 0
var is_on_buildable_tile: bool = true
# The size of the building's footprint in tile units (e.g., 1x1, 2x2).
var building_size_in_tiles: Vector2i = Vector2i.ONE
var is_valid: bool = true
# Keeps track of overlapping placement-blocking areas.
var overlapping_areas: Array[Area2D] = []
# Pool of Line2D nodes for drawing connection previews.
var ghost_lines: Array[ConnectionLine] = []
# Tracks if the preview has been configured.
var is_initialized: bool = false
var show_visual_feedback: bool = true

# --------------------------------------------
# --- Engine Callbacks -----------------------
# --------------------------------------------
func _draw() -> void:
	if not show_visual_feedback:
		return

	# Draws the weapon's fire range by highlighting individual tiles.
	_draw_fire_range_tiles()
	
	# Draws the validity box around the building
	var texture = sprite.texture
	if texture:
		var rect: Rect2
		rect.size = texture.get_size()
		rect.position = -rect.size / 2
		var color = GlobalData.BOX_VALID_COLOR if is_valid else GlobalData.BOX_INVALID_COLOR
		draw_rect(rect.grow(4), color, false, 2.0)

# --------------------------------------------
# --- Public Methods -------------------------
# --------------------------------------------
# Returns whether the preview has been initialized.
# Called by BuildingManager
func is_ghost_preview_initialized() -> bool:
	return is_initialized

# Initializes the preview's properties.
# Called by BuildingManager
func initialize_ghost_preview(p_building_type: GlobalData.BUILDING_TYPE, p_grid_manager: GridManager, p_texture: Texture2D, p_ground_layer: TileMapLayer, p_buildable_tile_id: int, p_show_feedback: bool = true) -> void:
	building_type = p_building_type
	grid_manager = p_grid_manager
	sprite.texture = p_texture
	ground_layer = p_ground_layer
	buildable_tile_id = p_buildable_tile_id
	show_visual_feedback = p_show_feedback
	
	# Get a reference to the FlowManager to check for ooze.
	flow_manager = get_tree().get_first_node_in_group("enemy_manager")
	
	# Return if texture is not valid
	if not sprite.texture:
		return
	
	# Calculate the building's footprint size in tile units.
	# This is crucial for ensuring multi-tile buildings are placed correctly.
	if ground_layer and sprite.texture:
		var tile_size = ground_layer.tile_set.tile_size
		var scaled_texture_size = sprite.texture.get_size() * sprite.scale
		building_size_in_tiles = Vector2i(
			ceil(scaled_texture_size.x / tile_size.x),
			ceil(scaled_texture_size.y / tile_size.y)
		)
		
	# Configure collision shape based on texture size
	var shape_size = sprite.texture.get_size() * sprite.scale
	collision_shape.shape.size = shape_size
	
	# Ensure collision is enabled
	collision_shape.set_deferred("disabled", false)
	
	is_initialized = true
	_update_validity()

# Updates the preview's position and redraws connection lines.
# Called by BuildingManager
func update_ghost_preview_position(new_position: Vector2) -> void:
	global_position = new_position

	if ground_layer:
		# Check if the entire building footprint is on valid ground.
		is_on_buildable_tile = _is_footprint_on_buildable_tiles()
	
	_update_validity()

# Hides and resets the preview.
# Called by BuildingManager
func clear_ghost_preview() -> void:
	building_type = GlobalData.BUILDING_TYPE.NULL
	if sprite:
		sprite.texture = null
	visible = false
	overlapping_areas.clear()
	if grid_manager:
		_clear_ghost_lines()
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	# Clear the fire range circle.
	queue_redraw()
	is_initialized = false

# --------------------------------------------
# --- Area2D Signal Handling -----------------
# --------------------------------------------
# Called when another area enters the preview's detection box.
func _on_area_entered(area: Area2D) -> void:
	overlapping_areas.append(area)
	_update_validity()

# Called when an area leaves the preview's detection box.
func _on_area_exited(area: Area2D) -> void:
	overlapping_areas.erase(area)
	_update_validity()

# --------------------------------------------
# --- Validity Update / Visual Feedback ------
# --------------------------------------------
# Checks if every tile under the building's footprint is a valid buildable tile
# AND that all tiles are on the same ground level.
func _is_footprint_on_buildable_tiles() -> bool:
	# Cannot perform check if the ground layer or sprite texture is missing.
	if not ground_layer or not sprite.texture:
		return false

	# Step 1: Determine the top-left corner of the building's footprint in the tilemap.
	var texture_size = sprite.texture.get_size() * sprite.scale
	var top_left_global_pos = global_position - texture_size / 2.0
	var top_left_tile = ground_layer.local_to_map(top_left_global_pos)

	# This will be used to store the terrain ID of the first tile.
	# Initialize to -2 to ensure it's different from any valid terrain ID (which start at -1).
	var first_tile_terrain_id: int = -2

	# Step 2: Iterate through each tile within the building's footprint.
	for y in range(building_size_in_tiles.y):
		for x in range(building_size_in_tiles.x):
			var tile_to_check = top_left_tile + Vector2i(x, y)
			
			# Step 3: Check for ooze. Buildings cannot be placed on ooze.
			if is_instance_valid(flow_manager) and flow_manager.has_ooze_on_tile(tile_to_check):
				return false # Invalid: Tile is covered in ooze.
			
			# Step 4: Check if the tile is of the correct buildable type using its source ID.
			# If the source ID is -1, the cell is empty.
			var source_id: int = ground_layer.get_cell_source_id(tile_to_check)
			if source_id != buildable_tile_id:
				return false # Invalid: Not a buildable tile type (e.g., wall, or empty space).

			# Step 5: Get the TileData to check the terrain for the ground level.
			var tile_data: TileData = ground_layer.get_cell_tile_data(tile_to_check)
			
			# This is an extra safeguard. The source_id check should already handle empty tiles.
			if not tile_data:
				return false

			# Step 6: Check if the tile is on the same level as the others using its terrain ID.
			var current_terrain_id: int = tile_data.terrain
			
			if x == 0 and y == 0:
				# For the very first tile, store its terrain ID as the reference.
				first_tile_terrain_id = current_terrain_id
			else:
				# For all subsequent tiles, compare their terrain ID to the first one.
				if current_terrain_id != first_tile_terrain_id:
					return false # Invalid: This tile is on a different ground level.

	# If we get here, all tiles are of the buildable type and on the same level.
	return true

# Draws the weapon's fire range by highlighting individual tiles.
# This creates a "blocky" and accurate visual representation of the range.
# It can be adjusted with new rules and colors in GlobalData.
func _draw_fire_range_tiles() -> void:
	# Retrieve the effective fire range of the building this ghost represents.
	var fire_range = GlobalData.get_fire_range(building_type)
	# If there's no fire range or the ground layer isn't valid, there's nothing to draw.
	if fire_range <= 0 or not is_instance_valid(ground_layer):
		return

	# Get the targeting rule to determine how different heights affect validity.
	var targeting_rule = GlobalData.get_targeting_rule(building_type)
	# Obtain the size of a single tile from the ground layer's tile set.
	var tile_size = ground_layer.tile_set.tile_size
	# Calculate the maximum number of tiles to check in any direction based on fire range.
	# We add 1 to ensure the full extent of the range is covered, even partially.
	var range_in_tiles = int(ceil(fire_range / tile_size.x)) + 1
	
	# Convert the ghost preview's global position to its local position within the TileMap.
	var ghost_pos_in_map_space = ground_layer.to_local(global_position)
	# Determine the tile coordinate where the center of the ghost preview is located.
	var origin_tile_coord = ground_layer.local_to_map(ghost_pos_in_map_space)
	
	# Initialize origin_height to -1 (an invalid height) and calculate if a height-based
	# targeting rule is active. This will be used to compare against target tile heights.
	var origin_height = -1
	if targeting_rule == GlobalData.WEAPON_TARGETING_RULE.SAME_OR_LOWER_HEIGHT:
		var origin_tile_data: TileData = ground_layer.get_cell_tile_data(origin_tile_coord)
		if origin_tile_data:
			origin_height = GlobalData.get_height_from_terrain_id(origin_tile_data.terrain)

	# Iterate through a square grid of tiles around the origin tile.
	for y_offset in range(-range_in_tiles, range_in_tiles + 1):
		for x_offset in range(-range_in_tiles, range_in_tiles + 1):
			# Calculate the current tile's coordinate in the tilemap grid.
			var tile_coord = origin_tile_coord + Vector2i(x_offset, y_offset)
			
			# Get the local position of the tile's center within the TileMap.
			# As per user's clarification, `map_to_local` returns the center for these tiles.
			var tile_center_in_map_space = ground_layer.map_to_local(tile_coord)
			
			# Check if the distance from the ghost's center to the current tile's center
			# exceeds the fire range. If so, this tile is out of range.
			if ghost_pos_in_map_space.distance_to(tile_center_in_map_space) > fire_range:
				continue # Skip to the next tile.
			
			# Check if the tile is a buildable type. If not, it's not a valid target.
			var source_id: int = ground_layer.get_cell_source_id(tile_coord)
			if source_id != buildable_tile_id:
				continue # Skip to the next tile.
				
			# Retrieve TileData to check terrain properties.
			var target_tile_data: TileData = ground_layer.get_cell_tile_data(tile_coord)
			# If there's no tile data, skip it.
			if not target_tile_data:
				continue
			
			# Calculate the drawing position of the tile relative to the ghost preview's origin.
			# This transforms the tile's center (in tilemap space) to be relative to the ghost.
			var draw_pos = ground_layer.map_to_local(tile_coord) - ghost_pos_in_map_space 

			# Default color is for valid tiles (same height).
			var color_to_draw = GlobalData.FIRE_RANGE_SAME_HEIGHT_COLOR
			# Apply height-based targeting rules if applicable.
			if targeting_rule == GlobalData.WEAPON_TARGETING_RULE.SAME_OR_LOWER_HEIGHT:
				var target_height = GlobalData.get_height_from_terrain_id(target_tile_data.terrain)
				
				# If the target tile is higher than the origin, mark it as an invalid target (red).
				if origin_height != -1 and target_height > origin_height:
					color_to_draw = GlobalData.FIRE_RANGE_COLOR
			
			# Create a Rect2 for drawing. The position needs to be adjusted because `draw_rect`
			# expects the top-left corner, but `draw_pos` currently points to the center
			# of where the tile should be drawn (relative to the ghost's origin).
			var rect = Rect2(draw_pos - (Vector2(tile_size) / 2.0), tile_size)
			draw_rect(rect, color_to_draw)

func _update_validity() -> void:
	is_valid = overlapping_areas.is_empty() and is_on_buildable_tile
	is_placeable.emit(is_valid, self)
	
	if show_visual_feedback:
		_update_connection_ghosts()
		queue_redraw()
	else:
		_clear_ghost_lines()

# --------------------------------------------
# --- Connection Previews Update&Cleanup -----
# --------------------------------------------
# Updates the visibility and position of connection lines to nearby buildings.
func _update_connection_ghosts() -> void:
	if building_type == GlobalData.BUILDING_TYPE.NULL or not is_visible():
		_clear_ghost_lines()
		return
	if not grid_manager:
		return

	var targets: Array = []
	for other in grid_manager.registered_buildings:
		if not is_instance_valid(other):
			continue
		if grid_manager.can_buildings_connect(
			building_type,
			global_position,
			GlobalData.get_is_relay(building_type),
			other.building_type,
			other.global_position,
			other.is_relay
		):
			targets.append(other)

	# Get more lines from the pool if needed.
	while ghost_lines.size() < targets.size():
		var line: ConnectionLine = grid_manager.get_connection_line_from_pool()
		connection_lines_container.add_child(line)
		ghost_lines.append(line)

	# Return excess lines to the pool.
	while ghost_lines.size() > targets.size():
		var line: ConnectionLine = ghost_lines.pop_back()
		grid_manager.return_connection_line_to_pool(line)

	# Update the visible lines.
	for i in range(targets.size()):
		var line: ConnectionLine = ghost_lines[i]
		var target = targets[i]
		line.setup_preview_connections(global_position, target.global_position, is_valid)


# Frees the Line2D nodes and clears the line array.
func _clear_ghost_lines() -> void:
	for line in ghost_lines:
		grid_manager.return_connection_line_to_pool(line)
	ghost_lines.clear()
