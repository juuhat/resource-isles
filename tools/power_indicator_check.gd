extends SceneTree

# Headless check for the red "no power" bolt. Runs the real game scene from a fresh world, places
# a power-consuming building with no generator, and confirms the bolt floats above it while it
# is unpowered, hides as soon as the robot's Operate action hand-powers it, and returns when the
# robot stops. Non-consumers (e.g. a windmill) never get a bolt.
#
# The game saves to SaveManager.SAVE_PATH as it plays, so any existing save is backed up first and
# restored at the end.
#
#   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/power_indicator_check.gd

const GameScene := preload("res://game.tscn")

var _saved_bytes := PackedByteArray()
var _had_save := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_backup_save()
	SaveManager.delete_save()

	var game: Node = GameScene.instantiate()
	root.add_child(game)
	await process_frame

	var island: IslandData = game.current_island
	var renderer: IslandRenderer = game.renderer
	var cell := _free_cell(game, island, GameTypes.BuildingType.SAWMILL)
	assert(cell != GameTypes.NO_CELL, "Need a free spot for a sawmill")
	assert(renderer.place_building_at(cell, GameTypes.BuildingType.SAWMILL))

	var indicator := _indicator_for(renderer, cell)
	assert(indicator != null, "A power consumer gets a bolt indicator")
	await _frames(3)
	assert(not island.is_consumer_powered(cell))
	assert(indicator.visible, "The bolt shows while the building is unpowered")

	var model_top := _model_top(renderer, indicator)
	assert(is_equal_approx(indicator.position.y, model_top), "The indicator anchors on the building's roof")
	var bolt_screen_lift: float = indicator._bolt.position.y
	assert(bolt_screen_lift > 0.0, "The bolt floats above the roof")

	# Hand-power it via the robot's Operate action.
	game.operate_cell = cell
	game.is_operating = true
	await _frames(3)
	assert(island.is_consumer_powered(cell))
	assert(not indicator.visible, "Operate powers the building, so the bolt hides")

	game.is_operating = false
	game.operate_cell = GameTypes.NO_CELL
	await _frames(3)
	assert(indicator.visible, "The bolt returns once the robot stops operating")

	# Non-consumers never get one.
	var windmill_cell := _free_cell(game, island, GameTypes.BuildingType.WINDMILL)
	if windmill_cell != GameTypes.NO_CELL and renderer.place_building_at(windmill_cell, GameTypes.BuildingType.WINDMILL):
		assert(_indicator_for(renderer, windmill_cell) == null, "Generators get no bolt")

	print("POWER INDICATOR CHECK PASSED")
	root.remove_child(game)
	game.free()
	_restore_save()
	quit(0)


func _free_cell(game: Node, island: IslandData, building_type: int) -> Vector2i:
	for cell in island.terrain.keys():
		if game.building_manager.can_place(cell, building_type, island):
			return cell
	return GameTypes.NO_CELL


func _indicator_for(renderer: IslandRenderer, cell: Vector2i) -> PowerIndicator:
	for node in renderer.find_children("PowerIndicator*", "", true, false):
		if node is PowerIndicator and node.anchor_cell == cell:
			return node
	return null


# Highest point of the building model the indicator sits over (same XZ, island-local space).
func _model_top(renderer: IslandRenderer, indicator: PowerIndicator) -> float:
	var top := -INF
	var objects := indicator.get_parent()
	for child in objects.get_children():
		if child == indicator or not (child is Node3D):
			continue
		var node := child as Node3D
		if Vector2(node.position.x, node.position.z).distance_to(Vector2(indicator.position.x, indicator.position.z)) > renderer.cell_size.x * 0.5:
			continue
		var aabb: AABB = objects.global_transform.affine_inverse() * renderer._instance_aabb(node)
		top = maxf(top, aabb.end.y)
	return top


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SaveManager.SAVE_PATH)
	if _had_save:
		_saved_bytes = FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH)


func _restore_save() -> void:
	SaveManager.delete_save()
	if _had_save:
		var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(_saved_bytes)
		file.close()
