# -------------------------------
# EnergyGenerator.gd
# -------------------------------
# Small generator that produces extra energy for the command center
# Network-only: only connects to normal relays, never moves
class_name EnergyGenerator
extends Relay

@onready var sprite_2d: Sprite2D = $Sprite2D

# Amount of extra energy regeneration this generator provides
@export var energy_bonus: int = 5

func _ready():
	# call base _ready to register with network
	super._ready()


# Function to add energy to command center if connected
func provide_energy_bonus():
	if not is_powered or not is_built:
		return

	#print("GENERATOR ACTIVE:", name)  # ✅ Debug: confirm it runs
	# Find the Command Center in this network
	var nm := get_tree().get_first_node_in_group("network_manager")
	if nm == null:
		print("❌ No network_manager found")
		return

	# Find any Command Center reachable from this generator
	for relay in nm.relays:
		if relay is Command_Center and nm.are_connected(relay, self):
			var cc := relay as Command_Center
			cc.generators_regen_rate += energy_bonus # Boost regen rate temporarily for this tick
			return  # Only one CC per network, so we can stop here


func _updates_visuals():
	# Color the sprite based on whether the relay is built
	# maybe change something if unpowered
	if is_built:
		# Built relay: full color
		sprite_2d.modulate = Color(1, 1, 1, 1)
	else:
		# Not built: dimmed / greyed out
		sprite_2d.modulate = Color(0.5, 0.5, 0.5, 1)
