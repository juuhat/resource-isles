class_name IslandProfiles
extends RefCounted

# Static catalog of biome profiles plus the coord -> biome mapping. The generator stays generic;
# every biome's personality lives here as data. Add a biome = add a profile + a mapping rule.
# See docs/island-generation.md.

const IslandProfileScript := preload("res://scripts/island/island_profile.gd")

enum Biome {
	STARTER, # ring 0 home: grass, wood + stone, the crash site
	STONE,   # ring 1 frontier: rocky, iron + coal + stone, no wood (docs/second-island-progression.md)
}

const ISLAND_WIDTH := 30
const ISLAND_HEIGHT := 24


# Which biome generates at a world-map coord. CENTER is the crash site; every other slot is a
# STONE frontier colony for now (the only frontier biome authored). This becomes ring-based once
# more biomes exist — see docs/island-generation.md.
static func biome_for_coord(coord: Vector2i) -> int:
	if coord == Vector2i.ZERO:
		return Biome.STARTER
	return Biome.STONE


static func get_profile(biome: int) -> IslandProfile:
	match biome:
		Biome.STONE:
			return _stone_profile()
		_:
			return _starter_profile()


# Ring-0 home: a green island with a forest cluster, a rock patch to quarry, and a couple of
# loose stone deposits — plus the crash site and the robot's scattered tools.
static func _starter_profile() -> IslandProfile:
	var profile := IslandProfileScript.new(
		Biome.STARTER, GameTypes.Terrain.GRASS, ISLAND_WIDTH, ISLAND_HEIGHT
	)
	profile.terrain_features = [IslandProfileScript.terrain_feature(GameTypes.Terrain.STONE, 1)]
	profile.resource_table = [
		IslandProfileScript.resource_entry(GameTypes.ResourceNodeType.TREE, 1, true),
		IslandProfileScript.resource_entry(GameTypes.ResourceNodeType.STONE, 2, false),
	]
	profile.place_crashed_spaceship = true
	profile.place_starter_tools = true
	return profile


# Ring-1 iron + coal + stone colony: rocky base, no wood. Stone is local (the "gentle first
# colony" lever — build with local rock, import only wood via trade route). See
# docs/second-island-progression.md.
static func _stone_profile() -> IslandProfile:
	var profile := IslandProfileScript.new(
		Biome.STONE, GameTypes.Terrain.STONE, ISLAND_WIDTH, ISLAND_HEIGHT
	)
	profile.resource_table = [
		IslandProfileScript.resource_entry(GameTypes.ResourceNodeType.IRON_ORE, 3, false),
		IslandProfileScript.resource_entry(GameTypes.ResourceNodeType.COAL, 2, false),
		IslandProfileScript.resource_entry(GameTypes.ResourceNodeType.STONE, 3, false),
	]
	return profile
