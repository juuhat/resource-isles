extends SceneTree

# Headless check for the quest highlight (QuestHighlight) and quests' highlights (QuestTarget).
# Attaching one glows every mesh of a model through its material_overlay and lays a halo, sized to
# clear the model, at its feet; attaching again keeps the one there; detaching fades it out and gives
# the meshes their own overlays back. A renderer glows the ground items an active quest highlights.
# In the game, Recover Your Tools lights up the robot's lost tools and nothing else (not K9-DA); once
# the chain reaches Eyes on the Horizon the tools go dark and the wreck's broken radar glows.
#
#   powershell -ExecutionPolicy Bypass -File tools/run_checks.ps1 -Filter quest_highlight

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const GameScene := preload("res://game.tscn")


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_check")


func _check() -> void:
	await _check_attach_and_detach()
	await _check_renderer()
	await _check_game()
	print("Quest highlight: PASS")
	quit()


func _check_attach_and_detach() -> void:
	# A model at a large scale, as the renderer draws them, with an overlay of its own on one part.
	var model := Node3D.new()
	model.scale = Vector3.ONE * 64.0
	model.position = Vector3(100.0, 20.0, -50.0)
	root.add_child(model)
	var body := _box(model, Vector3(0.0, 0.25, 0.0))
	var handle := _box(model, Vector3(0.4, 0.1, 0.0))
	var own_overlay := StandardMaterial3D.new()
	handle.material_overlay = own_overlay

	var highlight := QuestHighlight.attach(model)
	CheckWatchdog.require(highlight != null and highlight.get_parent() == model, "The highlight lives on the model")
	CheckWatchdog.require(body.material_overlay == highlight._glow and handle.material_overlay == highlight._glow,
		"Every mesh of the model glows")
	CheckWatchdog.require(QuestHighlight.attach(model) == highlight, "Attaching again keeps the highlight there")
	CheckWatchdog.require(model.find_children("*", "QuestHighlight", true, false).size() == 1, "A model has one highlight")

	var halo := highlight._halo
	CheckWatchdog.require(halo != null and halo.top_level, "The halo keeps its world size")
	var bounds := highlight._measure()
	CheckWatchdog.require(is_equal_approx(halo.global_position.y, bounds.position.y + QuestHighlight.HALO_LIFT),
		"The halo lies at the model's feet")
	var radius: float = (halo.mesh as PlaneMesh).size.x * 0.5
	CheckWatchdog.require(radius > Vector2(bounds.size.x, bounds.size.z).length() * 0.5, "The halo clears the model")
	CheckWatchdog.require(highlight._motes != null and highlight._motes.emitting, "Motes drift up from the model")

	model.position += Vector3(30.0, 6.0, 0.0)
	# process_frame fires before the nodes' own _process, so wait for the second one.
	await process_frame
	await process_frame
	CheckWatchdog.require(is_equal_approx(halo.global_position.x, highlight._measure().get_center().x),
		"The halo follows the model")

	QuestHighlight.detach(model)
	CheckWatchdog.require(highlight.is_fading(), "Detaching fades the highlight out")
	CheckWatchdog.require(QuestHighlight.attach(model) == highlight and not highlight.is_fading(),
		"Attaching while it fades brings it back")
	QuestHighlight.detach(model)
	var faded: WeakRef = weakref(highlight)
	await _wait_until(func() -> bool: return faded.get_ref() == null)
	CheckWatchdog.require(QuestHighlight.find_on(model) == null, "The faded highlight is gone")
	CheckWatchdog.require(body.material_overlay == null and handle.material_overlay == own_overlay,
		"The meshes get their own overlays back")

	var flat := Node3D.new()
	root.add_child(flat)
	_box(flat, Vector3.ZERO)
	CheckWatchdog.require(QuestHighlight.attach(flat, 0.0)._halo == null, "A zero radius leaves out the halo")
	# A part that is a mesh itself (like the wreck's) glows too.
	var part := _box(flat, Vector3.ONE)
	QuestHighlight.set_on(part, true, 0.0)
	CheckWatchdog.require(part.material_overlay == QuestHighlight.find_on(part)._glow, "A mesh target glows itself")
	QuestHighlight.set_on(part, false)
	CheckWatchdog.require(QuestHighlight.find_on(part).is_fading(), "Switching a highlight off fades it")
	model.queue_free()
	flat.queue_free()


# The renderer glows exactly the ground items an active quest highlights, and moves the glow when the
# quests change.
func _check_renderer() -> void:
	var island := IslandData.new(3, 3)
	for x in 3:
		for y in 3:
			island.set_terrain(Vector2i(x, y), GameTypes.Terrain.GRASS)
	island.items[Vector2i(1, 1)] = GameTypes.ItemType.AXE
	island.items[Vector2i(2, 1)] = GameTypes.ItemType.WRENCH
	var renderer := IslandRenderer.new()
	root.add_child(renderer)
	renderer.render(island)
	CheckWatchdog.require(_lit_items(renderer).is_empty(), "Without quests nothing glows")

	var lit_types := [GameTypes.ItemType.AXE]
	renderer.is_quest_highlighted = func(kind: int, value: int) -> bool:
		return kind == GameTypes.QuestTargetKind.ITEM and value in lit_types
	renderer.refresh()
	await process_frame
	CheckWatchdog.require(_lit_items(renderer) == [Vector2i(1, 1)], "Only the highlighted item type glows")
	lit_types.append(GameTypes.ItemType.WRENCH)
	renderer.update_quest_highlights()
	CheckWatchdog.require(_lit_items(renderer).size() == 2, "A newly highlighted item lights up")
	lit_types.clear()
	renderer.update_quest_highlights()
	CheckWatchdog.require(_lit_items(renderer).is_empty(), "Items no quest highlights go dark")
	renderer.queue_free()


# The real game: the quest catalog's highlights, through main and the world view.
func _check_game() -> void:
	SaveManager.delete_save()
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	var quests: QuestManager = game.quest_manager
	var renderer: IslandRenderer = game.renderer
	CheckWatchdog.require(quests.get_current_milestone().id == GameTypes.QuestId.HELLO_WORLD, "A new game starts on the tools")
	CheckWatchdog.require(not renderer._item_models.is_empty()
		and _lit_items(renderer).size() == renderer._item_models.size(), "Recover Your Tools lights up every lost tool")
	CheckWatchdog.require(QuestHighlight.find_on(_radar(game)) == null, "The radar waits dark until its quest")
	CheckWatchdog.require(game.dog.find_children("*", "QuestHighlight", true, false).is_empty(), "K9-DA never glows")

	# Play the chain up to Eyes on the Horizon by its stats, leaving the tools where they lie.
	for quest in quests.quests:
		if quest.id == GameTypes.QuestId.EYES_ON_THE_HORIZON:
			break
		if quest.kind != GameTypes.QuestKind.MILESTONE:
			continue
		for objective in quest.objectives:
			game.stat_tracker.add(objective.stat, objective.target)
	CheckWatchdog.require(quests.get_current_milestone().id == GameTypes.QuestId.EYES_ON_THE_HORIZON, "The chain reaches the radar")
	CheckWatchdog.require(_lit_items(renderer).is_empty(), "The tools go dark once their quest is done")
	var radar := QuestHighlight.find_on(_radar(game))
	CheckWatchdog.require(radar != null and not radar.is_fading(), "Eyes on the Horizon lights up the broken radar")
	CheckWatchdog.require(radar._halo == null, "The radar, up on the hull, gets no ground halo")
	CheckWatchdog.require(quests.is_highlighted(GameTypes.QuestTargetKind.SHIP_PART, GameTypes.ShipPart.RADAR)
		and not quests.is_highlighted(GameTypes.QuestTargetKind.ITEM, GameTypes.ItemType.AXE), "Only the active quest's targets glow")
	root.remove_child(game)
	game.free()
	SaveManager.delete_save()


# The cells whose ground item glows (fading ones don't count).
func _lit_items(renderer: IslandRenderer) -> Array:
	var lit := []
	for cell in renderer._item_models:
		var highlight := QuestHighlight.find_on(renderer._item_models[cell])
		if highlight != null and not highlight.is_fading():
			lit.append(cell)
	return lit


func _radar(game: Node) -> Node3D:
	var wreck := game.renderer.find_child("ShipWreck", true, false) as ShipWreck
	return wreck._model.find_child("RadarBroken", true, false) as Node3D


func _box(parent: Node3D, offset: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.2, 0.3)
	mesh.mesh = box
	mesh.position = offset
	parent.add_child(mesh)
	return mesh


func _wait_until(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while not condition.call():
		CheckWatchdog.require(Time.get_ticks_msec() < deadline, "Timed out waiting")
		await process_frame
