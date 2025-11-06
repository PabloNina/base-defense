class_name BuildingActionsAndInfoPanel extends PanelContainer
# -----------------------------------------
# --- Child Nodes References --------------
# -----------------------------------------
@onready var actions_buttons_container: VBoxContainer = $MainMarginContainer/MainHBoxContainer/ActionsButtonsContainer
@onready var name_label: Label = $MainMarginContainer/MainHBoxContainer/InfoLabelsContainer/NameLabel
@onready var health_label: Label = $MainMarginContainer/MainHBoxContainer/InfoLabelsContainer/HealthLabel
@onready var ammo_label: Label = $MainMarginContainer/MainHBoxContainer/InfoLabelsContainer/AmmoLabel
# -----------------------------------------
# --- Signals -----------------------------
# -----------------------------------------
# Listener: UserInterface
signal destroy_action_pressed(building_to_destroy: Building)
signal deactivate_action_pressed(building_to_deactivate: Building)
signal move_action_pressed()
# -----------------------------------------
# --- RunTime Data ------------------------
# -----------------------------------------
# Current selected single or multiple buildings
var current_selection: Array[Building] = []
var observed_building: Building = null

# Action Definitions Dictionary used to button creation
const ACTION_DEFINITIONS = {
	GlobalData.BUILDING_ACTIONS.DESTROY: {"text": "Destroy", "method": "_on_destroy_button_pressed"},
	GlobalData.BUILDING_ACTIONS.MOVE: {"text": "Move", "method": "_on_move_button_pressed"},
	GlobalData.BUILDING_ACTIONS.DEACTIVATE: {"text": "De/activate", "method": "_on_deactivate_button_pressed"},
}
# -----------------------------------------
# --- Public Methods ----------------------
# -----------------------------------------
# Called by UserInterface
# Creates actions buttons sets info labels and connects signals
func update_actions_and_info(selected_buildings: Array[Building]) -> void:
	# Disconnect signal from previous building
	if is_instance_valid(observed_building):
		if observed_building.state_updated.is_connected(_on_observed_building_state_updated):
			observed_building.state_updated.disconnect(_on_observed_building_state_updated)
			
	# Set current selection
	current_selection = selected_buildings
	var building: Building
	var building_type: GlobalData.BUILDING_TYPE
	var available_actions: Array[GlobalData.BUILDING_ACTIONS]
	
	# Atm only multi selections of same building type are allowed 
	# so even if it is a multi selection always get the first building in current_selection 
	building = current_selection[0]
	# Keep track of the new building
	observed_building = building 
	
	# Connect signal to new building
	if is_instance_valid(observed_building):
		observed_building.state_updated.connect(_on_observed_building_state_updated)
		
	# Get actions for the buttons
	available_actions = GlobalData.get_building_actions(building.building_type)
	
	# Create info labels
	_update_info_labels(building)
	# Create a button for each common action
	_create_action_buttons(available_actions)

# Called by UserInterface
func clear_actions_and_info() -> void:
	# Disconnect from previous building
	if is_instance_valid(observed_building):
		if observed_building.state_updated.is_connected(_on_observed_building_state_updated):
			observed_building.state_updated.disconnect(_on_observed_building_state_updated)
			
	# Clear references
	observed_building = null
	current_selection.clear()
# --------------------------------
# --- Action Buttons Creation ----
# --------------------------------
# Creates buttons based on available_actions and ACTION_DEFINITIONS
func _create_action_buttons(available_actions: Array[GlobalData.BUILDING_ACTIONS]) -> void:
	# First clear any old buttons from the container
	for child in actions_buttons_container.get_children():
		child.queue_free()

	# Create one button for each available action
	# Set it with action definition data
	for action in available_actions:
		if ACTION_DEFINITIONS.has(action):
			var definition = ACTION_DEFINITIONS[action]
			var button = Button.new()
			button.text = definition.text
			button.pressed.connect(self.call.bind(definition.method))
			actions_buttons_container.add_child(button)

# --------------------------------
# --- Info Labels Creation -------
# --------------------------------
func _on_observed_building_state_updated() -> void:
	if is_instance_valid(observed_building):
		_update_info_labels(observed_building)
	
func _update_info_labels(building: Building) -> void:
	_update_name_label(building)
	_update_health_label(building)
	_update_ammo_label(building)

func _update_name_label(building: Building) -> void:
	# Get name from GlobalData
	var display_name: String = GlobalData.get_display_name(building.building_type)
	# Check for single or multiple selection
	if current_selection.size() == 1:
		name_label.text = (display_name + ":")
	else:
		name_label.text = str(current_selection.size()) + " " + display_name + "s:"

func _update_health_label(building: Building) -> void:
	var max_health: int = GlobalData.get_cost_to_build(building.building_type)
	var current_health = building.construction_progress
	health_label.text = "Health: " + str(current_health) + "/" + str(max_health)

func _update_ammo_label(building: Building) -> void:
	var building_category: GlobalData.BUILDING_CATEGORY 
	building_category = GlobalData.get_building_category(building.building_type)
	# If category is weapon
	if building_category == GlobalData.BUILDING_CATEGORY.WEAPON:
		# show ammo label and set text
		var max_ammo_storage: int = GlobalData.get_max_ammo_storage(building.building_type)
		var current_ammo: float = building.current_ammo
		ammo_label.text = "Ammo: " + str(current_ammo) + "/" + str(max_ammo_storage)
		if not ammo_label.visible:
			ammo_label.visible = true
	else:
		# hide ammo label
		if ammo_label.visible:
			ammo_label.visible = false

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
