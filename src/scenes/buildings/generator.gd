# -------------------------------
# Generator.gd
# -------------------------------
# Small generator that produces extra energy for the command center
# Network-only: only connects to normal relays, never moves
class_name EnergyGenerator extends Building

@onready var sprite_2d: Sprite2D = $Sprite2D

# Amount of extra packet regeneration this generator provides
@export var packet_production_bonus: float = 5.0


# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready():
	super._ready()
	add_to_group("generators")


# Called by CC on tick used to calc total packet production
func get_packet_production_bonus() -> float:
	return packet_production_bonus


func _updates_visuals() -> void:
	# Color the sprite based on whether the relay is built
	# maybe change something if unpowered
	if is_built:
		# Built relay: full color
		sprite_2d.modulate = Color(1, 1, 1, 1)
	else:
		# Not built: dimmed / greyed out
		sprite_2d.modulate = Color(0.5, 0.5, 0.5, 1)
