# -------------------------------
# MovableWeapon.gd
# -------------------------------
# Base class for movable weapons connected to the network.
# Extends Relay for network integration.
class_name MovableWeapon
extends Relay

@onready var base_sprite: Sprite2D = $BaseSprite
@onready var turret_sprite: Sprite2D = $TurretSprite

#Weapon stats
@export var attack_damage: int = 10
@export var attack_range: float = 100.0
@export var fire_rate: float = 1.0


func _ready():
	# call base _ready to register with network
	super._ready()

# Example attack function
func attack(target: Node2D):
	if not is_powered or not is_built or not is_supplied:
		return
	print("Firing at target ", target.name)

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
