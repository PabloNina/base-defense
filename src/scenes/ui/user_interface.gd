extends CanvasLayer

@export var network_manager: NetworkManager



@onready var energy_stored_label: Label = $EnergyStats/VBoxContainer/EnergyStoredLabel
@onready var energy_balance_bar: ProgressBar = $EnergyStats/VBoxContainer/EnergyBalanceBar



#var demand: int = 0
#var net_rate: int = 0
var current_display_value: int = 0

func _ready() -> void:
	network_manager.update_energy.connect(on_update_energy)


func on_update_energy(current_energy: int) -> void:
	if current_display_value != current_energy:
		energy_balance_bar.value = current_energy
		energy_stored_label.text = "Energy Stored: %d / %d" % [current_energy, 150]
