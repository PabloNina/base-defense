# connection_line.gd
class_name ConnectionLine extends Node2D

@onready var line_2d: Line2D = $Line2D

var building_a: Building
var building_b: Building

# Sets up the connection line between two buildings.
func setup(b_a: Building, b_b: Building):
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
	# If either building is powered, the line is blue (active). Otherwise, it's red (inactive).
	line_2d.default_color = Color(0.3, 0.9, 1.0) if (a_powered or b_powered) else Color(1, 0.3, 0.3)

# Destroys the connection line.
func destroy():
	queue_free()
