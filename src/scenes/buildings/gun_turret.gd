class_name Weapon extends MovableBuilding

@onready var base_sprite: Sprite2D = $BaseSprite
@onready var turret_sprite: Sprite2D = $TurretSprite
@onready var ammo_stock_bar: ProgressBar = $AmmoStockBar
@onready var out_of_ammo_sprite: Sprite2D = $OutOfAmmoSprite

@export var max_ammo_storage: int = 10
@export var cost_per_shot: float = 0.25
@export var fire_rate: float = 0.5
@export var fire_range: int = 100

var is_full_ammo: bool = false
var current_ammo: float = 0.0: set = _set_ammo
var is_scheduled_to_full_ammo: bool = false

# -----------------------------------------
# --- Engine Callbacks --------------------
# -----------------------------------------
func _ready():
	super._ready()
	add_to_group("weapons")
	# setup ammo stock bar
	ammo_stock_bar.max_value = max_ammo_storage
	ammo_stock_bar.step = cost_per_shot
	ammo_stock_bar.value = 0
	# Starts hidden is activated after receiving the first ammo packet
	ammo_stock_bar.visible = false
	# hide Out of ammo sprite
	#out_of_ammo_sprite.visible = false

func _process(_delta: float) -> void:
	if is_deactivated:
		return
	# Add shooting logic here
	pass

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
# --- Packet Processing ----------
# -------------------------------
func _handle_received_ammo_packet() -> void:
	if not is_built:
		return
	current_ammo += 1

# ammo setter
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

# -------------------------------
# --- Visuals Updating ----------
# -------------------------------
func _updates_visuals():
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
