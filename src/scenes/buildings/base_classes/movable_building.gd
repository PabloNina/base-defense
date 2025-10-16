# -------------------------------
# MovableWeapon.gd
# -------------------------------
# Base class for movable buildings connected to the network.
# Extends building for network integration.
class_name MovableBuilding extends Building


# -----------------------------------------
# ------------ Move Mode ------------------
# -----------------------------------------
var is_moving: bool = false
var move_target_position: Vector2 = Vector2.ZERO
var move_speed: float = 100.0



func _move_towards_target(delta: float) -> void:
	var dir = (move_target_position - global_position)
	var dist = dir.length()

	if dist < 2.0:
		_complete_move()
	else:
		global_position += dir.normalized() * move_speed * delta

func _complete_move() -> void:
	is_moving = false
	is_built = true
	# re-register to managers if needed
	if building_manager:
		building_manager.rebuild_relay(self)
	_updates_visuals()
