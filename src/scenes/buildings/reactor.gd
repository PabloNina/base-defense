class_name Reactor extends Building
# -----------------------------------------
# --- Onready Variables -------------------
# -----------------------------------------
@onready var sprite_2d: Sprite2D = $Sprite2D
# -----------------------------------------
# --- Reactor Settings --------------------
# -----------------------------------------
# Amount of extra packet regeneration this generator provides
var packet_production_bonus: float = 0.0
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready():
	super._ready()
	add_to_group("reactors")
	_config_reactor_settings()

# -----------------------------------------
# --- Public Methods ----------------------
# -----------------------------------------
# Called by CC on tick used to calc total packet production
func get_packet_production_bonus() -> float:
	if is_deactivated:
		return 0.0
	return packet_production_bonus

# -----------------------------------------
# --- Reactor Configuration ---------------
# -----------------------------------------
func _config_reactor_settings() -> void:
	packet_production_bonus = GlobalData.get_packet_production_bonus(building_type)

# -------------------------------
# --- Visuals Updating ----------
# -------------------------------
func _update_is_built_visuals() -> void:
	# Color the sprite based on whether the relay is built
	# maybe change something if unpowered
	if is_built:
		# Built relay: full color
		sprite_2d.modulate = Color(1, 1, 1, 1)
	else:
		# Not built: dimmed / greyed out
		sprite_2d.modulate = Color(0.5, 0.5, 0.5, 1)
