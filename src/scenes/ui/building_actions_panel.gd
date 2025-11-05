class_name BuildingActionsPanel extends PanelContainer
# -----------------------------------------
# --- Child Nodes References --------------
# -----------------------------------------
@onready var actions_buttons_container: VBoxContainer = $MainMarginContainer/MainHBoxContainer/ActionsButtonsContainer
@onready var name_label: Label = $MainMarginContainer/MainHBoxContainer/InfoContainer/NameLabel
# -----------------------------------------
# --- Signals -----------------------------
# -----------------------------------------
# Listener: UserInterface
signal destroy_action_pressed(building_to_destroy: Building)
signal deactivate_action_pressed(building_to_deactivate: Building)
signal move_action_pressed()


# Current selected single or multiple buildings
var current_selection: Array[Building] = []

const ACTION_DEFINITIONS = {
	GlobalData.BUILDING_ACTIONS.DESTROY: {"text": "Destroy", "method": "_on_destroy_button_pressed"},
	GlobalData.BUILDING_ACTIONS.MOVE: {"text": "Move", "method": "_on_move_button_pressed"},
	GlobalData.BUILDING_ACTIONS.DEACTIVATE: {"text": "De/activate", "method": "_on_deactivate_button_pressed"},
}

# -----------------------------------------
# --- Public Methods --------------------
# -----------------------------------------
func update_building_actions_buttons(selected_buildings: Array[Building]) -> void:
	current_selection = selected_buildings
	
	# First, clear any old buttons from the container
	for child in actions_buttons_container.get_children():
		child.queue_free()

	var available_actions: Array[GlobalData.BUILDING_ACTIONS]

	if current_selection.size() == 1:
		# Single building selected
		var single_building = current_selection[0]
		name_label.text = GlobalData.get_display_name(single_building.building_type)
		available_actions = single_building.get_available_actions()
	else:
		# Multiple buildings selected - actions are the same for all
		# Get first building in selection
		var first_building = current_selection[0]
		var display_name: String = GlobalData.get_display_name(first_building.building_type)
		name_label.text = str(current_selection.size()) + " " + display_name + "s"
		available_actions = first_building.get_available_actions()

	# Create a button for each common action
	for action in available_actions:
		if ACTION_DEFINITIONS.has(action):
			var definition = ACTION_DEFINITIONS[action]
			var button = Button.new()
			button.text = definition.text
			button.pressed.connect(self.call.bind(definition.method))
			actions_buttons_container.add_child(button)
	

func clear_building_actions_buttons() -> void:
	current_selection.clear()
	

# -----------------------------------------
# --- Action Buttons Signal Handling ------
# -----------------------------------------
func _on_destroy_button_pressed() -> void:
	if not current_selection.is_empty():
		for building in current_selection:
			destroy_action_pressed.emit(building)

func _on_move_button_pressed() -> void:
	if not current_selection.is_empty():
		move_action_pressed.emit()
		
func _on_deactivate_button_pressed() -> void:
	if not current_selection.is_empty():
		for building in current_selection:
			deactivate_action_pressed.emit(building)
