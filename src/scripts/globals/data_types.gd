# =========================================
# DataTypes.gd
# =========================================
# Centralized global consts, enums and metadata tables for consistency across systems
class_name DataTypes extends Node
# --------------------------------------------
# --- Enumerations ---------------------------
# --------------------------------------------
# Packet types
enum PACKETS {NULL, BUILDING, ENERGY, AMMO, ORE, TECH}
# Player Buildings
enum BUILDING_TYPE {NULL, COMMAND_CENTER, RELAY, GENERATOR, GUN_TURRET}
# Buildings actions
enum BUILDING_ACTIONS {DESTROY, MOVE, STOP_RESSUPLY, DISABLE} 
# Enemy Structures
# TO DO
# Enemy types
# TO DO

# --------------------------------------------
# --- Buildings Metadata ---------------------
# --------------------------------------------
# Each building entry stores:
# - scene_path: packed scene for placement
# - ghost_texture: preview ghost sprite
# - tilemap_id: ID used in tilemap collections
# - display_name: for UI labels
# - cost: for resource logic
# - optimal_building_distance_tiles: in tile units
# - connection_range_tiles: in tile units
# - add more and comment
const TILE_SIZE: int = 16
const BUILDINGS_DATA: Dictionary = {
	BUILDING_TYPE.COMMAND_CENTER: {
		#"scene_path": "res://Scenes/Buildings/CommandCenter.tscn",
		"ghost_texture": preload("res://assets/sprites/buildings/command_center.png"),
		"tilemap_id": 3,
		"display_name": "Command Center",
		"cost_to_build": 0,
		"connection_range_tiles": 8,
		"is_relay": true,
		"upkeep_cost": 0.0,
		"optimal_building_distance_tiles": 0,
		# Command_Center class only
	},
	BUILDING_TYPE.RELAY: {
		#"scene_path": "res://Scenes/Buildings/Relay.tscn",
		"ghost_texture": preload("res://assets/sprites/buildings/energy_relay.png"),
		"tilemap_id": 5,
		"display_name": "Relay",
		"cost_to_build": 2,
		"connection_range_tiles": 8,
		"is_relay": true,
		"upkeep_cost": 0.5,
		"optimal_building_distance_tiles": 8,
		# Relay class only
	},
	BUILDING_TYPE.GENERATOR: {
		#"scene_path": "res://Scenes/Buildings/Mine.tscn",
		"ghost_texture": preload("res://assets/sprites/buildings/energy_generator.png"),
		"tilemap_id": 4,
		"display_name": "Generator",
		"cost_to_build": 5,
		"connection_range_tiles": 5,
		"is_relay": false,
		"upkeep_cost": 0.5,
		"optimal_building_distance_tiles": 1,
		# Generator class only
	},
	BUILDING_TYPE.GUN_TURRET: {
		#"scene_path": "res://Scenes/Buildings/ResearchLab.tscn",
		"ghost_texture": preload("res://assets/sprites/buildings/cannon_base.png"),
		"tilemap_id": 6,
		"display_name": "Gun Turret",
		"cost_to_build": 3,
		"connection_range_tiles": 6,
		"is_relay": false,
		"upkeep_cost": 1.0,
		"optimal_building_distance_tiles": 3,
		# Weapon class only
		"landing_marker_texture": preload("res://assets/sprites/buildings/landing_marker.png"),
		"max_ammo_storage": 10,
		"cost_per_shot": 0.25,
		"fire_rate": 0.5,
		"fire_range": 100,
	},
}


# --------------------------------------------
# --- Utility Accessors ----------------------
# --------------------------------------------
static func get_building_data(building_type: int) -> Dictionary:
	return BUILDINGS_DATA.get(building_type, {})

static func get_ghost_texture(building_type: int) -> Texture2D:
	var data = get_building_data(building_type)
	return data.get("ghost_texture", null)

static func get_tilemap_id(building_type: DataTypes.BUILDING_TYPE) -> int:
	var data = get_building_data(building_type)
	return data.get("tilemap_id", -1)

static func get_display_name(building_type: int) -> String:
	var data = get_building_data(building_type)
	return data.get("display_name", "")

static func get_connection_range(building_type: int) -> float:
	var data = get_building_data(building_type)
	var range_in_tiles = data.get("connection_range_tiles", 0)
	return float(range_in_tiles * TILE_SIZE)

static func get_is_relay(building_type: int) -> bool:
	var data = get_building_data(building_type)
	return data.get("is_relay", null)

static func get_landing_marker_texture(building_type: int) -> Texture2D:
	var data = get_building_data(building_type)
	return data.get("landing_marker_texture", null)

static func get_fire_range(building_type: DataTypes.BUILDING_TYPE) -> int:
	var data = get_building_data(building_type)
	return data.get("fire_range", -1)

static func get_optimal_building_distance(building_type: DataTypes.BUILDING_TYPE) -> float:
	var data = get_building_data(building_type)
	var distance_in_tiles = data.get("optimal_building_distance_tiles", 0)
	return float(distance_in_tiles * TILE_SIZE)

static func get_cost_to_build(building_type: DataTypes.BUILDING_TYPE) -> int:
	var data = get_building_data(building_type)
	return data.get("cost_to_build", -1)

static func get_upkeep_cost(building_type: DataTypes.BUILDING_TYPE) -> float:
	var data = get_building_data(building_type)
	return data.get("upkeep_cost", -1.0)

#static func get_scene_path(building_type: int) -> String:
	#var data = get_building_data(building_type)
	#return data.get("scene_path", "")
