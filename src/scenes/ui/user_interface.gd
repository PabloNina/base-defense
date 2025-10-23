class_name UserInterface extends CanvasLayer
# -----------------------------------------
# --- Child Nodes References --------------
# -----------------------------------------
@onready var packets_stored_label: Label = $PacketsStats/Panel/MarginContainer/VBoxContainer/PacketsStoredLabel
@onready var packets_stored_bar: ProgressBar = $PacketsStats/Panel/MarginContainer/VBoxContainer/PacketsStoredBar
@onready var packets_spent_label: Label = $PacketsStats/Panel/MarginContainer/VBoxContainer/HBoxContainer/PacketsDemandLabel
@onready var packets_produced_label: Label = $PacketsStats/Panel/MarginContainer/VBoxContainer/HBoxContainer/PacketsProducedLabel
@onready var packets_balance_label: Label = $PacketsStats/Panel/MarginContainer/VBoxContainer/HBoxContainer/PacketsBalanceLabel
@onready var building_actions_panel: MarginContainer = $BuildingsPanel/HBoxContainer/Panel/BuildingActionsPanel
@onready var building_actions_label: Label = $BuildingsPanel/HBoxContainer/Panel/BuildingActionsPanel/LabelsContainer/BuildingActionsLabel
@onready var buttons_container: VBoxContainer = $BuildingsPanel/HBoxContainer/Panel/BuildingActionsPanel/LabelsContainer/ButtonsContainer
# -----------------------------------------
# --- Managers References ---------------
# -----------------------------------------
var network_manager: NetworkManager
var building_manager: BuildingManager
# -----------------------------------------
# --- Signals ------------------------------
# -----------------------------------------
# Listener: BuildingManager
signal building_button_pressed(building_to_build: DataTypes.BUILDING_TYPE)
signal destroy_button_pressed(building_to_destroy: Building)
signal move_button_pressed(building_to_move: MovableBuilding)
# -----------------------------------------
# --- ???????????? -----------------------
# -----------------------------------------
var current_building_selected: Building
var default_max_storage: float = 50.0
# A dictionary to map actions to button text and methods
const ACTION_DEFINITIONS = {
	DataTypes.BUILDING_ACTIONS.DESTROY: {"text": "Destroy", "method": "_on_destroy_button_pressed"},
	DataTypes.BUILDING_ACTIONS.MOVE: {"text": "Move", "method": "_on_move_button_pressed"},
}
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Subscribe to network signals
	network_manager = get_tree().get_first_node_in_group("network_manager")
	if network_manager:
		network_manager.ui_update_packets.connect(on_update_packets)

	# Subscribe to building manager signals
	building_manager = get_tree().get_first_node_in_group("building_manager")
	if building_manager:
		building_manager.building_selected.connect(show_building_actions_panel)
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
func show_building_actions_panel(selected_building: Building) -> void:
	current_building_selected = selected_building
	building_actions_label.text = DataTypes.get_display_name(selected_building.building_type)
	
	# Clear any old buttons
	for child in buttons_container.get_children():
		child.queue_free()

	# Ask the building what it can do
	var available_actions = selected_building.get_available_actions()

	# Create a button for each action
	for action in available_actions:
		if ACTION_DEFINITIONS.has(action):
			var definition = ACTION_DEFINITIONS[action]
			var button = Button.new()
			button.text = definition.text
			# Connect the button's press signal to the corresponding method
			button.pressed.connect(self.call.bind(definition.method))
			buttons_container.add_child(button)
	
	building_actions_panel.visible = true

func hide_building_actions_panel() -> void:
	current_building_selected = null
	building_actions_panel.visible = false

func _on_destroy_button_pressed() -> void:
	if current_building_selected:
		# Emit signal to BuildingManager
		destroy_button_pressed.emit(current_building_selected)
		hide_building_actions_panel()

func _on_move_button_pressed() -> void:
	if current_building_selected and current_building_selected is MovableBuilding:
		# Emit signal to BuildingManager
		move_button_pressed.emit(current_building_selected)
		hide_building_actions_panel()

# -----------------------------------------
# --- Building Selection Panel -------------
# -----------------------------------------
func _on_relay_button_pressed() -> void:
	building_button_pressed.emit(DataTypes.BUILDING_TYPE.RELAY)


func _on_turret_button_pressed() -> void:
	building_button_pressed.emit(DataTypes.BUILDING_TYPE.GUN_TURRET)


func _on_generator_button_pressed() -> void:
	building_button_pressed.emit(DataTypes.BUILDING_TYPE.GENERATOR)


func _on_base_button_pressed() -> void:
	building_button_pressed.emit(DataTypes.BUILDING_TYPE.COMMAND_CENTER)
