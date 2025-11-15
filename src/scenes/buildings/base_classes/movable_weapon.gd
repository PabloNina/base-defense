# MovableWeapon - movable_weapon.gd
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
class_name MovableWeapon extends MovableBuilding
# -----------------------------------------
# --- Onready References ------------------
# -----------------------------------------
@onready var base_sprite: Sprite2D = $BaseSprite
@onready var turret_sprite: Sprite2D = $TurretSprite
@onready var ammo_stock_bar: ProgressBar = $AmmoStockBar
@onready var out_of_ammo_sprite: Sprite2D = $OutOfAmmoSprite
@onready var fire_rate_timer: Timer = $FireRateTimer
# -----------------------------------------
# --- Manager References ------------------
# -----------------------------------------
# A reference to the FlowManager used to query for ooze targets.
var flow_manager: FlowManager
# -----------------------------------------
# --- Weapon Settings ---------------------
# -----------------------------------------
var max_ammo_storage: int = 0
var cost_per_shot: float = 0.0
var fire_rate: float = 0.0
var fire_range: int = 0
# -----------------------------------------
# --- Private Variables -------------------
# -----------------------------------------
# This timer controls how often the weapon scans for a new target.
#var fire_rate_timer: Timer
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
	add_to_group("movable_weapons")
	# Get manager references to enable communication with the ooze simulation.
	flow_manager = get_tree().get_first_node_in_group("enemy_manager")
	# Setup the weapon
	_config_weapon_settings()
	_config_ammo_bar()
	# Configure the timer that dictates the weapon's fire rate.
	_config_fire_rate_timer()

func _process(_delta: float) -> void:
	# The weapon should only attempt to fire if it is not deactivated, fully built, and powered.
	if is_deactivated or not is_built or not is_powered:
		return

	# If the fire rate timer is stopped, it means the weapon is ready to fire again.
	if fire_rate_timer.is_stopped():
		fire_rate_timer.start()

# -----------------------------------------
# -------- Public Methods -----------------
# -----------------------------------------

# -------------------------------
# -- PacketInFlight Management --
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
# --- Ooze Targeting / Shooting -----
# -----------------------------------
## This function is called by the fire_rate_timer to find and engage ooze targets.
func _find_target() -> void:
	# Ensure the FlowManager is available before attempting to find a target.
	if not is_instance_valid(flow_manager):
		return

	# Request the nearest ooze tile from the FlowManager within the weapon's fire range.
	var target_tile: Vector2i = flow_manager.get_nearest_ooze_tile(global_position, fire_range)
	# If a valid target is found (i.e., not the default invalid vector), proceed.
	if target_tile != Vector2i(-1, -1):
		print("Target found at: ", target_tile)
		# TODO: Implement the actual shooting logic here.
		# Call shoot method
		_shoot_target(target_tile)
		# This would involve creating a projectile and firing it towards the target tile.

func _shoot_target(target_tile: Vector2i) -> void:
	var bullet: Bullet = GlobalData.BULLET_SCENE.instantiate()
	bullet.flow_manager = self.flow_manager
	bullet.target_tile = target_tile
	bullet.global_position = self.global_position
	add_child(bullet)
	if is_instance_valid(bullet):
		current_ammo -= cost_per_shot

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

func _config_fire_rate_timer() -> void:
	#fire_rate_timer = Timer.new()
	#add_child(fire_rate_timer)
	fire_rate_timer.wait_time = 1.0 / fire_rate
	# The timer will be restarted manually after each shot.
	fire_rate_timer.one_shot = true 
	# Connect the timer's timeout signal to the target-finding logic.
	fire_rate_timer.timeout.connect(_find_target)
	
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
		is_scheduled_to_full_ammo = false
	else:
		is_full_ammo = false
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
#func _update_is_built_visuals():
	# Color the sprite based on whether the building is built
	#if is_built:
		## Built: full color
		#base_sprite.modulate = Color(1, 1, 1, 1)
		#turret_sprite.modulate = Color(1, 1, 1, 1)
	#else:
		## Not built: dimmed / greyed out
		#base_sprite.modulate = Color(0.5, 0.5, 0.5, 1)
		#turret_sprite.modulate = Color(0.5, 0.5, 0.5, 1)

# Update ammo bar
func _update_ammo_stock_bar(new_value: float) -> void:
	ammo_stock_bar.value = new_value
	# Only show bar if not full
	if ammo_stock_bar.value < max_ammo_storage:
		ammo_stock_bar.visible = true
	else:
		ammo_stock_bar.visible = false
