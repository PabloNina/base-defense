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




func _physics_process(delta: float) -> void:
	if is_moving:
		_move_towards_target(delta)


func start_move(target_pos: Vector2) -> void:
	if not is_built:
		return

	move_target_position = target_pos
	is_built = false
	is_powered = false
	is_supplied = false

	is_moving = true
	_updates_visuals()

	network_manager.unregister_relay(self)
	#building_manager.unregister_building(self)


func _move_towards_target(delta: float) -> void:
	var dir = (move_target_position - global_position)
	var dist = dir.length()

	if dist < 1.0:
		_complete_move()
	else:
		global_position += dir.normalized() * move_speed * delta


func _complete_move() -> void:
	is_moving = false
	is_built = true
	# re-register to managers if needed
	network_manager.register_relay(self)
	#land
	#_updates_visuals()
	
