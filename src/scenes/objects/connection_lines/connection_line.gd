# ConnectionLine - connection_line.gd
# ============================================================================
# This script manages the visual representation of a connection between two
# buildings. It uses a Line2D node to draw a line from one building to another,
# providing immediate visual feedback on the grid's status.
#
# Key Responsibilities:
# - Drawing Connections: Establishes a visual line between two specified
#   Building nodes.
#
# - Status Updates: Changes color to reflect the power status of the
#   connection. A green line indicates that at least one of the connected
#   buildings is powered, while a red line indicates that neither is.
#
# - Preview Display: Functions as a visual aid during building placement,
#   showing potential connections and their validity before a building is
#   officially placed.
# ============================================================================
class_name ConnectionLine extends Node2D
# --------------------------------------------
# --- Onready References ---------------------
# --------------------------------------------
@onready var line_2d: Line2D = $Line2D
# --------------------------------------------
# --- Line Configuration ---------------------
# --------------------------------------------
var building_a: Building
var building_b: Building

# --------------------------------------------
# --- Public Methods / Set&Update Lines ------
# --------------------------------------------
# Sets up the connection line between two buildings.
# Called by GridManager
func setup_connection(point_a: Building, point_b: Building):
	building_a = point_a
	building_b = point_b
	# Set the points of the Line2D to the global positions of the buildings.
	line_2d.points = [building_a.global_position, building_b.global_position]

# Updates the color of the connection line based on the power status of the connected buildings.
# Called by GridManager
func update_connection_status(powered_map: Dictionary):
	if not is_instance_valid(building_a) or not is_instance_valid(building_b):
		return
	var a_powered = powered_map.get(building_a, false)
	var b_powered = powered_map.get(building_b, false)
	# If either building is powered the line is green (active). Otherwise its red (inactive).
	if (a_powered or b_powered):
		line_2d.default_color = GlobalData.LINE_VALID_COLOR
	else:
		line_2d.default_color = GlobalData.LINE_INVALID_COLOR

# Sets up the line for preview purposes.
# Used by BuildingManager and GhostPreview
func setup_preview_connections(start_pos: Vector2, end_pos: Vector2, is_valid: bool):
	# We dont have buildings here so we cant use building_a/b.
	# This method will just set the lines points and color.
	line_2d.points = [start_pos, end_pos]
	# The line is a child of the ConnectionLine Node2D which is positioned at the containers origin.
	line_2d.global_position = Vector2.ZERO 
	# Change color if preview placement is not valid
	if is_valid:
		line_2d.default_color = GlobalData.LINE_VALID_COLOR
	else:
		line_2d.default_color = GlobalData.LINE_INVALID_COLOR
