# -------------------------------
# MovableBuilding.gd
# -------------------------------
# Base class for movable buildings connected to the network.
# Extends building for network integration.
class_name MovableBuilding extends Building
# -----------------------------------------
# -------- Signals -----------------------
# -----------------------------------------
signal move_started(building: MovableBuilding, landing_position: Vector2)
signal move_completed(building: MovableBuilding)
# -----------------------------------------
# -------- Move State Variables -----------
# -----------------------------------------
var is_moving: bool = false
var landing_target_position: Vector2 = Vector2.ZERO
var move_speed: float = 100.0

# -----------------------------------------
# ------------ Engine Callbacks -----------
# -----------------------------------------
func _physics_process(delta: float) -> void:
	if is_moving:
		_move_towards_target(delta)

# -----------------------------------------
# -------- Move State Methods -------------
# -----------------------------------------
func start_move(target_pos: Vector2) -> void:
	if not is_built:
		return
	
	landing_target_position = target_pos
	is_built = false
	is_powered = false

	move_started.emit(self, landing_target_position)
	
	is_moving = true
	#_updates_visuals()
	reset_packets_in_flight()

	# Unregister for clearing connections and packet demand/production during move 
	grid_manager.unregister_relay(self)

func _move_towards_target(delta: float) -> void:
	var dir = (landing_target_position - global_position)
	var dist = dir.length()

	if dist < 1.0:
		_complete_move()
	else:
		global_position += dir.normalized() * move_speed * delta


func _complete_move() -> void:
	is_moving = false
	is_built = true
	# re-register to managers if needed
	grid_manager.register_relay(self)
	#land
	move_completed.emit(self)
	#_updates_visuals()
	

func get_available_actions() -> Array[GlobalData.BUILDING_ACTIONS]:
	# Start with the parent class's actions
	var actions: Array[GlobalData.BUILDING_ACTIONS] = super.get_available_actions()
	# Add the actions specific to this class
	actions.append(GlobalData.BUILDING_ACTIONS.MOVE)
	return actions
