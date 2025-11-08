# Weapon - weapon.gd
# ============================================================================
# This is an abstract base class for all defensive structures in the game
# that are capable of firing projectiles at enemies. It extends the
# `MovableBuilding` class, inheriting its grid integration and movement
# capabilities, while adding specialized functionalities for combat.
#
# Key Responsibilities:
# - Ammunition Management: Manages the weapon's current ammunition count,
#   maximum capacity, and the cost per shot. It also handles the reception
#   of ammo packets and updates the weapon's ammo state.
#
# - Firing Mechanics: Defines core properties such as fire rate and fire range.
#   (Specific targeting and projectile spawning logic are typically implemented
#   in concrete weapon subclasses).
#
# - State & Visual Feedback: Tracks the weapon's ammo status (e.g., full,
#   out of ammo) and provides visual indicators for these states, including
#   an ammo stock bar and an "out of ammo" sprite.
#
# - Packet Demand: Determines if the weapon requires ammo packets based on
#   its current stock, power status, and operational state.
# ============================================================================
@abstract
class_name Weapon extends MovableBuilding
# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
@onready var base_sprite: Sprite2D = $BaseSprite
@onready var turret_sprite: Sprite2D = $TurretSprite
@onready var ammo_stock_bar: ProgressBar = $AmmoStockBar
@onready var out_of_ammo_sprite: Sprite2D = $OutOfAmmoSprite
# -----------------------------------------
# --- Weapon Settings ---------------------
# -----------------------------------------
var max_ammo_storage: int = 0
var cost_per_shot: float = 0.0
var fire_rate: float = 0.0
var fire_range: int = 0
# -------------------------------
# --- Runtime States ------------
# -------------------------------
var is_full_ammo: bool = false
var is_scheduled_to_full_ammo: bool = false
var current_ammo: float = 0.0: set = _set_ammo

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready():
	super._ready()
	# group adding
	add_to_group("weapons")
	_config_weapon_settings()
	_config_ammo_bar()

func _process(_delta: float) -> void:
	if is_deactivated:
		return
	# Add shooting logic here
	pass

# -----------------------------------------
# -------- Public Methods -----------------
# -----------------------------------------

# -------------------------------
# --- Packet In Flight ----------
# -------------------------------
func increment_packets_in_flight() -> void:
	super.increment_packets_in_flight()
	if is_built and packets_in_flight + current_ammo >= max_ammo_storage:
		is_scheduled_to_full_ammo = true

func decrement_packets_in_flight() -> void:
	super.decrement_packets_in_flight()
	if is_built and packets_in_flight + current_ammo < max_ammo_storage:
		is_scheduled_to_full_ammo = false
		
func reset_packets_in_flight() -> void:
	super.reset_packets_in_flight()
	if is_built: #and not is_full_ammo:
		is_scheduled_to_full_ammo = false

# -------------------------------
# --- Packet Reception ----------
# -------------------------------
func received_packet(packet_type: GlobalData.PACKETS):
	# Let parent handle the standard packet types
	if packet_type in [GlobalData.PACKETS.BUILDING, GlobalData.PACKETS.ENERGY]:
		super.received_packet(packet_type)
		return
	
	# Handle ammo separately
	match packet_type:
		GlobalData.PACKETS.AMMO:
			_handle_received_ammo_packet()
		_:
			push_warning("Unknown packet type received: %s" % str(packet_type))


# -------------------------------
# --- Packet Demand Query -------
# -------------------------------
func needs_packet(packet_type: GlobalData.PACKETS) -> bool:
	# If parent class needs this packet let it handle it
	if super.needs_packet(packet_type):
		return true
	
	# Handle ammo separately
	match packet_type:
		GlobalData.PACKETS.AMMO:
			## Needs ammo if built, powered, not fully stocked and not scheduled to full
			return is_built and is_powered and not is_deactivated and not is_full_ammo and not is_scheduled_to_full_ammo

		_:
			return false

# -----------------------------------------
# -------- Private Methods ----------------
# -----------------------------------------

# -----------------------------------
# --- Weapon Configuration ----------
# -----------------------------------
func _config_weapon_settings() -> void:
	# config weapon with data from global data
	max_ammo_storage = GlobalData.get_max_ammo_storage(building_type)
	cost_per_shot = GlobalData.get_cost_per_shot(building_type)
	fire_range = GlobalData.get_fire_range(building_type)
	fire_rate = GlobalData.get_fire_rate(building_type)

func _config_ammo_bar() -> void:
	# setup ammo stock bar
	ammo_stock_bar.max_value = max_ammo_storage
	ammo_stock_bar.step = cost_per_shot
	ammo_stock_bar.value = 0
	# Starts hidden is activated after receiving the first ammo packet
	ammo_stock_bar.visible = false

# ----------------------
# --- Ammo Setter ------
# ----------------------
func _set_ammo(new_ammo: float) -> void:
	if current_ammo == new_ammo:
		return
	current_ammo = new_ammo
	state_updated.emit()
	_update_ammo_stock_bar(current_ammo)
	if current_ammo >= max_ammo_storage:
		is_full_ammo = true
	#prints("Current ammo:", current_ammo, "Full ammo:", is_full_ammo)
	if current_ammo <= 0.0:
		out_of_ammo_sprite.visible = true
	else:
		out_of_ammo_sprite.visible = false

# -------------------------------
# --- Packet Processing ----------
# -------------------------------
func _handle_received_ammo_packet() -> void:
	if not is_built:
		return
	current_ammo += 1

# -------------------------------
# --- Visuals Updating ----------
# -------------------------------
func _update_is_built_visuals():
	# Color the sprite based on whether the building is built
	if is_built:
		# Built: full color
		base_sprite.modulate = Color(1, 1, 1, 1)
		turret_sprite.modulate = Color(1, 1, 1, 1)
	else:
		# Not built: dimmed / greyed out
		base_sprite.modulate = Color(0.5, 0.5, 0.5, 1)
		turret_sprite.modulate = Color(0.5, 0.5, 0.5, 1)

# Update ammo bar
func _update_ammo_stock_bar(new_value: float) -> void:
	ammo_stock_bar.value = new_value
	# Only show bar if not full
	if ammo_stock_bar.value < max_ammo_storage:
		ammo_stock_bar.visible = true
	else:
		ammo_stock_bar.visible = false
