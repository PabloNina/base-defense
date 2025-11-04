# =========================================
# connection_line_pool.gd
# =========================================
# Manages a pool of reusable ConnectionLine objects to optimize performance
# by avoiding frequent instantiation and destruction.
class_name ConnectionLinePool extends Node
# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
## The initial size of the pool.
@export var pool_size: int = 60
## The value to increment pool_size each time the pool goes empty.
@export var pool_grow_value: int = 10
# -----------------------------------------
# --- Runtime Data ------------------------
# -----------------------------------------
# The pool of available ConnectionLine objects.
var connection_line_pool: Array[ConnectionLine] = []
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Pre-populate the pool with ConnectionLine instances.
	_populate_pool(pool_size)

# ---------------------------------
# --- Private Methods -------------
# ---------------------------------
# Pre-instantiates a number of Connectionlines to have them ready for use.
func _populate_pool(size: int) -> void:
	for i in range(size):
		var connection_line: ConnectionLine = GlobalData.CONNECTION_LINE_SCENE.instantiate()
		# Disable the ConnectionLine and add it to the pool.
		connection_line.visible = false
		connection_line_pool.append(connection_line)
		add_child(connection_line)

# ---------------------------------
# --- Public Methods --------------
# ---------------------------------
# Retrieves a ConnectionLine from the pool and returns it. 
# If the pool is empty it creates more.
func get_connection_line() -> ConnectionLine:
	# Add more ConnectionLines if the pool runs dry.
	# This makes the pool grow dynamically as needed.
	if connection_line_pool.is_empty():
		print("ConnectionLine pool empty. Growing pool!")
		_populate_pool(pool_grow_value)

	# Get a ConnectionLine from the front of the pool.
	var connection_line: ConnectionLine = connection_line_pool.pop_front()
	
	# The ConnectionLine is a child of the pool, remove it before handing it out.
	if connection_line.get_parent() == self:
		remove_child(connection_line)

	# Enable the ConnectionLine
	connection_line.visible = true

	return connection_line


# Returns a ConnectionLine to the pool so it can be reused.
func return_connection_line(connection_line: ConnectionLine) -> void:
	if not is_instance_valid(connection_line):
		return
		
	# Disable the ConnectionLine.
	connection_line.visible = false
	
	# Reparent the ConnectionLine back to the pool to keep the scene tree clean.
	if connection_line.get_parent() != self:
		connection_line.get_parent().remove_child(connection_line)
		add_child(connection_line)
	
	# Add ConnectionLine back to the pool
	connection_line_pool.append(connection_line)
