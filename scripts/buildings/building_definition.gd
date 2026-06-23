class_name BuildingDefinition
extends RefCounted

var id: int
var display_name: String
var category: int
var texture: Texture2D
# Optional 3D model. When set, the renderer instances this instead of the flat texture.
var model: PackedScene = null
var cost: Dictionary
var footprint_size: Vector2i = Vector2i.ONE
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
