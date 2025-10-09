extends Relay

@onready var base_sprite: Sprite2D = $BaseSprite
@onready var turret_sprite: Sprite2D = $TurretSprite

func _update_power_visual():
	if base_sprite == null and turret_sprite == null:
		return
	base_sprite.modulate = Color(1.0, 1.0, 1.0) if is_powered else Color(1.0, 0.3, 0.3)
	turret_sprite.modulate = Color(1.0, 1.0, 1.0) if is_powered else Color(1.0, 0.3, 0.3)
