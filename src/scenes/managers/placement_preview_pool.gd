# =========================================
# placement_preview_pool.gd
# =========================================
# Manages a pool of reusable PlacementPreview objects to optimize performance
# by avoiding frequent instantiation and destruction.
class_name PlacementPreviewPool extends Node
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
# The pool of available PlacementPreview objects.
var placement_preview_pool: Array[PlacementPreview] = []
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Pre-populate the pool with PlacementPreview instances.
	_populate_pool(pool_size)

# ---------------------------------
# --- Private Methods -------------
# ---------------------------------
# Pre-instantiates a number of PlacementPreviews to have them ready for use.
func _populate_pool(size: int) -> void:
	for i in range(size):
		var preview: PlacementPreview = GlobalData.PLACEMENT_PREVIEW_SCENE.instantiate()
		# Disable the preview and add it to the pool.
		preview.clear()
		placement_preview_pool.append(preview)
		add_child(preview)

# ---------------------------------
# --- Public Methods --------------
# ---------------------------------
# Retrieves a PlacementPreview from the pool and returns it.
# If the pool is empty it creates more.
func get_preview() -> PlacementPreview:
	# Add more previews if the pool runs dry.
	if placement_preview_pool.is_empty():
		print("PlacementPreview pool empty. Growing pool!")
		_populate_pool(pool_grow_value)

	# Get a preview from the front of the pool.
	var preview: PlacementPreview = placement_preview_pool.pop_front()

	# The preview is a child of the pool, remove it before handing it out.
	if preview.get_parent() == self:
		remove_child(preview)

	# Enable the preview
	preview.visible = true

	return preview


# Returns a PlacementPreview to the pool so it can be reused.
func return_preview(preview: PlacementPreview) -> void:
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
	placement_preview_pool.append(preview)
