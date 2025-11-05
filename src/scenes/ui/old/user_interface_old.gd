class_name UserInterfaceOld extends CanvasLayer
# -----------------------------------------
# --- Child Nodes References --------------
# -----------------------------------------
@onready var packets_stored_label: Label = $PacketsStats/Panel/MarginContainer/VBoxContainer/PacketsStoredLabel
@onready var packets_stored_bar: ProgressBar = $PacketsStats/Panel/MarginContainer/VBoxContainer/PacketsStoredBar
@onready var packets_spent_label: Label = $PacketsStats/Panel/MarginContainer/VBoxContainer/HBoxContainer/PacketsDemandLabel
@onready var packets_produced_label: Label = $PacketsStats/Panel/MarginContainer/VBoxContainer/HBoxContainer/PacketsProducedLabel
@onready var packets_balance_label: Label = $PacketsStats/Panel/MarginContainer/VBoxContainer/HBoxContainer/PacketsBalanceLabel
@onready var building_actions_panel: MarginContainer = $BuildingsPanelOld/HBoxContainer/Panel/BuildingActionsPanel
@onready var building_actions_label: Label = $BuildingsPanelOld/HBoxContainer/Panel/BuildingActionsPanel/VBoxContainer/BuildingActionsLabel
@onready var buttons_container: VBoxContainer = $BuildingsPanelOld/HBoxContainer/Panel/BuildingActionsPanel/VBoxContainer/ButtonsContainer
# -----------------------------------------
# --- Managers References ---------------
# -----------------------------------------
var grid_manager: GridManager
var building_manager: BuildingManager
# -----------------------------------------
# --- Signals ------------------------------
# -----------------------------------------
# Listener: BuildingManager
signal building_button_pressed(building_to_build: GlobalData.BUILDING_TYPE)
signal destroy_button_pressed(building_to_destroy: Building)
signal deactivate_button_pressed(building_to_deactivate: Building)
signal move_selection_pressed()
# -----------------------------------------
# --- ???????????? -----------------------
# -----------------------------------------
var current_selection: Array[Building] = []
var default_max_storage: float = 50.0
# A dictionary to map actions to button text and methods
const ACTION_DEFINITIONS = {
	GlobalData.BUILDING_ACTIONS.DESTROY: {"text": "Destroy", "method": "_on_destroy_button_pressed"},
	GlobalData.BUILDING_ACTIONS.MOVE: {"text": "Move", "method": "_on_move_button_pressed"},
	GlobalData.BUILDING_ACTIONS.DEACTIVATE: {"text": "De/activate", "method": "_on_deactivate_button_pressed"},
}
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Subscribe to grid signals
	grid_manager = get_tree().get_first_node_in_group("grid_manager")
	if grid_manager:
		grid_manager.ui_update_packets.connect(on_update_packets)

	# Subscribe to building manager signals
	building_manager = get_tree().get_first_node_in_group("building_manager")
	if building_manager:
		#building_manager.building_selected.connect(show_building_actions_panel)
		building_manager.selection_changed.connect(show_building_actions_panel)
		building_manager.building_deselected.connect(hide_building_actions_panel)

	# Hide building actions panel at start
	hide_building_actions_panel()

	# Initialize packets stored bar range
	packets_stored_bar.min_value = 0
	packets_stored_bar.max_value = default_max_storage
	packets_stored_bar.value = 0

# -----------------------------------------
# --- Packets Stats Panel ----------------
# -----------------------------------------
# Update packets stats
func on_update_packets(stored: float, max_storage: float, produced: float, consumed: float, net_balance: float) -> void:
	# Update stored packets label and bar
	packets_stored_label.text = "Packets Stored: %.1f / %.1f" % [stored, max_storage]
	packets_stored_bar.value = stored
	# Only assign new value if max storaged changed 
	if packets_stored_bar.max_value != max_storage:
		packets_stored_bar.max_value = max_storage

	# Update production/consumption values
	packets_produced_label.text = "+ %.1f" % [produced]
	packets_spent_label.text = "- %.1f" % [consumed]

	# Update balance label
	# Color code the balance label based on value
	var balance_color := Color.GREEN if net_balance > 0 else Color.RED if net_balance < 0 else Color.WHITE
	packets_balance_label.add_theme_color_override("font_color", balance_color)
	packets_balance_label.text = "%.1f" % [net_balance]

# -----------------------------------------
# --- Building Actions Panel --------------
# -----------------------------------------
func show_building_actions_panel(selected_buildings: Array[Building]) -> void:
	current_selection = selected_buildings
	
	# First, clear any old buttons from the container
	for child in buttons_container.get_children():
		child.queue_free()

	var available_actions: Array[GlobalData.BUILDING_ACTIONS]

	if current_selection.size() == 1:
		# Single building selected
		var building = current_selection[0]
		building_actions_label.text = GlobalData.get_display_name(building.building_type)
		available_actions = building.get_available_actions()
	else:
		# Multiple buildings selected - actions are the same for all
		building_actions_label.text = "%s Buildings Selected" % current_selection.size()
		available_actions = current_selection[0].get_available_actions()

	# Create a button for each common action
	for action in available_actions:
		if ACTION_DEFINITIONS.has(action):
			var definition = ACTION_DEFINITIONS[action]
			var button = Button.new()
			button.text = definition.text
			button.pressed.connect(self.call.bind(definition.method))
			buttons_container.add_child(button)
	
	building_actions_panel.visible = true

func hide_building_actions_panel() -> void:
	current_selection.clear()
	building_actions_panel.visible = false

func _on_destroy_button_pressed() -> void:
	if not current_selection.is_empty():
		for building in current_selection:
			destroy_button_pressed.emit(building)
		hide_building_actions_panel()

func _on_move_button_pressed() -> void:
	if not current_selection.is_empty():
		move_selection_pressed.emit()
		hide_building_actions_panel()
		
func _on_deactivate_button_pressed() -> void:
	if not current_selection.is_empty():
		for building in current_selection:
			deactivate_button_pressed.emit(building)
		hide_building_actions_panel()

# -----------------------------------------
# --- Building Selection Panel -------------
# -----------------------------------------
func _on_relay_button_pressed() -> void:
	building_button_pressed.emit(GlobalData.BUILDING_TYPE.RELAY)


func _on_turret_button_pressed() -> void:
	building_button_pressed.emit(GlobalData.BUILDING_TYPE.GUN_TURRET)


func _on_generator_button_pressed() -> void:
	building_button_pressed.emit(GlobalData.BUILDING_TYPE.GENERATOR)


func _on_base_button_pressed() -> void:
	building_button_pressed.emit(GlobalData.BUILDING_TYPE.COMMAND_CENTER)
