class_name BuildingsConstructionPanel extends PanelContainer
# -----------------------------------------
# --- Child Nodes References --------------
# -----------------------------------------
@onready var infrastructure_buttons_container: VBoxContainer = $MainMarginContainer/MainHBoxContainer/InfrastructureButtonsContainer
@onready var weapon_buttons_container: VBoxContainer = $MainMarginContainer/MainHBoxContainer/WeaponButtonsContainer
@onready var special_buttons_container: VBoxContainer = $MainMarginContainer/MainHBoxContainer/SpecialButtonsContainer

# -----------------------------------------
# --- Signals -----------------------------
# -----------------------------------------
# Listener: UserInterface
signal construction_button_pressed(building_to_build: GlobalData.BUILDING_TYPE)
# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready() -> void:
	# By default start with infrastructures category selected
	_hide_weapon_buttons()
	_hide_special_buttons()
	_show_infrastructure_buttons()
	
# -----------------------------------------
# --- Category Buttons Signal Handling ----
# -----------------------------------------
func _on_infrastructure_button_pressed() -> void:
	_hide_weapon_buttons()
	_hide_special_buttons()
	_show_infrastructure_buttons()

func _on_weapons_button_pressed() -> void:
	_hide_infrastructure_buttons()
	_hide_special_buttons()
	_show_weapon_buttons()

func _on_special_button_pressed() -> void:
	_hide_infrastructure_buttons()
	_hide_weapon_buttons()
	_show_special_buttons()

# ---------------------------------------------
# --- Construction Buttons Signal Handling ----
# ---------------------------------------------
func _on_relay_button_pressed() -> void:
	construction_button_pressed.emit(GlobalData.BUILDING_TYPE.RELAY)
	
func _on_reactor_button_pressed() -> void:
	construction_button_pressed.emit(GlobalData.BUILDING_TYPE.GENERATOR)

func _on_cannon_button_pressed() -> void:
	construction_button_pressed.emit(GlobalData.BUILDING_TYPE.GUN_TURRET)

func _on_base_button_pressed() -> void:
	construction_button_pressed.emit(GlobalData.BUILDING_TYPE.COMMAND_CENTER)

# ---------------------------
# --- Buttons Visibility ----
# ---------------------------
func _show_infrastructure_buttons() -> void:
	if not infrastructure_buttons_container.visible:
		infrastructure_buttons_container.visible = true

func _hide_infrastructure_buttons() -> void:
	if infrastructure_buttons_container.visible:
		infrastructure_buttons_container.visible = false

func _show_weapon_buttons() -> void:
	if not weapon_buttons_container.visible:
		weapon_buttons_container.visible = true

func _hide_weapon_buttons() -> void:
	if weapon_buttons_container.visible:
		weapon_buttons_container.visible = false

func _show_special_buttons() -> void:
	if not special_buttons_container.visible:
		special_buttons_container.visible = true

func _hide_special_buttons() -> void:
	if special_buttons_container.visible:
		special_buttons_container.visible = false
