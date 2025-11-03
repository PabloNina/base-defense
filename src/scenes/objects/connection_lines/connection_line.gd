# =========================================
# connection_line.gd
# =========================================
# add description
class_name ConnectionLine extends Node2D

const PREVIEW_LINE_COLOR: Color = Color(0.2, 1.0, 0.0, 0.6)
const PREVIEW_LINE_INVALID_COLOR: Color = Color(1.0, 0.2, 0.2, 0.6)

@onready var line_2d: Line2D = $Line2D

var building_a: Building
var building_b: Building

# Sets up the connection line between two buildings.
func setup_connection(b_a: Building, b_b: Building):
	building_a = b_a
	building_b = b_b
	# Set the points of the Line2D to the global positions of the buildings.
	line_2d.points = [building_a.global_position, building_b.global_position]

# Updates the color of the connection line based on the power status of the connected buildings.
func update_power_status(powered_map: Dictionary):
	if not is_instance_valid(building_a) or not is_instance_valid(building_b):
		return
		
	var a_powered = powered_map.get(building_a, false)
	var b_powered = powered_map.get(building_b, false)
	# If either building is powered, the line is green (active). Otherwise, it's red (inactive).
	line_2d.default_color = PREVIEW_LINE_COLOR if (a_powered or b_powered) else PREVIEW_LINE_INVALID_COLOR

# Sets up the line for preview purposes.
func setup_preview(start_pos: Vector2, end_pos: Vector2, is_valid: bool):
	# We don't have buildings here, so we can't use building_a/b.
	# This method will just set the line's points and color.
	line_2d.points = [start_pos, end_pos]
	line_2d.global_position = Vector2.ZERO # The line is a child of the ConnectionLine Node2D, which is positioned at the container's origin.
	line_2d.default_color = PREVIEW_LINE_COLOR if is_valid else PREVIEW_LINE_INVALID_COLOR
