class_name Relay extends Building
# -----------------------------------------
# --- Onready Variables -------------------
# -----------------------------------------
@onready var sprite_2d: Sprite2D = $Sprite2D
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready():
	super._ready()
	add_to_group("relays")

# -------------------------------
# --- Visuals Updating ----------
# -------------------------------
func _update_is_built_visuals():
	# Color the sprite based on whether the relay is built
	if is_built:
		# Built relay: full color
		sprite_2d.modulate = Color(1, 1, 1, 1)
	else:
		# Not built: dimmed / greyed out
		sprite_2d.modulate = Color(0.5, 0.5, 0.5, 1)
