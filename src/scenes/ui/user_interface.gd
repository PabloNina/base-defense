extends CanvasLayer

@export var network_manager: NetworkManager
@export var building_manager: BuildingManager

@onready var energy_stored_label: Label = $EnergyStats/VBoxContainer/EnergyStoredLabel
@onready var energy_balance_bar: ProgressBar = $EnergyStats/VBoxContainer/EnergyBalanceBar
@onready var building_actions_panel: MarginContainer = $BuildingActionsPanel

var current_display_value: int = 0 # stores the current value the ui is displaying
var current_building_selected: Relay

func _ready() -> void:
	network_manager.update_energy.connect(on_update_energy)
	building_manager.building_selected.connect(show_building_actions_panel)
	building_manager.building_deselected.connect(hide_building_actions_panel)
	#
	hide_building_actions_panel()

# Energy stats display
func on_update_energy(current_energy: int) -> void:
	if current_display_value != current_energy:
		energy_balance_bar.value = current_energy
		energy_stored_label.text = "Energy Stored: %d / %d" % [current_energy, 150]

# Building actions panel
func show_building_actions_panel(selected_building: Relay) -> void:
	current_building_selected = selected_building
	building_actions_panel.visible = true

func hide_building_actions_panel() -> void:
	current_building_selected = null
	building_actions_panel.visible = false

func _on_destroy_button_pressed() -> void:
	current_building_selected.destroy()
	hide_building_actions_panel()
