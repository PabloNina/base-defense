# =========================================
# DataTypes.gd
# =========================================
# Centralized global enums and metadata tables for consistency across systems
class_name DataTypes
extends Node


# --------------------------------------------
# --- Enumerations ---------------------------
# --------------------------------------------

# Packet types
enum PACKETS {NULL, BUILDING, ENERGY, AMMO, ORE, TECH}

# Player Buildings
enum BUILDING_TYPE {NULL, COMMAND_CENTER, RELAY, GENERATOR, GUN_TURRET}

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

const BUILDINGS_DATA: Dictionary = {
	BUILDING_TYPE.COMMAND_CENTER: {
		#"scene_path": "res://Scenes/Buildings/CommandCenter.tscn",
		"ghost_texture": preload("res://assets/sprites/buildings/command_center.png"),
		"tilemap_id": 3,
		"display_name": "Command Center",
		"cost": 0,
	},
	BUILDING_TYPE.RELAY: {
		#"scene_path": "res://Scenes/Buildings/Relay.tscn",
		"ghost_texture": preload("res://assets/sprites/buildings/energy_relay.png"),
		"tilemap_id": 5,
		"display_name": "Relay",
		"cost": 2,
	},
	BUILDING_TYPE.GENERATOR: {
		#"scene_path": "res://Scenes/Buildings/Mine.tscn",
		"ghost_texture": preload("res://assets/sprites/buildings/energy_generator.png"),
		"tilemap_id": 4,
		"display_name": "Generator",
		"cost": 5,
	},
	BUILDING_TYPE.GUN_TURRET: {
		#"scene_path": "res://Scenes/Buildings/ResearchLab.tscn",
		"ghost_texture": preload("res://assets/sprites/buildings/cannon_base.png"),
		"tilemap_id": 6,
		"display_name": "Gun Turret",
		"cost": 3,
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

#static func get_scene_path(building_type: int) -> String:
	#var data = get_building_data(building_type)
	#return data.get("scene_path", "")
