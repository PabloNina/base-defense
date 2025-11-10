class_name BuildingManagerState extends NodeState

var building_manager: BuildingManager
@export var state: BuildingManager.STATES

func _ready() -> void:
	# This state must be the child of the state machine which is a child of the BuildingManager
	building_manager = get_parent().get_parent()
	# Ensure that the parent is a BuildingManager if not generate an error
	assert(building_manager is BuildingManager)

func _on_enter() -> void:
	if building_manager.current_state != self.state:
		building_manager.current_state = self.state
