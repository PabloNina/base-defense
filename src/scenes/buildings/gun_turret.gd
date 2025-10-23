class_name Weapon extends MovableBuilding

@onready var base_sprite: Sprite2D = $BaseSprite
@onready var turret_sprite: Sprite2D = $TurretSprite
@onready var ammo_stock_bar: ProgressBar = $AmmoStockBar

@export var max_ammo_storage: int = 10
@export var cost_per_shot: float = 0.25
@export var fire_rate: float = 0.5
@export var fire_range: int = 150

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
func received_packet(packet_type: DataTypes.PACKETS):
	# Let parent handle the standard packet types
	if packet_type in [DataTypes.PACKETS.BUILDING, DataTypes.PACKETS.ENERGY]:
		super.received_packet(packet_type)
		return
	
	# Handle ammo separately
	match packet_type:
		DataTypes.PACKETS.AMMO:
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
	_update_ammo_stock_bar(current_ammo)
	if current_ammo >= max_ammo_storage:
		is_full_ammo = true
	#prints("Current ammo:", current_ammo, "Full ammo:", is_full_ammo)

# -------------------------------
# --- Packet Demand Query -------
# -------------------------------
func needs_packet(packet_type: DataTypes.PACKETS) -> bool:
	# If parent class needs this packet let it handle it
	if super.needs_packet(packet_type):
		return true
	
	# Handle ammo separately
	match packet_type:
		DataTypes.PACKETS.AMMO:
			## Needs ammo if built, powered, not fully stocked and not scheduled to full
			return is_built and is_powered and not is_full_ammo and not is_scheduled_to_full_ammo

		_:
			return false

# -------------------------------
# --- Visuals Updating ----------
# -------------------------------
func _updates_visuals():
	# Color the sprite based on whether the relay is built
	if is_built:
		# Built relay: full color
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
