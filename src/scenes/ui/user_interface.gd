class_name UserInterface extends CanvasLayer

# -----------------------------------------
# --- Nodes ------------------------------
# -----------------------------------------
@onready var energy_stored_label: Label = $EnergyStats/Panel/MarginContainer/VBoxContainer/EnergyStoredLabel
@onready var energy_stored_bar: ProgressBar = $EnergyStats/Panel/MarginContainer/VBoxContainer/EnergyStoredBar
@onready var building_actions_panel: MarginContainer = $BuildingsPanel/HBoxContainer/Panel/BuildingActionsPanel
@onready var energy_spent_label: Label = $EnergyStats/Panel/MarginContainer/VBoxContainer/HBoxContainer/EnergyDemandLabel
@onready var energy_produced_label: Label = $EnergyStats/Panel/MarginContainer/VBoxContainer/HBoxContainer/EnergyProducedLabel
@onready var energy_balance_label: Label = $EnergyStats/Panel/MarginContainer/VBoxContainer/HBoxContainer/EnergyBalanceLabel
@onready var building_actions_label: Label = $BuildingsPanel/HBoxContainer/Panel/BuildingActionsPanel/VBoxContainer/BuildingActionsLabel

# -----------------------------------------
# --- ???????????? -----------------------
# -----------------------------------------
var current_building_selected: Building
var max_balance_value: int = 100 # Maximum production/demand displayed on bar

# -----------------------------------------
# --- References ---------------
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
# --- Initialization ---------------------
# -----------------------------------------
func _ready() -> void:

	# Subscribe to network signals
	network_manager = get_tree().get_first_node_in_group("network_manager")
	if network_manager:
		network_manager.ui_update_energy.connect(on_update_energy)

	# Subscribe to building manager signals
	building_manager = get_tree().get_first_node_in_group("building_manager")
	if building_manager:
		building_manager.building_selected.connect(show_building_actions_panel)
		building_manager.building_deselected.connect(hide_building_actions_panel)

	# Hide building panel at start
	hide_building_actions_panel()

	# Initialize packets stored bar range
	energy_stored_bar.min_value = 0
	energy_stored_bar.max_value = max_balance_value
	energy_stored_bar.value = 0

# -----------------------------------------
# --- Energy Stats Panel ----------------
# -----------------------------------------
# Update energy stats

func on_update_energy(current_energy: float, produced: float, consumed: float, net_balance: float) -> void:
	# Update stored packets label and bar
	energy_stored_label.text = "Packets Stored: %.1f / %.1f" % [current_energy, max_balance_value]
	energy_stored_bar.value = current_energy

	# Update production/consumption values
	energy_produced_label.text = "+ %.1f" % [produced]
	energy_spent_label.text = "- %.1f" % [consumed]

	# Update balance label
	# Color code the balance label based on value
	var balance_color := Color.GREEN if net_balance > 0 else Color.RED if net_balance < 0 else Color.WHITE
	energy_balance_label.add_theme_color_override("font_color", balance_color)
	energy_balance_label.text = "%.1f" % [net_balance]

# -----------------------------------------
# --- Building Actions Panel --------------
# -----------------------------------------
func show_building_actions_panel(selected_building: Building) -> void:
	current_building_selected = selected_building
	building_actions_label.text = DataTypes.get_display_name(selected_building.building_type)
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
# --- Building Selection Panel --------------
# -----------------------------------------
func _on_relay_button_pressed() -> void:
	building_button_pressed.emit(DataTypes.BUILDING_TYPE.RELAY)


func _on_turret_button_pressed() -> void:
	building_button_pressed.emit(DataTypes.BUILDING_TYPE.GUN_TURRET)


func _on_generator_button_pressed() -> void:
	building_button_pressed.emit(DataTypes.BUILDING_TYPE.GENERATOR)


func _on_base_button_pressed() -> void:
	building_button_pressed.emit(DataTypes.BUILDING_TYPE.COMMAND_CENTER)
