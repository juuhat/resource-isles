class_name IslandProfile
extends RefCounted

# A biome recipe for IslandGenerator: the CONTRACT it must satisfy (which base terrain, which
# resources, which landmarks). The per-island seed varies the EXPRESSION (exact silhouette and
# layout) within this contract. Add biomes in IslandProfiles, not here. See
# docs/island-generation.md.

var biome: int
var width: int
var height: int
var sand_border_width: int
var coast_rings: int
# Visual base terrain the island body is carved from. This is identity + (future) adjacency
# bonus — NOT a building-placement gate (see docs/island-generation.md).
var primary_terrain: int
# Optional terrain patches stamped onto the base after carving. Each entry: {terrain, count}.
# Built with terrain_feature(). Example: the starter stamps a STONE patch onto its grass.
var terrain_features: Array = []
# Resource nodes to scatter. Each entry: {node_type, count, cluster}. Built with resource_entry().
# A node is only placed on terrain it is allowed on (IslandData._terrain_for_resource).
var resource_table: Array = []
# Worldgen-forced landmarks, normally starter-only.
var place_crashed_spaceship: bool = false
var place_starter_tools: bool = false


func _init(
	new_biome: int,
	new_primary_terrain: int,
	new_width: int,
	new_height: int,
	new_sand_border_width: int = 1,
	new_coast_rings: int = 2
) -> void:
	biome = new_biome
	primary_terrain = new_primary_terrain
	width = new_width
	height = new_height
	sand_border_width = new_sand_border_width
	coast_rings = new_coast_rings


static func terrain_feature(terrain_type: int, count: int = 1) -> Dictionary:
	return {terrain = terrain_type, count = count}


# cluster=true places `count` 3-cell clusters (like the starter forest); false scatters `count`
# single nodes.
static func resource_entry(node_type: int, count: int, cluster: bool = false) -> Dictionary:
	return {node_type = node_type, count = count, cluster = cluster}
