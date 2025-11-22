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
const TILE_SIZE_VECTOR2: Vector2 = Vector2(TILE_SIZE, TILE_SIZE)

const BUILDABLE_TILE_ID = 7

const WALL_TERRAIN_ID = 0
const GROUND_LVL1_TERRAIN_ID = 1
const GROUND_LVL2_TERRAIN_ID = 2
const GROUND_LVL3_TERRAIN_ID = 3
const GROUND_LVL4_TERRAIN_ID = 4
const GROUND_LVL5_TERRAIN_ID = 5

const BOX_VALID_COLOR: Color = Color.GREEN
const BOX_INVALID_COLOR: Color = Color.RED
const LINE_VALID_COLOR: Color = Color(0.2, 1.0, 0.0, 0.6)
const LINE_INVALID_COLOR: Color = Color(1.0, 0.2, 0.2, 0.6)
const FIRE_RANGE_COLOR: Color = Color(1.0, 0.2, 0.2, 0.2)
const FIRE_RANGE_SAME_HEIGHT_COLOR: Color = Color(0.2, 1.0, 0.2, 0.2)
const FIRE_RANGE_LOWER_HEIGHT_COLOR: Color = Color(1.0, 1.0, 0.2, 0.2)
# --------------------------------------------
# --- Preloads -------------------------------
# --------------------------------------------
# PackedScenes
const CONNECTION_LINE_SCENE: PackedScene = preload("uid://bxt6vth3tar67")
const GHOST_PREVIEW_SCENE: PackedScene = preload("uid://c8t5w2j2qg3j")
const PACKET_SCENE: PackedScene = preload("uid://by7nkqhi30wjd")
const BULLET_SCENE: PackedScene = preload("uid://b0pme20rpv8x4")
#Textures2D
const GREEN_PACKET_TEXTURE: Texture2D = preload("uid://bxdghtbrpoc1r")
const RED_PACKET_TEXTURE:Texture2D = preload("uid://dumwgtbqb3ci8")
const BLUE_PACKET_TEXTURE:Texture2D = preload("uid://dbuicd3klgwq1")
# --------------------------------------------
# --- Enumerations ---------------------------
# --------------------------------------------
# Packet types
enum PACKETS {NULL, BUILDING, ENERGY, AMMO, ORE, TECH}
# Player Buildings 
enum BUILDING_TYPE {NULL, COMMAND_CENTER, RELAY, REACTOR, CANNON, MORTAR, ORE_MINE, FACTORY, RESEARCH_CENTER}
# Buildings categories
enum BUILDING_CATEGORY {NULL, INFRASTRUCTURE, WEAPON, SPECIAL}
# Buildings actions
enum BUILDING_ACTIONS {DESTROY, MOVE, STOP_RESSUPLY, DEACTIVATE} 
# Weapon Targeting Rules
enum WEAPON_TARGETING_RULE {IGNORE_HEIGHT, SAME_OR_LOWER_HEIGHT}
# Enemy Structures
enum ENEMY_STRUCTURES {EMITTER}
# Enemy types
enum ENEMY_TYPES {OOZE}


# --------------------------------------------
# --- Game Data Dictionaries -----------------
# --------------------------------------------
## A dictionary to map terrain IDs from to integer height values.
const TERRAIN_ID_TO_HEIGHT: Dictionary = {
	GROUND_LVL1_TERRAIN_ID: 1,
	GROUND_LVL2_TERRAIN_ID: 2,
	GROUND_LVL3_TERRAIN_ID: 3,
	GROUND_LVL4_TERRAIN_ID: 4,
	GROUND_LVL5_TERRAIN_ID: 5,
}

## Buildings metadata
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
		"optimal_building_distance_tiles": 7,
		"building_category": BUILDING_CATEGORY.INFRASTRUCTURE,
		"building_actions": [BUILDING_ACTIONS.DESTROY]
		# Relay class only
		# packet bonus speed 
	},
	BUILDING_TYPE.REACTOR: {
		"packed_scene": preload("res://src/scenes/buildings/reactor.tscn"),
		"ghost_texture": preload("res://assets/sprites/buildings/energy_generator.png"),
		"display_name": "Reactor",
		"cost_to_build": 5,
		"connection_range_tiles": 5,
		"is_relay": false,
		"upkeep_cost": 0.5,
		"optimal_building_distance_tiles": 1,
		"building_category": BUILDING_CATEGORY.INFRASTRUCTURE,
		"building_actions": [BUILDING_ACTIONS.DESTROY, BUILDING_ACTIONS.DEACTIVATE],
		# Reactor class only
		"packet_production_bonus": 5.0
	},
	BUILDING_TYPE.CANNON: {
		"packed_scene": preload("res://src/scenes/buildings/cannon.tscn"),
		"ghost_texture": preload("res://assets/sprites/buildings/cannon_base.png"),
		"display_name": "Cannon",
		"cost_to_build": 3,
		"connection_range_tiles": 6,
		"is_relay": false,
		"upkeep_cost": 1.0,
		"optimal_building_distance_tiles": 3,
		"building_category": BUILDING_CATEGORY.WEAPON,
		"building_actions": [BUILDING_ACTIONS.DESTROY, BUILDING_ACTIONS.DEACTIVATE, BUILDING_ACTIONS.MOVE],
		# MovableBuilding class only
		"landing_marker_texture": preload("res://assets/sprites/buildings/landing_marker.png"),
		# MovableWeapon class only
		"max_ammo_storage": 10,
		"cost_per_shot": 0.25,
		"fire_rate": 2,
		"fire_range_tiles": 6,
		"targeting_rule": WEAPON_TARGETING_RULE.SAME_OR_LOWER_HEIGHT,
	},
}

# --------------------------------------------
# --- Buildings Metadata Accessors -----------
# --------------------------------------------
static func get_building_data(building_type: int) -> Dictionary:
	return BUILDINGS_DATA.get(building_type, {})

# Building Base Class
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

static func get_optimal_building_distance(building_type: GlobalData.BUILDING_TYPE) -> int:
	var data = get_building_data(building_type)
	var distance_in_tiles = data.get("optimal_building_distance_tiles", 0)
	return int(distance_in_tiles * TILE_SIZE)

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

static func get_building_actions(building_type: GlobalData.BUILDING_TYPE) -> Array[GlobalData.BUILDING_ACTIONS]:
	var data = get_building_data(building_type)
	# Retrieve the raw actions data, which is a generic Array from the dictionary.
	var actions_data: Array = data.get("building_actions", [])
	# Create a new typed Array to match the function's return type hint.
	var typed_actions: Array[GlobalData.BUILDING_ACTIONS] = []
	# Assign the elements from the generic array to the newly created typed array.
	typed_actions.assign(actions_data)
	return typed_actions

# Generator class only
static func get_packet_production_bonus(building_type: GlobalData.BUILDING_TYPE) -> float:
	var data = get_building_data(building_type)
	return data.get("packet_production_bonus", -1.0)

# MovableBuilding Class
static func get_landing_marker_texture(building_type: int) -> Texture2D:
	var data = get_building_data(building_type)
	return data.get("landing_marker_texture", null)

# Weapon Class
static func get_max_ammo_storage(building_type: GlobalData.BUILDING_TYPE) -> int:
	var data = get_building_data(building_type)
	return data.get("max_ammo_storage", -1)

static func get_fire_range(building_type: GlobalData.BUILDING_TYPE) -> int:
	var data = get_building_data(building_type)
	var fire_range_in_tiles = data.get("fire_range_tiles", -1)
	return int(fire_range_in_tiles * TILE_SIZE)

static func get_cost_per_shot(building_type: GlobalData.BUILDING_TYPE) -> float:
	var data = get_building_data(building_type)
	return data.get("cost_per_shot", -1.0)

static func get_fire_rate(building_type: GlobalData.BUILDING_TYPE) -> float:
	var data = get_building_data(building_type)
	return data.get("fire_rate", -1.0)

static func get_targeting_rule(building_type: GlobalData.BUILDING_TYPE) -> WEAPON_TARGETING_RULE:
	var data = get_building_data(building_type)
	return data.get("targeting_rule", WEAPON_TARGETING_RULE.IGNORE_HEIGHT)

# --------------------------------------------
# --- Other Accessors ------------------------
# --------------------------------------------
# Returns an integer height value for a given terrain ID.
static func get_height_from_terrain_id(terrain_id: int) -> int:
	return TERRAIN_ID_TO_HEIGHT.get(terrain_id, -1)
