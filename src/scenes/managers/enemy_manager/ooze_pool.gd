# ObjectPool - object_pool.gd
# ============================================================================
# This script implements an object pooling pattern specifically for objects. 
# Its primary goal is to optimize game performance by minimizing the
# overhead associated with frequently creating and destroying object nodes.
#
# Key Responsibilities:
# - Pre-population: Initializes a pool of object instances at the start of the
#   game, making them ready for immediate use.
#
# - Dynamic Growth: Automatically expands the pool size if all available
#   packets are in use, ensuring a continuous supply without interruption.
#
# - object Acquisition: Provides a method to retrieve a pre-configured object
#   from the pool, initializing it with necessary data (type, speed, path, position).
#
# - object Return: Manages the return of used object objects to the pool,
#   resetting their state and making them available for future reuse.
#
# - Performance Optimization: By recycling object instances, it significantly
#   reduces garbage collection overhead and CPU spikes that would occur from
#   constant node instantiation/deletion, leading to smoother gameplay.
# ============================================================================
class_name OozePool extends Node
# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
## The initial size of the pool.
@export var pool_size: int = 100
## The value to increment pool_size each time the pool goes empty.
@export var pool_grow_value: int = 25
# -----------------------------------------
# --- Runtime Data ------------------------
# -----------------------------------------
# The pool of available objects.
var object_pool: Array[EnemyOoze] = []
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Pre-populate the pool with object instances.
	_populate_pool(pool_size)

# ---------------------------------
# --- Private Methods -------------
# ---------------------------------
# Pre-instantiates a number of object to have them ready for use.
func _populate_pool(size: int) -> void:
	for i in range(size):
		var object: EnemyOoze = GlobalData.ENEMY_OOZE_SCENE.instantiate()
		# Disable the object and add it to the pool.
		object.visible = false
		object_pool.append(object)
		add_child(object)

# -----------------------------------------
# --- Public Methods/Get&Return Objects ---
# -----------------------------------------
# Retrieves a object from the pool. If the pool is empty it creates more.
# Initializes the object with the provided parameters.
# Returns the configured object.
func get_ooze(position: Vector2) -> EnemyOoze:
	# Add more objects if the pool runs dry.
	# This makes the pool grow dynamically as needed.
	if object_pool.is_empty():
		print("Object pool empty. Growing pool!")
		_populate_pool(pool_grow_value)

	# Get a object from the front of the pool.
	var object: EnemyOoze = object_pool.pop_front()

	# The object is a child of the pool remove it before handing it out.
	if object.get_parent() == self:
		remove_child(object)

	# Initialize the object's properties
	object.global_position = position

	# Enable the object for processing and visibility
	object.visible = true

	return object


# Returns a object back to the pool.
# Disables the object and makes it available for reuse.
func return_ooze(object: EnemyOoze) -> void:
	if not is_instance_valid(object):
		return

	# Disable the object.
	object.visible = false

	# Reparent the object to the pool to keep the scene tree clean.
	if object.get_parent() != self:
		object.get_parent().remove_child(object)
		add_child(object)

	# Add the object back to the pool.
	object_pool.append(object)
