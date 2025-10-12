extends Relay

@onready var base_sprite: Sprite2D = $BaseSprite
@onready var turret_sprite: Sprite2D = $TurretSprite

func _update_power_visual():
		# Color the sprite based on whether the relay is built
	# and optionally change alpha/brightness if unpowered
	if is_built:
		# Built relay: full color
		base_sprite.modulate = Color(1, 1, 1, 1)
		turret_sprite.modulate = Color(1, 1, 1, 1)
	else:
		# Not built: dimmed / greyed out
		base_sprite.modulate = Color(0.5, 0.5, 0.5, 1)
		turret_sprite.modulate = Color(0.5, 0.5, 0.5, 1)
		
	#if base_sprite == null and turret_sprite == null:
		#return
	#base_sprite.modulate = Color(1.0, 1.0, 1.0) if is_powered else Color(1.0, 0.3, 0.3)
	#turret_sprite.modulate = Color(1.0, 1.0, 1.0) if is_powered else Color(1.0, 0.3, 0.3)
