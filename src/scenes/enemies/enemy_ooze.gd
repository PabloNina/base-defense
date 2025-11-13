class_name EnemyOoze extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

## Divisor that determines how much depth is needed for full opacity
@export var full_opacity_depth: float = 10.0

func update_visuals(depth: float) -> void:
	# Sprite is modulated to purple we just need to adjust its alpha.
	# This value can be tweaked to change the ooze appearance.
	var alpha: float = clamp(depth / full_opacity_depth, 0.1, 1.0)
	sprite.modulate.a = alpha
