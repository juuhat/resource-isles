extends SceneTree

const CheckWatchdog := preload("res://tools/check_watchdog.gd")


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_check_exploration")


func _check_exploration() -> void:
	var map := ExplorationMap.new()
	CheckWatchdog.require(not map.is_explored(Vector2i.ZERO), "A new map has nothing explored")
	CheckWatchdog.require(ExplorationMap.cells_around(Vector2i(3, -5), 2).size() == 19, "Sight covers a hex of cells")

	var home := Vector2i(1, 1)
	var changes := [0]
	map.changed.connect(func() -> void: changes[0] += 1)
	CheckWatchdog.require(map.explore(ExplorationMap.cells_around(home, 3)), "Seeing new cells explores them")
	CheckWatchdog.require(map.is_explored(home) and map.is_explored(HexGrid.shift(home, Vector2i(3, -3))), "Every cell in sight is explored")
	CheckWatchdog.require(not map.is_explored(HexGrid.shift(home, Vector2i(4, 0))), "Cells out of sight stay unexplored")
	CheckWatchdog.require(not map.explore(ExplorationMap.cells_around(home, 2)), "Seeing explored cells again changes nothing")
	CheckWatchdog.require(changes[0] == 1, "Only new cells signal a change")

	# Seeing far past the square grows it and keeps what was explored.
	var far := Vector2i(-150, 210)
	map.explore(ExplorationMap.cells_around(far, 1))
	CheckWatchdog.require(map.radius >= 210, "The map grows to hold far cells")
	CheckWatchdog.require(map.is_explored(home) and map.is_explored(far), "Growing keeps explored cells")
	CheckWatchdog.require(map.cells.size() == map.size() * map.size(), "One byte per cell")

	var world := WorldData.new()
	world.exploration = map
	var restored := WorldData.from_dict(world.to_dict(0.0), 0.0).exploration
	CheckWatchdog.require(restored.radius == map.radius and restored.cells == map.cells, "Exploration survives a save")
	CheckWatchdog.require(not WorldData.from_dict({}, 0.0).exploration.is_explored(home), "Older saves start unexplored")
	print("Exploration map: PASS")
	quit()
