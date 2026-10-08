extends SceneTree

# Renders the build bar open over the game, at the start of a new game and with every quest done
# (all buildings unlocked, also at 1280x720), each with a card hovered so its details popup shows.
# Needs a window
# (not headless):
#
#   Godot_v4.6.3-stable_win64_console.exe --path . --script res://tools/building_menu_screenshot.gd -- <out_dir>
#
# The game saves to SaveManager.SAVE_PATH as it plays, so any existing save is backed up first and
# restored at the end.

const GameScene := preload("res://game.tscn")

var _saved_bytes := PackedByteArray()
var _had_save := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://")
	_had_save = FileAccess.file_exists(SaveManager.SAVE_PATH)
	if _had_save:
		_saved_bytes = FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH)
	SaveManager.delete_save()

	root.size = Vector2i(1600, 900)
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	var menu: BuildingMenu = game.building_menu

	await _shoot(menu, out_dir.path_join("build_menu_start.png"), -1, 0)

	var all_quests := {}
	for quest in game.quest_manager.quests:
		all_quests[quest.id] = true
	game.quest_manager.restore_completed(all_quests)
	game._debug_grant_resources()
	menu.close_menu()
	await _shoot(menu, out_dir.path_join("build_menu_power.png"), GameTypes.BuildingCategory.POWER, 1)
	menu.close_menu()
	await _shoot(menu, out_dir.path_join("build_menu_resources.png"), GameTypes.BuildingCategory.RESOURCES, 2)
	# The smallest common window: the bar must still clear the launcher and the robot portrait.
	menu.close_menu()
	root.size = Vector2i(1280, 720)
	await _shoot(menu, out_dir.path_join("build_menu_small.png"), GameTypes.BuildingCategory.RESOURCES, 3)

	root.remove_child(game)
	game.free()
	SaveManager.delete_save()
	if _had_save:
		var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(_saved_bytes)
		file.close()
	quit()


# Opens the menu on `category` (-1 keeps the default tab) and hovers the card at `card_index`.
func _shoot(menu: BuildingMenu, path: String, category: int, card_index: int) -> void:
	if category != -1:
		menu.selected_category = category
	menu.open_menu()
	for i in 30:
		await process_frame
	if card_index < menu.card_order.size():
		var building_type := menu.card_order[card_index]
		menu._on_card_hovered(menu.building_manager.get_definition(building_type))
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("Saved ", path)
