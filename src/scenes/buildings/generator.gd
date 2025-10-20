# -------------------------------
# EnergyGenerator.gd
# -------------------------------
# Small generator that produces extra energy for the command center
# Network-only: only connects to normal relays, never moves
class_name EnergyGenerator extends Building

@onready var sprite_2d: Sprite2D = $Sprite2D

# Amount of extra packet regeneration this generator provides
@export var packet_production_bonus: int = 5


# Function to add packets to command center if connected
func add_packet_production_bonus():
	if not is_powered or not is_built:
		return

	if network_manager == null:
		print("No network_manager found")
		return

	# Find any Command Center reachable from this generator
	for building in network_manager.registered_buildings:
		if building is Command_Center and network_manager.are_connected(building, self):
			var cc := building as Command_Center
			cc.generators_production_bonus += packet_production_bonus # Boost regen rate temporarily for this tick
			return  # if Only one CC per network we can stop here


func _updates_visuals():
	# Color the sprite based on whether the relay is built
	# maybe change something if unpowered
	if is_built:
		# Built relay: full color
		sprite_2d.modulate = Color(1, 1, 1, 1)
	else:
		# Not built: dimmed / greyed out
		sprite_2d.modulate = Color(0.5, 0.5, 0.5, 1)
