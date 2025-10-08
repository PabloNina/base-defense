extends CanvasLayer

@onready var energy_bar: ProgressBar = $MarginContainer/EnergyBar
@export var n_manager: NetworkManager

func _ready() -> void:
	n_manager.update_energy.connect(on_update_energy)


func on_update_energy(current_energy: int) -> void:
	energy_bar.value = current_energy
