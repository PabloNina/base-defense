class_name GunTurret extends MovableBuilding

@onready var base_sprite: Sprite2D = $BaseSprite
@onready var turret_sprite: Sprite2D = $TurretSprite


func _updates_visuals():
	# Color the sprite based on whether the relay is built
	# TO DO: change something if unpowered or unsupplied
	if is_built:
		# Built relay: full color
		base_sprite.modulate = Color(1, 1, 1, 1)
		turret_sprite.modulate = Color(1, 1, 1, 1)
	else:
		# Not built: dimmed / greyed out
		base_sprite.modulate = Color(0.5, 0.5, 0.5, 1)
		turret_sprite.modulate = Color(0.5, 0.5, 0.5, 1)
