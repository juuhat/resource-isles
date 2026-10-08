extends SceneTree

# Headless check that the world map (assets/world/world_map.cfg) keeps the rules the game relies on
# (tools/world_map_rules.gd): islands that don't overlap and stay within the sea, a dock shore on
# every island, nothing walled in by deposits or cliffs, a start island with the wreck and the robot's tools,
# and K9-DA on an island in the home waters at a spot reachable from the shore. Fails with every
# problem found.
#
# Then breaks a copy of the map one way at a time, to make sure each rule catches what it should.
#
#   powershell -ExecutionPolicy Bypass -File tools/run_checks.ps1 -Filter world_map

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const WorldMapRules := preload("res://tools/world_map_rules.gd")

# Designs made to break one rule each, tried as extra islands on the map.
const WALLED_ITEM := """
[grid]
. s s s s .
 s g T T g s
s g T a T g
 s g T T g s
. s s s s .
"""
const WALLED_DEPOSIT := """
[grid]
. s s s s .
 s r S S r s
s r S S S r
 s r S S r s
. s s s s .
"""
const WALLED_K9DA := """
[grid]
. s s s s .
 s r S S r s
s r S r S r
 s r S S r s
. s s s s .

[markers]
k9da 3,2
"""
# Grass straight down to the water: no sand for a dock.
const NO_SHORE := """
[grid]
g g g
 g g g
g g g
"""
# The axe on a plateau with cliffs all round: no ramp up from the beaches, and no landing on top.
const CLIFF_ITEM := """
[grid]
. s s s s .
 s g g g g s
s g g a g g
 s g g g g s
. s s s s .

[heights]
. . . . . .
 . 4 4 4 4 .
. 4 4 4 4 4
 . 4 4 4 4 .
"""
# A start island whose wreck stands on a plateau with no way down to the beaches, and so to a dock.
const CLIFF_START := """
[grid]
. s s s s .
 s g g g g s
s g a p w g
 s g g g g s
. s s s s .

[heights]
. . . . . .
 . 4 4 4 4 .
. 4 4 4 4 4
 . 4 4 4 4 .

[landmarks]
crashed_spaceship 2,1 0
"""

var failures := 0
var _manager := BuildingManager.new()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAILED: " + message)


func _initialize() -> void:
	CheckWatchdog.install(self)
	for problem in WorldMapRules.problems(WorldMap.load_file(), _manager):
		expect(false, problem.message)
	_check_rules_catch_mistakes()
	print("World map: PASS" if failures == 0 else "World map: FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


func _check_rules_catch_mistakes() -> void:
	var map := FileAccess.get_file_as_string(WorldMap.PATH)

	_expect_problem(map + "\n[too_close]\ndesign = \"atoll_small\"\ncenter = Vector2i(46, 0)\n",
		"[iron_isle] and [too_close] overlap", ["iron_isle", "too_close"])
	_expect_problem(map.replace("center = Vector2i(-100, 232)", "center = Vector2i(-130, 290)"),
		"[rim_isle] runs past the edge of the sea", ["rim_isle"])
	_expect_problem(map.replace("center = Vector2i(0, 0)", "center = Vector2i(0, 70)"),
		"[crash_site] is the start island but lies", ["crash_site"])
	var no_wreck := map.replace("design = \"starter\"", "design = \"atoll_small\"")
	_expect_problem(no_wreck, "[crash_site] is the start island but has no crashed spaceship", ["crash_site"])
	_expect_problem(no_wreck, "[crash_site] is the start island but has no wrench", ["crash_site"])
	# Its coast just crossing the edge of the home waters is enough.
	_expect_problem(map.replace("center = Vector2i(-12, -28)", "center = Vector2i(-16, -38)"),
		"[copper_isle] is K9-DA's island but reaches", ["copper_isle"])
	_expect_problem(map.replace("center = Vector2i(50, 0)", "center = Vector2i(30, 0)"),
		"[iron_isle] lies", ["iron_isle"])
	_expect_problem(map.replace("k9da = true", "").replace("start = true", "start = true\nk9da = true"),
		"[crash_site] K9-DA must wait on another island", ["crash_site"])
	var cliff_start := {cliff_start = IslandDesign.parse(CLIFF_START, "cliff_start")}
	expect(cliff_start.cliff_start.errors.is_empty(), "The cliff_start design reads")
	var stuck := WorldMapRules.problems(WorldMap.parse(map.replace("design = \"starter\"", "design = \"cliff_start\"")), _manager, cliff_start)
	_expect_in(stuck, "[crash_site] has nowhere to build a dock the robot can walk to", ["crash_site"])

	# Islands that break the rules of their own, K9-DA moved onto one of them (and copper_isle,
	# no longer K9-DA's, out of the home waters).
	var extra := map.replace("k9da = true", "").replace("center = Vector2i(-12, -28)", "center = Vector2i(-25, -58)")
	extra += "\n[walled_item]\ndesign = \"walled_item\"\ncenter = Vector2i(30, -40)\n"
	extra += "\n[walled_deposit]\ndesign = \"walled_deposit\"\ncenter = Vector2i(-40, 35)\n"
	extra += "\n[no_shore]\ndesign = \"no_shore\"\ncenter = Vector2i(35, 30)\n"
	extra += "\n[walled_k9da]\ndesign = \"walled_k9da\"\ncenter = Vector2i(14, 22)\nk9da = true\n"
	extra += "\n[cliff_item]\ndesign = \"cliff_item\"\ncenter = Vector2i(-45, -10)\n"
	var designs := {
		walled_item = IslandDesign.parse(WALLED_ITEM, "walled_item"),
		walled_deposit = IslandDesign.parse(WALLED_DEPOSIT, "walled_deposit"),
		no_shore = IslandDesign.parse(NO_SHORE, "no_shore"),
		walled_k9da = IslandDesign.parse(WALLED_K9DA, "walled_k9da"),
		cliff_item = IslandDesign.parse(CLIFF_ITEM, "cliff_item"),
	}
	for design_name in designs:
		expect((designs[design_name] as IslandDesign).errors.is_empty(), "The %s design reads" % design_name)
	var problems := WorldMapRules.problems(WorldMap.parse(extra), _manager, designs)
	_expect_in(problems, "[walled_item] the axe at", ["walled_item"])
	_expect_in(problems, "[walled_deposit] the stone deposit at", ["walled_deposit"])
	_expect_in(problems, "[no_shore] has nowhere to build a dock", ["no_shore"])
	_expect_in(problems, "[walled_k9da] K9-DA's spot at", ["walled_k9da"])
	_expect_in(problems, "[cliff_item] the axe at", ["cliff_item"])
	# The made-up designs aren't files, which the map itself reports; everything else is on the islands.
	var map_problems := problems.filter(func(p: Dictionary) -> bool: return p.islands.is_empty())
	var island_problems := problems.filter(func(p: Dictionary) -> bool: return not p.islands.is_empty())
	expect(map_problems.size() == designs.size()
		and map_problems.all(func(p: Dictionary) -> bool: return (p.message as String).contains("there is no design")),
		"The map only misses the made-up design files")
	expect(island_problems.size() == 5, "Only the broken islands have problems: %s"
		% "; ".join(PackedStringArray(island_problems.map(func(p): return p.message))))


func _expect_problem(map_text: String, text: String, ids: Array) -> void:
	_expect_in(WorldMapRules.problems(WorldMap.parse(map_text), _manager), text, ids)


# A problem containing `text` names exactly the islands `ids`.
func _expect_in(problems: Array[Dictionary], text: String, ids: Array) -> void:
	for problem in problems:
		if (problem.message as String).contains(text):
			var named: Array = problem.islands.map(func(id: StringName) -> String: return String(id))
			expect(named == ids, "\"%s\" names %s, not %s" % [text, ids, named])
			return
	expect(false, "Reports \"%s\", got: %s" % [text, "; ".join(PackedStringArray(problems.map(func(p): return p.message)))])
