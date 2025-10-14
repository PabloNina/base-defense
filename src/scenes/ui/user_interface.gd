class_name UserInterface
extends CanvasLayer

# -----------------------------------------
# --- Exports / References ---------------
# -----------------------------------------
@export var network_manager: NetworkManager
@export var building_manager: BuildingManager

# -----------------------------------------
# --- Nodes ------------------------------
# -----------------------------------------
@onready var energy_stored_label: Label = $EnergyStats/VBoxContainer/EnergyStoredLabel
@onready var energy_stored_bar: ProgressBar = $EnergyStats/VBoxContainer/EnergyStoredBar
@onready var building_actions_panel: MarginContainer = $BuildingActionsPanel
@onready var energy_spent_label: Label = $EnergyStats/VBoxContainer/HBoxContainer/EnergyDemandLabel
@onready var energy_produced_label: Label = $EnergyStats/VBoxContainer/HBoxContainer/EnergyProducedLabel
@onready var energy_balance_label: Label = $EnergyStats/VBoxContainer/HBoxContainer/EnergyBalanceLabel

# -----------------------------------------
# --- Runtime State -----------------------
# -----------------------------------------
var current_building_selected: Relay
var max_balance_value: int = 200 # Maximum production/demand displayed on bar
# -----------------------------------------
# --- Initialization ---------------------
# -----------------------------------------
func _ready() -> void:
	# Subscribe to network signals
	if network_manager:
		network_manager.ui_update_energy.connect(on_update_energy)

	# Subscribe to building manager signals
	if building_manager:
		building_manager.building_selected.connect(show_building_actions_panel)
		building_manager.building_deselected.connect(hide_building_actions_panel)

	# Hide building panel at start
	hide_building_actions_panel()

	# Initialize balance bar range
	energy_stored_bar.min_value = 0
	energy_stored_bar.max_value = max_balance_value
	energy_stored_bar.value = 0

# -----------------------------------------
# --- Energy Display ----------------------
# -----------------------------------------
# Update energy stats
func on_update_energy(current_energy: float, produced: float, consumed: float, net_balance: float) -> void:
	# Update stored energy label and bar
	energy_stored_label.text = "Energy Stored: %.1f / %.1f" % [current_energy, 200.0]
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
func show_building_actions_panel(selected_building: Relay) -> void:
	current_building_selected = selected_building
	building_actions_panel.visible = true

func hide_building_actions_panel() -> void:
	current_building_selected = null
	building_actions_panel.visible = false

func _on_destroy_button_pressed() -> void:
	if current_building_selected:
		current_building_selected.destroy()
		hide_building_actions_panel()
