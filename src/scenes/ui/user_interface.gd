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
@onready var energy_balance_bar: ProgressBar = $EnergyStats/VBoxContainer/EnergyBalanceBar
@onready var building_actions_panel: MarginContainer = $BuildingActionsPanel
@onready var energy_spent_label: Label = $EnergyStats/VBoxContainer/HBoxContainer/EnergyDemandLabel
@onready var energy_produced_label: Label = $EnergyStats/VBoxContainer/HBoxContainer/EnergyProducedLabel
@onready var energy_balance_label: Label = $EnergyStats/VBoxContainer/HBoxContainer/EnergyBalanceLabel

# -----------------------------------------
# --- Runtime State -----------------------
# -----------------------------------------
var current_building_selected: Relay
var max_balance_value: int = 200 # Maximum production/demand displayed on bar
var net_balance: int = 0
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
	energy_balance_bar.min_value = -max_balance_value
	energy_balance_bar.max_value = max_balance_value
	energy_balance_bar.value = 0

# -----------------------------------------
# --- Energy Display ----------------------
# -----------------------------------------
# Update the stored energy label
func on_update_energy(current_energy: int, energy_produced: int, energy_spent: int) -> void:
	energy_stored_label.text = "Energy Stored: %d / %d" % [current_energy, 200]
	update_energy_balance(energy_produced, energy_spent)
	
# Update the balance bar based on net production/demand
func update_energy_balance(energy_produced: int, energy_spent: int) -> void:
	energy_produced_label.text = "+ %d" % [energy_produced]
	energy_spent_label.text = "- %d" % [energy_spent]
	
	net_balance = energy_produced - energy_spent
	energy_balance_bar.value = net_balance
	energy_balance_label.text = "%d" % [net_balance]

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
