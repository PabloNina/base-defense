extends Relay

@onready var sprite_2d: Sprite2D = $Sprite2D

func _update_power_visual():
	if not sprite_2d:
		return
	sprite_2d.modulate = Color(1.0, 1.0, 1.0) if is_powered else Color(1.0, 0.3, 0.3)
