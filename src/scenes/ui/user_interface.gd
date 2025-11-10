class_name UserInterface extends CanvasLayer
# -----------------------------------------
# --- Child Nodes References --------------
# -----------------------------------------
@onready var building_actions_and_info_panel: BuildingActionsAndInfoPanel = $MainMarginContainer/BuildingActionsAndInfoPanel
@onready var buildings_construction_panel: BuildingsConstructionPanel = $MainMarginContainer/BuildingsConstructionPanel
@onready var packets_stats_panel: PacketsStatsPanel = $MainMarginContainer/PacketsStatsPanel
# -----------------------------------------
# --- Signals ------------------------------
# -----------------------------------------
# Listener: BuildingManager
signal building_button_pressed(building_to_build: GlobalData.BUILDING_TYPE)
signal destroy_button_pressed()
signal deactivate_button_pressed()
signal move_selection_pressed()
# -----------------------------------------
# --- Managers References ---------------
# -----------------------------------------
var building_manager: BuildingManager
var grid_manager: GridManager
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# Ensure UserInterface processes even when game is paused 
	process_mode = Node.PROCESS_MODE_ALWAYS
	# By default start with construction panel selected
	_hide_building_actions_and_info_panel()
	_show_buildings_construction_panel()

	# Subscribe to building manager signals
	building_manager = get_tree().get_first_node_in_group("building_manager")
	if building_manager:
		building_manager.selection_changed.connect(_show_building_actions_and_info_panel)
		building_manager.building_deselected.connect(_hide_building_actions_and_info_panel)

	# Subscribe to grid manager signals
	grid_manager = get_tree().get_first_node_in_group("grid_manager")
	if grid_manager:
		grid_manager.ui_update_packets.connect(_on_update_packets)

	# Subscribe to building actions panel signals
	building_actions_and_info_panel.destroy_action_pressed.connect(_on_destroy_action_pressed)
	building_actions_and_info_panel.deactivate_action_pressed.connect(_on_deactivate_action_pressed)
	building_actions_and_info_panel.move_action_pressed.connect(_on_move_action_pressed)
	
	# Subscribe to buildings construction panel signals
	buildings_construction_panel.construction_button_pressed.connect(_on_construction_button_pressed)
	
# -----------------------------------------
# --- Building Manager Signal Handling ----
# -----------------------------------------
# Changes building action panel visibility and updates buttons and info labels
# Connected to building_manager.selection_changed Signal
func _show_building_actions_and_info_panel(selected_buildings: Array[Building]) -> void:
	if not building_actions_and_info_panel.visible:
		building_actions_and_info_panel.visible = true
		building_actions_and_info_panel.update_actions_and_info(selected_buildings)

# Connected to building_manager.building_deselected Signal
func _hide_building_actions_and_info_panel() -> void:
	if building_actions_and_info_panel.visible:
		building_actions_and_info_panel.visible = false
		building_actions_and_info_panel.clear_actions_and_info()

# -----------------------------------------
# --- Grid Manager Signal Handling --------
# -----------------------------------------
# Updates packet stats on tick
# Connected to grid_manager.ui_update_packets Signal
func _on_update_packets(stored: float, max_storage: float, produced: float, consumed: float, net_balance: float) -> void:
	packets_stats_panel.update_stats(stored, max_storage, produced, consumed, net_balance)
	
# ----------------------------------------------------
# --- Construction&Actions Buttons Signal Handling ---
# ----------------------------------------------------
func _on_construction_button_pressed(building_type: GlobalData.BUILDING_TYPE) -> void:
	building_button_pressed.emit(building_type)

func _on_destroy_action_pressed() -> void:
	destroy_button_pressed.emit()

func _on_deactivate_action_pressed() -> void:
	deactivate_button_pressed.emit()

func _on_move_action_pressed() -> void:
	move_selection_pressed.emit()

# -----------------------------------------------
# --- Buildings Construction Panel Visibility ---
# -----------------------------------------------
func _show_buildings_construction_panel() -> void:
	if not buildings_construction_panel.visible:
		buildings_construction_panel.visible = true

func _hide_buildings_construction_panel() -> void:
	if buildings_construction_panel.visible:
		buildings_construction_panel.visible = false
