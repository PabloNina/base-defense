# =========================================
# ConnectionLinePool.gd
# =========================================
# Manages a pool of ConnectionLine objects to reuse them and avoid frequent
# instantiation and freeing, which can cause performance issues.
class_name ConnectionLinePool extends Node

var _pool: Array[ConnectionLine] = []

# Pre-warms the pool with a specified number of instances.
func _ready() -> void:
	_prewarm_pool(20)

# Pre-instantiates a number of lines to have them ready for use.
func _prewarm_pool(size: int) -> void:
	for i in range(size):
		#var line: ConnectionLine = ConnectionLineScene.instantiate()
		var line: ConnectionLine = GlobalData.CONNECTION_LINE_SCENE.instantiate()
		line.visible = false
		add_child(line)
		_pool.append(line)


# Retrieves a line from the pool. If the pool is empty, it creates a new one.
func get_line() -> ConnectionLine:
	if _pool.is_empty():
		_prewarm_pool(5) # Add more lines if the pool runs dry.

	var line: ConnectionLine = _pool.pop_front()
	
	# The line is a child of the pool, remove it before handing it out.
	if line.get_parent() == self:
		remove_child(line)
		
	line.visible = true
	return line


# Returns a line to the pool so it can be reused.
func return_line(line: ConnectionLine) -> void:
	if not is_instance_valid(line):
		return

	line.visible = false
	# Reparent the line back to the pool to keep the scene tree clean.
	if line.get_parent() != self:
		line.get_parent().remove_child(line)
		add_child(line)
	
	_pool.append(line)
