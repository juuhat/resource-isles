extends SceneTree

# Headless check for the placement preview. Runs the real game scene from a fresh world and, for
# every player-buildable building with a model, confirms the build menu shows a render of the
# model rather than the flat texture, then hovers a free spot in placement mode and confirms the
# preview shows a see-through copy of the 3D model (not the flat billboard) with the same bounds
# as the building placed on that spot.
#
# The game saves to SaveManager.SAVE_PATH as it plays, so any existing save is backed up first and
# restored at the end.
#
#   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/placement_preview_check.gd

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
	var checked := 0
	for definition in game.building_manager.definitions.values():
		if definition.model == null or not definition.player_buildable:
			continue
		assert(game.building_menu._building_art(definition) is ViewportTexture,
			"%s shows its 3D model in the build menu" % definition.display_name)
		var cell := _free_cell(game, island, renderer, definition.id)
		if cell == GameTypes.NO_CELL:
			print("Placement preview: no free spot for %s, skipped" % definition.display_name)
			continue
		var rotation := renderer.placement_rotation_at(cell, definition.id)

		renderer.hovered_cell = cell
		renderer.set_placement_preview(true, definition.id)
		var ghost := _ghost_model(renderer)
		assert(ghost != null, "%s previews as its 3D model" % definition.display_name)
		assert(renderer._preview_root.find_children("*", "Sprite3D", true, false).is_empty(),
			"%s shows no billboard ghost" % definition.display_name)
		for node in ghost.find_children("*", "GeometryInstance3D", true, false):
			assert((node as GeometryInstance3D).transparency > 0.0, "The ghost is see-through")
		var ghost_bounds := renderer._instance_aabb(ghost)
		renderer.set_placement_preview(false, definition.id)
		await process_frame

		assert(renderer.place_building_at(cell, definition.id, rotation))
		assert(_has_model_with_bounds(renderer, ghost_bounds),
			"%s preview matches the placed model's size and position" % definition.display_name)
		checked += 1

	assert(checked > 0, "At least one modelled building was checked")
	print("Placement preview: %d buildings checked" % checked)
	print("PLACEMENT PREVIEW CHECK PASSED")
	root.remove_child(game)
	game.free()
	_restore_save()
	quit(0)


func _free_cell(game: Node, island: IslandData, renderer: IslandRenderer, building_type: int) -> Vector2i:
	for cell in island.terrain.keys():
		var rotation := renderer.placement_rotation_at(cell, building_type)
		if renderer._can_place_at(cell, building_type, rotation):
			return cell
	return GameTypes.NO_CELL


# The model ghost among the preview's tile caps and yield labels.
func _ghost_model(renderer: IslandRenderer) -> Node3D:
	for child in renderer._preview_root.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Node3D and not (child is GeometryInstance3D):
			return child
	return null


func _has_model_with_bounds(renderer: IslandRenderer, bounds: AABB) -> bool:
	for child in renderer._objects_root.get_children():
		if not (child is Node3D) or child is GeometryInstance3D or child is PowerIndicator:
			continue
		var placed := renderer._instance_aabb(child)
		if placed.position.distance_to(bounds.position) < 0.01 and placed.size.distance_to(bounds.size) < 0.01:
			return true
	return false


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
