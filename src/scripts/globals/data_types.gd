# =========================================
# DataTypes.gd
# =========================================
# Centralized global enums and metadata tables for consistency across systems
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
# - add more and comment
const BUILDINGS_DATA: Dictionary = {
	BUILDING_TYPE.COMMAND_CENTER: {
		#"scene_path": "res://Scenes/Buildings/CommandCenter.tscn",
		"ghost_texture": preload("res://assets/sprites/buildings/command_center.png"),
		"tilemap_id": 3,
		"display_name": "Command Center",
		"cost_to_build": 0,
		"connection_range": 125.0,
		"is_relay": true,
		"upkeep_cost": 0.0,
	},
	BUILDING_TYPE.RELAY: {
		#"scene_path": "res://Scenes/Buildings/Relay.tscn",
		"ghost_texture": preload("res://assets/sprites/buildings/energy_relay.png"),
		"tilemap_id": 5,
		"display_name": "Relay",
		"cost_to_build": 2,
		"connection_range": 125.0,
		"is_relay": true,
		"upkeep_cost": 0.0,
	},
	BUILDING_TYPE.GENERATOR: {
		#"scene_path": "res://Scenes/Buildings/Mine.tscn",
		"ghost_texture": preload("res://assets/sprites/buildings/energy_generator.png"),
		"tilemap_id": 4,
		"display_name": "Generator",
		"cost_to_build": 5,
		"connection_range": 75.0,
		"is_relay": false,
		"upkeep_cost": 0.0,
	},
	BUILDING_TYPE.GUN_TURRET: {
		#"scene_path": "res://Scenes/Buildings/ResearchLab.tscn",
		"ghost_texture": preload("res://assets/sprites/buildings/cannon_base.png"),
		"tilemap_id": 6,
		"display_name": "Gun Turret",
		"cost_to_build": 3,
		"connection_range": 90.0,
		"is_relay": false,
		"upkeep_cost": 0.0,
		"landing_marker_texture": preload("res://assets/sprites/buildings/landing_marker.png"),
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
	return data.get("connection_range", 0.0)

static func get_is_relay(building_type: int) -> bool:
	var data = get_building_data(building_type)
	return data.get("is_relay", null)

static func get_landing_marker_texture(building_type: int) -> Texture2D:
	var data = get_building_data(building_type)
	return data.get("landing_marker_texture", null)

static func get_fire_range(building_type: DataTypes.BUILDING_TYPE) -> int:
	var data = get_building_data(building_type)
	return data.get("fire_range", -1)

#static func get_scene_path(building_type: int) -> String:
	#var data = get_building_data(building_type)
	#return data.get("scene_path", "")
