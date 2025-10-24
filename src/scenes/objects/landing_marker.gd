class_name LandingMarker extends Area2D

const landing_marker_scene: PackedScene = preload("res://src/scenes/objects/landing_marker.tscn")

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var ghost_lines_container: Node2D = $GhostLines

signal is_placeable(value: bool, marker: LandingMarker)

var building_type: DataTypes.BUILDING_TYPE
var texture_to_use: Texture2D = null

var overlapping_areas: Array[Area2D] = []
const VALID_COLOR: Color = Color(1.0, 1.0, 1.0, 0.5)
const INVALID_COLOR: Color = Color(1.0, 0.0, 0.0, 0.5)

const GHOST_LINE_WIDTH: float = 1.0
const GHOST_LINE_COLOR: Color = Color(0.2, 1.0, 0.0, 0.6)
const GHOST_LINE_INVALID_COLOR: Color = Color(1.0, 0.2, 0.2, 0.6)

var _ghost_lines: Array[Line2D] = []
var _network_manager: NetworkManager

func _ready() -> void:
	sprite_2d.texture = texture_to_use
	var collision_shape_size = sprite_2d.texture.get_size() * sprite_2d.scale
	collision_shape_2d.shape.size = collision_shape_size
	
	# Connect signals
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

static func new_landing_marker(bdg_type: DataTypes.BUILDING_TYPE, landing_position: Vector2, network_manager: NetworkManager) -> LandingMarker:
	var new_marker = landing_marker_scene.instantiate() as LandingMarker
	new_marker.global_position = landing_position
	new_marker.building_type = bdg_type
	new_marker.texture_to_use = DataTypes.get_landing_marker_texture(bdg_type)
	new_marker._network_manager = network_manager
	return new_marker

func update_preview(new_position: Vector2) -> void:
	global_position = new_position
	_update_connection_ghosts()

func _on_area_entered(area: Area2D) -> void:
	overlapping_areas.append(area)
	_set_valid_color(false)
	is_placeable.emit(false, self)
	_update_connection_ghosts()

func _on_area_exited(area: Area2D) -> void:
	overlapping_areas.erase(area)
	if overlapping_areas.is_empty():
		_set_valid_color(true)
		is_placeable.emit(true, self)
	_update_connection_ghosts()

func _set_valid_color(valid: bool) -> void:
	sprite_2d.modulate = VALID_COLOR if valid else INVALID_COLOR

func _update_connection_ghosts() -> void:
	if building_type == DataTypes.BUILDING_TYPE.NULL or not is_visible():
		_clear_ghost_lines()
		return
	if not _network_manager:
		return

	var targets: Array = []
	for other in _network_manager.registered_buildings:
		if not is_instance_valid(other):
			continue
		if NetworkManager.can_buildings_connect(
			building_type,
			global_position,
			DataTypes.get_is_relay(building_type),
			other.building_type,
			other.global_position,
			other.is_relay
		):
			targets.append(other)

	while _ghost_lines.size() < targets.size():
		var line := Line2D.new()
		line.width = GHOST_LINE_WIDTH
		line.default_color = GHOST_LINE_COLOR
		ghost_lines_container.add_child(line)
		_ghost_lines.append(line)

	for i in range(_ghost_lines.size()):
		if i < targets.size():
			var t = targets[i]
			var l: Line2D = _ghost_lines[i]
			l.points = [global_position, t.global_position]
			l.global_position = Vector2.ZERO
			l.default_color = GHOST_LINE_COLOR if overlapping_areas.is_empty() else GHOST_LINE_INVALID_COLOR
			l.visible = true
		else:
			_ghost_lines[i].visible = false

func _clear_ghost_lines() -> void:
	for l in _ghost_lines:
		if is_instance_valid(l):
			l.queue_free()
	_ghost_lines.clear()
