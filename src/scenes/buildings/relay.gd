class_name EnergyRelay extends Building

@onready var sprite_2d: Sprite2D = $Sprite2D

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready():
	super._ready()
	add_to_group("relays")

func _updates_visuals():
	# Color the sprite based on whether the relay is built
	# maybe change something if unpowered
	if is_built:
		# Built relay: full color
		sprite_2d.modulate = Color(1, 1, 1, 1)
	else:
		# Not built: dimmed / greyed out
		sprite_2d.modulate = Color(0.5, 0.5, 0.5, 1)
