# =========================================
# ghost_preview_pool.gd
# =========================================
# Manages a pool of reusable GhostPreview objects to optimize performance
# by avoiding frequent instantiation and destruction.
class_name GhostPreviewPool extends Node
# -----------------------------------------
# --- Editor Exports ----------------------
# -----------------------------------------
## The initial size of the pool.
@export var pool_size: int = 20
## The value to increment pool_size each time the pool goes empty.
@export var pool_grow_value: int = 5
# -----------------------------------------
# --- Runtime Data ------------------------
# -----------------------------------------
# The pool of available GhostPreview objects.
var ghost_preview_pool: Array[GhostPreview] = []
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Pre-populate the pool with GhostPreview instances.
	_populate_pool(pool_size)

# ---------------------------------
# --- Private Methods -------------
# ---------------------------------
# Pre-instantiates a number of GhostPreviews to have them ready for use.
func _populate_pool(size: int) -> void:
	for i in range(size):
		var preview: GhostPreview = GlobalData.GHOST_PREVIEW_SCENE.instantiate()
		# Disable the preview and add it to the pool.
		preview.clear()
		ghost_preview_pool.append(preview)
		add_child(preview)

# ---------------------------------
# --- Public Methods --------------
# ---------------------------------
# Retrieves a GhostPreview from the pool and returns it.
# If the pool is empty it creates more.
func get_preview() -> GhostPreview:
	# Add more previews if the pool runs dry.
	if ghost_preview_pool.is_empty():
		print("GhostPreview pool empty. Growing pool!")
		_populate_pool(pool_grow_value)

	# Get a preview from the front of the pool.
	var preview: GhostPreview = ghost_preview_pool.pop_front()

	# The preview is a child of the pool, remove it before handing it out.
	if preview.get_parent() == self:
		remove_child(preview)

	# Enable the preview
	preview.visible = true

	return preview


# Returns a GhostPreview to the pool so it can be reused.
func return_preview(preview: GhostPreview) -> void:
	if not is_instance_valid(preview):
		return

	# Disable and reset the preview.
	preview.clear()

	# Reparent the preview back to the pool to keep the scene tree clean.
	if preview.get_parent() != self:
		if preview.get_parent() != null:
			preview.get_parent().remove_child(preview)
		add_child(preview)
	
	# Add preview back to the pool
	ghost_preview_pool.append(preview)
