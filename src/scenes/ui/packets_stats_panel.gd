class_name PacketsStatsPanel extends PanelContainer
# -----------------------------------------
# --- Child Nodes References --------------
# -----------------------------------------
@onready var stored_progress_bar: TextureProgressBar = $MainMarginContainer/MainVBoxContainer/StoredProgressBar
@onready var stored_value_label: Label = $MainMarginContainer/MainVBoxContainer/StoredProgressBar/StoredValueLabel
@onready var consumed_value_label: Label = $MainMarginContainer/MainVBoxContainer/HBoxContainer/ConsumedValueLabel
@onready var balance_value_label: Label = $MainMarginContainer/MainVBoxContainer/HBoxContainer/BalanceValueLabel
@onready var produced_value_label: Label = $MainMarginContainer/MainVBoxContainer/HBoxContainer/ProducedValueLabel


# Should get this from global data
var default_max_storage: float = 50.0

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Initialize packets stored bar values
	stored_progress_bar.min_value = 0
	stored_progress_bar.max_value = default_max_storage
	stored_progress_bar.value = 0

# -----------------------------------------
# --- Update Packets Stats ----------------
# -----------------------------------------
func update_stats(stored: float, max_storage: float, produced: float, consumed: float, net_balance: float) -> void:
	# Update stored packets label and bar
	stored_value_label.text = "Packets Stored: %.1f / %.1f" % [stored, max_storage]
	stored_progress_bar.value = stored
	# Only assign new value if max storaged changed 
	if stored_progress_bar.max_value != max_storage:
		stored_progress_bar.max_value = max_storage

	# Update production/consumption values
	produced_value_label.text = "+ %.1f" % [produced]
	consumed_value_label.text = "- %.1f" % [consumed]

	# Update balance label
	# Color code the balance label based on value
	var balance_color := Color.GREEN if net_balance > 0 else Color.RED if net_balance < 0 else Color.WHITE
	balance_value_label.add_theme_color_override("font_color", balance_color)
	balance_value_label.text = "%.1f" % [net_balance]
