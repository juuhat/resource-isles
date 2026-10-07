class_name WorldMap
extends RefCounted

# Every island in the world and where it goes, read from assets/world/world_map.cfg: one ConfigFile
# section per island, named by its id, saying which IslandDesign to place, where its middle sits,
# how it is turned, and its role. See docs/world-map-and-island-designs.md.
#
#   [copper_isle]
#   design = "copper_01"          ; assets/world/islands/copper_01.island
#   center = Vector2i(-25, -58)   ; the world cell the design's middle lands on
#   rotation = 0                  ; 60-degree steps counter-clockwise (optional)
#   mirror = false                ; flip east-west before turning (optional)
#   name = "Copper Isle"          ; shown on the map (optional)
#   k9da = true                   ; K9-DA waits here, at the design's k9da marker
#
# Exactly one island has start = true (the crash site, where the robot begins) and one k9da = true.

const IslandDesignScript := preload("res://scripts/island/island_design.gd")

const PATH := "res://assets/world/world_map.cfg"
# Every key an island can have, and the type its value must be.
const KEYS := {
	design = TYPE_STRING,
	center = TYPE_VECTOR2I,
	rotation = TYPE_INT,
	mirror = TYPE_BOOL,
	name = TYPE_STRING,
	start = TYPE_BOOL,
	k9da = TYPE_BOOL,
}
const REQUIRED_KEYS: Array[String] = ["design", "center"]
const ROLES: Array[String] = ["start", "k9da"]

# Every island on the map, in file order.
var placements: Array[Placement] = []
# What is wrong with the map, one line each. Don't build a world from a map with errors.
var errors: PackedStringArray = []


# One island on the map: a section of the file.
class Placement:
	var id: StringName
	var design := ""
	var center := Vector2i.ZERO
	var rotation := 0
	var mirror := false
	var name := ""
	var start := false
	var k9da := false


static func load_file(path := PATH) -> WorldMap:
	if not FileAccess.file_exists(path):
		var missing := WorldMap.new()
		missing.errors.append("%s: there is no world map file" % path)
		return missing
	return parse(FileAccess.get_file_as_string(path))


# Reads a map from the text of a world_map.cfg. Whatever is wrong with it goes in errors.
static func parse(text: String) -> WorldMap:
	var map := WorldMap.new()
	var config := ConfigFile.new()
	var result := config.parse(text)
	if result != OK:
		map.errors.append("world map: it doesn't read as a ConfigFile (%s); look for a missing quote or bracket"
			% error_string(result))
		return map
	map._find_repeats(text)
	for id in config.get_sections():
		map._read_placement(config, id)
	for role in ROLES:
		map._count_role(role)
	return map


func _read_placement(config: ConfigFile, id: String) -> void:
	var placement := Placement.new()
	placement.id = StringName(id)
	for key in config.get_section_keys(id):
		if not KEYS.has(key):
			errors.append("[%s]: unknown key %s; the keys are %s"
				% [id, key, ", ".join(PackedStringArray(KEYS.keys()))])
			continue
		var value: Variant = config.get_value(id, key)
		if typeof(value) != KEYS[key]:
			errors.append("[%s]: %s should be a %s, not %s" % [id, key, type_string(KEYS[key]), var_to_str(value)])
			continue
		placement.set(key, value)
	for key in REQUIRED_KEYS:
		if not config.has_section_key(id, key):
			errors.append("[%s]: needs a %s" % [id, key])
	if placement.rotation < 0 or placement.rotation > 5:
		errors.append("[%s]: rotation is 0 to 5 (60-degree steps), not %d" % [id, placement.rotation])
	var design_path := IslandDesignScript.path_for(placement.design)
	if placement.design != "" and not FileAccess.file_exists(design_path):
		errors.append("[%s]: there is no design %s (%s)" % [id, placement.design, design_path])
	placements.append(placement)


func _count_role(role: String) -> void:
	var ids := PackedStringArray()
	for placement in placements:
		if placement.get(role):
			ids.append(placement.id)
	if ids.size() != 1:
		errors.append("world map: exactly one island needs %s = true, not %d (%s)"
			% [role, ids.size(), ", ".join(ids) if not ids.is_empty() else "none"])


# ConfigFile quietly merges a repeated section and keeps the last of a repeated key, so a copied
# island whose id wasn't changed would vanish. Look for both in the text itself.
func _find_repeats(text: String) -> void:
	var sections := {}
	var keys := {}
	var section := ""
	for line in text.replace("\r", "").split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with(";") or stripped.begins_with("#"):
			continue
		if stripped.begins_with("[") and stripped.ends_with("]"):
			section = stripped.substr(1, stripped.length() - 2)
			if sections.has(section):
				errors.append("[%s]: two islands have this id; every id must be different" % section)
			sections[section] = true
		elif stripped.contains("="):
			var key := stripped.get_slice("=", 0).strip_edges()
			if keys.has(section + "/" + key):
				errors.append("[%s]: %s is set twice" % [section, key])
			keys[section + "/" + key] = true
