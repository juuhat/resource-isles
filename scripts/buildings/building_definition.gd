class_name BuildingDefinition
extends RefCounted

var id: int
var display_name: String
# One or two sentences on the building's role, shown in the build menu's details column.
var description: String = ""
var category: int
var texture: Texture2D
# Optional 3D model. When set, the renderer instances this instead of the flat texture.
var model: PackedScene = null
var cost: Dictionary
# Seconds of robot work to raise a placed blueprint into the finished building.
var build_seconds: float = 6.0
# The tiles the building covers, as axial hex offsets from its anchor tile (HexGrid.AXIAL_*,
# summed for tiles further out). The anchor, Vector2i.ZERO, comes first. The player turns the
# shape in 60-degree steps while placing it. See docs/building-footprints.md.
var footprint: Array[Vector2i] = [Vector2i.ZERO]
# Optional per-tile terrain rule, one entry per footprint tile: a non-empty Array[int] replaces
# required_terrains for that tile (e.g. the dock's second tile must be Coast).
var footprint_terrains: Array = []
# When the player's chosen rotation doesn't fit, placement tries the other five before giving up
# (the dock swings its pier toward whichever side the water is on).
var auto_rotate: bool = false
# Model authored with tools/lowpoly_kit.py at TILE (2) units per tile, its origin on the anchor
# tile's ground at the centroid of the footprint tiles' centres. The renderer then uses a fixed
# scale and places the origin directly, instead of fitting the model's bounds to
# visual_size_tiles, so parts may reach below the ground (the dock's pilings).
var true_tile_model: bool = false
# Footprint tiles (indices into footprint) with a floor units walk and stand on once the building
# is finished, even over water (the dock's pier), reached only from the building's own tiles.
# deck_height_tiles is that floor's height above the anchor tile's ground, in tiles.
var deck_tiles: Array[int] = []
var deck_height_tiles: float = 0.0
var visual_size_tiles: Vector2 = Vector2.ONE
var visual_offset_tiles: Vector2 = Vector2.ZERO
# Heading (degrees) applied around the Y axis when instancing a 3D model.
var visual_rotation_y: float = 0.0

# Optional spinning sub-mesh of the 3D model (e.g. a windmill's blades, a separate object
# in the .glb). When spin_node_name is set, the renderer finds that child and rotates it
# around spin_axis (model-local) at spin_speed_degrees per second.
var spin_node_name: String = ""
var spin_axis: Vector3 = Vector3(0, 0, 1)
var spin_speed_degrees: float = 45.0

# Whether the player can place this from the build menu. False for buildings that only
# exist via worldgen or story (e.g. the crashed spaceship) — you don't build those.
var player_buildable: bool = true
# Walked around like a resource node rather than straight through (HexPathfinder.step_cost). For
# landmarks only (the crashed spaceship): the player's own buildings stay walk-through, so they can
# never wall the robot in.
var solid: bool = false

# Footprint cells must sit on one of these terrains. List a single type for a strict
# requirement, several for a choice, or GameTypes.LAND_TERRAINS for any solid ground.
var required_terrains: Array[int] = []
# Each entry { kind, type } must have at least one matching neighbor for placement to be legal.
var required_adjacent: Array[Dictionary] = []
# Placement is blocked if any neighbor matches any { kind, type } entry here.
var forbidden_adjacent: Array[Dictionary] = []
# Each entry { kind, type, amount } grants amount per matching neighbor.
var adjacency_yields: Array[Dictionary] = []

# Production: -1 resource type means the building produces nothing.
var production_resource_type: int = -1
var production_base_amount: int = 0
var production_interval_seconds: float = 0.0

# Input a producer pulls from the inventory each cycle to make its output. -1
# means no input (a raw extractor like a logger's camp draws from the map, not
# stock). A processor (e.g. a sawmill) stalls until it can afford one batch.
var input_resource_type: int = -1
var input_amount: int = 0
# Additional processors can declare a whole batch here (e.g. ore + coal). The legacy
# single input remains supported for the sawmill; get_production_inputs combines them.
var production_inputs: Dictionary = {}
# A processor that can make more than one thing (the furnace smelts copper or iron): each entry is
# {output, inputs}, inputs as in production_inputs. A newly placed building runs the first; the
# player switches from its info panel and the choice is kept on the building (IslandData.get_recipe,
# BuildingManager.get_recipe). Set production_resource_type to the first output, so code that only
# asks whether the building produces anything still sees it does.
var recipes: Array[Dictionary] = []

# Power (MW): a constant rate, not a stockpile. Generators add power_generated
# while running; producers draw power_consumed while powered.
var power_generated: int = 0
var power_consumed: int = 0

# Fuel a generator burns to keep running. -1 resource type means no fuel needed
# (the generator always runs, e.g. a windmill).
var fuel_resource_type: int = -1
var fuel_amount: int = 0
var fuel_interval_seconds: float = 0.0


# Constructed with no arguments; every field is set by name at the call site (see
# building_definitions.gd) so each line reads as "this property = this value".

func get_production_inputs() -> Dictionary:
	var inputs := production_inputs.duplicate()
	if input_resource_type != -1 and input_amount > 0:
		inputs[input_resource_type] = int(inputs.get(input_resource_type, 0)) + input_amount
	return inputs
