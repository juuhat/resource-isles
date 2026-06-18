class_name ResourceDatabase
extends RefCounted

# Static catalog of every GameTypes.ResourceType's metadata — the single source of truth
# for display name, floating-text colour, UI icon and lifetime "gathered" Stat. Mirrors the
# ResourceNodeDatabase / BuildingDefinitions pattern, but kept static so the scattered
# (and partly static) call sites can read it without plumbing an instance through:
#   - ResourceManager.get_display_name_for_type()  (display name)
#   - main.gd / _resource_color()                  (colour)
#   - resource_bar.gd / _resource_icon()           (icon)
#   - stat_tracker.gd                              (gathered stat)
#
# To add a resource type: add its enum value and ONE entry below. Nothing else.

const ResourceDefinitionScript := preload("res://scripts/resources/resource_definition.gd")
const WOOD_ICON := preload("res://assets/icons/wood_log.png")
const STONE_ICON := preload("res://assets/icons/stone.png")
const PLANKS_ICON := preload("res://assets/icons/wood_plank.png")
const COAL_ICON := preload("res://assets/icons/coal_ore.png")

# Lazily built, then cached for the rest of the run. Keyed by ResourceType.
static var _definitions: Dictionary = {}


static func get_definition(resource_type: int) -> ResourceDefinition:
	if _definitions.is_empty():
		_build()
	return _definitions.get(resource_type)


static func _build() -> void:
	_add(ResourceDefinitionScript.new(
		GameTypes.ResourceType.WOOD,
		"Wood",
		Color("#d79a4f"),
		WOOD_ICON,
		GameTypes.Stat.WOOD_GATHERED
	))
	_add(ResourceDefinitionScript.new(
		GameTypes.ResourceType.STONE,
		"Stone",
		Color("#cfcfd6"),
		STONE_ICON,
		GameTypes.Stat.STONE_GATHERED
	))
	_add(ResourceDefinitionScript.new(
		GameTypes.ResourceType.PLANKS,
		"Planks",
		Color("#e8c07a"),
		PLANKS_ICON,
		GameTypes.Stat.PLANKS_GATHERED
	))
	# Iron ore reuses the stone icon as placeholder art until iron art exists.
	_add(ResourceDefinitionScript.new(
		GameTypes.ResourceType.IRON_ORE,
		"Iron Ore",
		Color("#b9794f"),
		STONE_ICON,
		GameTypes.Stat.IRON_ORE_GATHERED
	))
	_add(ResourceDefinitionScript.new(
		GameTypes.ResourceType.COAL,
		"Coal",
		Color("#5a5a64"),
		COAL_ICON,
		GameTypes.Stat.COAL_GATHERED
	))


static func _add(definition: ResourceDefinition) -> void:
	_definitions[definition.id] = definition
