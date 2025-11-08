# MovableBuilding - movable_building.gd
# ============================================================================
# This is an abstract base class for all buildings in the game that possess
# the ability to be relocated on the game grid after their initial construction.
# It extends the core functionalities provided by the `Building` class,
# adding specific mechanics and states necessary for handling movement.
#
# Key Responsibilities:
# - Movement State Management: Tracks whether a building is currently in motion,
#   its target landing position, and its movement speed.
#
# - Relocation Process: Manages the sequence of events when a building is
#   commanded to move, including temporarily unregistering from the grid,
#   animating its movement, and re-integrating with the grid upon arrival
#   at the new location.
#
# - Grid Re-integration: Ensures that after a move, the building correctly
#   re-establishes its connections and operational status within the energy
#   network.
#
# - Signal Emission: Emits signals to notify other game systems when a move
#   starts and when it successfully completes, allowing for coordinated
#   gameplay responses.
# ============================================================================
@abstract
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
# -------- Public Methods -----------------
# -----------------------------------------
# Called by BuildingManager
func start_move(target_pos: Vector2) -> void:
	if not is_built:
		return
	
	# start moving animation
	landing_target_position = target_pos
	is_built = false
	is_powered = false

	move_started.emit(self, landing_target_position)

	is_moving = true
	reset_packets_in_flight()

	# Unregister for clearing connections and packet demand/production during move 
	grid_manager.unregister_to_grid(self)

# -----------------------------------------
# -------- Private Methods ----------------
# -----------------------------------------
# Called in _physics_process if is_moving flag is turned on
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
	# re-register to managers
	grid_manager.register_to_grid(self)
	# land animation
	move_completed.emit(self)
	
