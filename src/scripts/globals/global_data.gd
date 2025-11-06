# GlobalData - global_data.gd
# ============================================================================
# This autoloaded singleton script serves as a central repository for global
# constants, enumerations, and metadata tables used throughout the game.
# Its purpose is to ensure consistency, provide a single source of truth for
# game-wide data, and facilitate easy access to commonly used resources and
# configurations.
#
# Key Responsibilities:
# - Centralized Constants: Defines game-wide constants such as TILE_SIZE.
#
# - Enumerations: Provides a comprehensive set of enumerations for various
#   game entities like PACKETS, BUILDING_TYPE, BUILDING_CATEGORY, and
#   BUILDING_ACTIONS, promoting type safety and readability.
#
# - Metadata Tables: Stores detailed metadata for game elements, such as
#   BUILDINGS_DATA, which includes packed scenes, ghost textures, costs,
#   and other configuration details for different building types.
#
# - Data Accessors: Offers static helper functions to easily retrieve specific
#   pieces of data from the metadata tables, abstracting away the underlying
#   dictionary structure.
#
# - Resource Preloading: Preloads essential scenes and textures to ensure they
#   are readily available when needed, reducing load times during gameplay.
# ============================================================================
class_name GlobalData extends Node
# --------------------------------------------
# --- Constants ------------------------------
# --------------------------------------------
const TILE_SIZE: int = 16
# --------------------------------------------
# --- Preloads -------------------------------
# --------------------------------------------
# PackedScenes
const CONNECTION_LINE_SCENE: PackedScene = preload("res://src/scenes/objects/connection_lines/connection_line.tscn")
const GHOST_PREVIEW_SCENE: PackedScene = preload("res://src/scenes/objects/ghost_previews/ghost_preview.tscn")
const PACKET_SCENE: PackedScene = preload("res://src/scenes/objects/packets/base_packet.tscn")
# Textures2D
const GREEN_PACKET_TEXTURE: Texture2D = preload("res://assets/sprites/objects/energy_packet.png")
const RED_PACKET_TEXTURE:Texture2D = preload("res://assets/sprites/objects/ammo_packet.png")
const BLUE_PACKET_TEXTURE:Texture2D = preload("res://assets/sprites/objects/building_packet.png")
# --------------------------------------------
# --- Enumerations ---------------------------
# --------------------------------------------
# Packet types
enum PACKETS {NULL, BUILDING, ENERGY, AMMO, ORE, TECH}
# Player Buildings 
enum BUILDING_TYPE {NULL, COMMAND_CENTER, RELAY, GENERATOR, GUN_TURRET, MORTAR, ORE_MINE, FACTORY, RESEARCH_CENTER}
# Buildings categories
enum BUILDING_CATEGORY {NULL, INFRASTRUCTURE, WEAPON, SPECIAL}
# Buildings actions
enum BUILDING_ACTIONS {DESTROY, MOVE, STOP_RESSUPLY, DEACTIVATE} 

# Enemy Structures
# TO DO
# Enemy types
# TO DO

# --------------------------------------------
# --- Buildings Metadata Dictionary ----------
# --------------------------------------------
# Each building entry stores:
# - scene: packed scene for placement
# - ghost_texture: preview placement sprite
# - tilemap_id: ID used in tilemap collections
# - display_name: for UI labels
# - cost: for resource logic
# - optimal_building_distance_tiles: in tile units
# - connection_range_tiles: in tile units
# - add more and comment
const BUILDINGS_DATA: Dictionary = {
	BUILDING_TYPE.COMMAND_CENTER: {
		"packed_scene": preload("res://src/scenes/buildings/command_center.tscn"),
		"ghost_texture": preload("res://assets/sprites/buildings/command_center.png"),
		"display_name": "Base",
		"cost_to_build": 0,
		"connection_range_tiles": 8,
		"is_relay": true,
		"upkeep_cost": 0.0,
		"optimal_building_distance_tiles": 0,
		"building_category": BUILDING_CATEGORY.SPECIAL,
		"building_actions": [BUILDING_ACTIONS.DESTROY]
		# Command_Center class only
		# default packet prod
		# default max storage
	},
	BUILDING_TYPE.RELAY: {
		"packed_scene": preload("res://src/scenes/buildings/relay.tscn"),
		"ghost_texture": preload("res://assets/sprites/buildings/energy_relay.png"),
		"display_name": "Relay",
		"cost_to_build": 2,
		"connection_range_tiles": 8,
		"is_relay": true,
		"upkeep_cost": 0.5,
		"optimal_building_distance_tiles": 8,
		"building_category": BUILDING_CATEGORY.INFRASTRUCTURE,
		"building_actions": [BUILDING_ACTIONS.DESTROY]
		# Relay class only
	},
	BUILDING_TYPE.GENERATOR: {
		"packed_scene": preload("res://src/scenes/buildings/generator.tscn"),
		"ghost_texture": preload("res://assets/sprites/buildings/energy_generator.png"),
		"display_name": "Reactor",
		"cost_to_build": 5,
		"connection_range_tiles": 5,
		"is_relay": false,
		"upkeep_cost": 0.5,
		"optimal_building_distance_tiles": 1,
		"building_category": BUILDING_CATEGORY.INFRASTRUCTURE,
		"building_actions": [BUILDING_ACTIONS.DESTROY, BUILDING_ACTIONS.DEACTIVATE],
		# Generator class only
		# packet bonus
	},
	BUILDING_TYPE.GUN_TURRET: {
		"packed_scene": preload("res://src/scenes/buildings/gun_turret.tscn"),
		"ghost_texture": preload("res://assets/sprites/buildings/cannon_base.png"),
		"display_name": "Cannon",
		"cost_to_build": 3,
		"connection_range_tiles": 6,
		"is_relay": false,
		"upkeep_cost": 1.0,
		"optimal_building_distance_tiles": 3,
		"building_category": BUILDING_CATEGORY.WEAPON,
		"building_actions": [BUILDING_ACTIONS.DESTROY, BUILDING_ACTIONS.DEACTIVATE, BUILDING_ACTIONS.MOVE],
		# Weapon class only
		"landing_marker_texture": preload("res://assets/sprites/buildings/landing_marker.png"),
		"max_ammo_storage": 10,
		"cost_per_shot": 0.25,
		"fire_rate": 0.5,
		"fire_range": 100,
	},
}

# --------------------------------------------
# --- Buildings Metadata Accessors -----------
# --------------------------------------------
static func get_building_data(building_type: int) -> Dictionary:
	return BUILDINGS_DATA.get(building_type, {})

static func get_ghost_texture(building_type: int) -> Texture2D:
	var data = get_building_data(building_type)
	return data.get("ghost_texture", null)

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

static func get_fire_range(building_type: GlobalData.BUILDING_TYPE) -> int:
	var data = get_building_data(building_type)
	return data.get("fire_range", -1)

static func get_optimal_building_distance(building_type: GlobalData.BUILDING_TYPE) -> float:
	var data = get_building_data(building_type)
	var distance_in_tiles = data.get("optimal_building_distance_tiles", 0)
	return float(distance_in_tiles * TILE_SIZE)

static func get_cost_to_build(building_type: GlobalData.BUILDING_TYPE) -> int:
	var data = get_building_data(building_type)
	return data.get("cost_to_build", -1)

static func get_upkeep_cost(building_type: GlobalData.BUILDING_TYPE) -> float:
	var data = get_building_data(building_type)
	return data.get("upkeep_cost", -1.0)

static func get_packed_scene(building_type: int) -> PackedScene:
	var data = get_building_data(building_type)
	return data.get("packed_scene", null)

static func get_building_category(building_type: GlobalData.BUILDING_TYPE) -> GlobalData.BUILDING_CATEGORY:
	var data = get_building_data(building_type)
	return data.get("building_category", -1)

static func get_max_ammo_storage(building_type: GlobalData.BUILDING_TYPE) -> int:
	var data = get_building_data(building_type)
	return data.get("max_ammo_storage", -1)

static func get_building_actions(building_type: GlobalData.BUILDING_TYPE) -> Array[GlobalData.BUILDING_ACTIONS]:
	var data = get_building_data(building_type)
	# Retrieve the raw actions data, which is a generic Array from the dictionary.
	var actions_data: Array = data.get("building_actions", [])
	# Create a new typed Array to match the function's return type hint.
	var typed_actions: Array[GlobalData.BUILDING_ACTIONS] = []
	# Assign the elements from the generic array to the newly created typed array.
	typed_actions.assign(actions_data)
	return typed_actions
