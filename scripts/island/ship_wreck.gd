class_name ShipWreck
extends Node3D

# Shows the crashed ship's repairs on its model (tools/build_spaceship.py, docs/spaceship-model.md).
# Each part in ShipRepairs.MODEL_NODES is in the model twice, as a '<Name>Broken' and a
# '<Name>Repaired' node, and this shows the one WorldData.ship_repairs calls for. A part under
# repair, or paused part way, is printed up to its progress inside a hologram of the finished part,
# like a blueprint (ConstructionSite). A repaired part's '<Name>Spin' node, if it has one (the radar
# dish), turns about its local up axis to face where the chart's radar sweep points
# (WorldView.radar_sweep_angle), so dish and sweep turn together. A broken part the active quest
# highlights glows (update_quest_highlights). Like ConstructionSite it polls each frame, so
# finishing a repair needs no re-render, and it is freed with the objects on the next one. It runs
# while the game is paused too, as the sweep does.

enum State { BROKEN, REPAIRING, REPAIRED }

var world: WorldData
var island: IslandData
var anchor_cell := GameTypes.NO_CELL
# Optional, from the renderer: (GameTypes.QuestTargetKind, value) -> true while an active quest
# highlights that target. A highlighted part glows while it is broken (QuestHighlight).
var is_quest_highlighted := Callable()
var _model: Node3D
# Model node name -> the State shown, the ConstructionSite printing it, and its hologram copy.
var _states := {}
var _sites := {}
var _ghosts := {}
# Spin node -> its basis as modelled, which it turns from.
var _spinning := {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# world may be null (no repairs to show): every part then stays broken.
func setup(new_world: WorldData, new_island: IslandData, new_anchor_cell: Vector2i, model: Node3D) -> void:
	world = new_world
	island = new_island
	anchor_cell = new_anchor_cell
	_model = model
	_update()
	update_quest_highlights()


# Puts the quest glow on each broken part an active quest highlights (only the glow: the parts sit up
# on the hull, off the ground), and takes it off the rest. Hidden with the broken part once its
# repair starts.
func update_quest_highlights() -> void:
	for model_node in ShipRepairs.MODEL_NODES:
		var part := ShipRepairs.part_for_model_node(model_node)
		var broken := _model.find_child(model_node + "Broken", true, false) as Node3D
		if part == -1 or broken == null:
			continue
		QuestHighlight.set_on(broken, is_quest_highlighted.is_valid()
			and is_quest_highlighted.call(GameTypes.QuestTargetKind.SHIP_PART, part), 0.0)


func _process(_delta: float) -> void:
	if _model == null:
		return
	_update()
	for spin in _spinning:
		_face_sweep(spin)


# Turns spin about its own up axis until it faces (its +Z, the dish's look) where the radar's sweep
# points. The wreck tilts the axis a few degrees, so the angle is measured on the ground plane.
func _face_sweep(spin: Node3D) -> void:
	var rest: Basis = _spinning[spin]
	spin.basis = rest
	var look := spin.global_basis.z
	spin.basis = rest * Basis(Vector3.UP, atan2(look.z, look.x) - WorldView.radar_sweep_angle())


func _update() -> void:
	for model_node in ShipRepairs.MODEL_NODES:
		var state := _state_of(ShipRepairs.part_for_model_node(model_node))
		if _states.get(model_node, -1) != state:
			_show(model_node, state)


func _state_of(part: int) -> State:
	if world == null or part == -1 or not world.ship_repairs.has(part):
		return State.BROKEN
	return State.REPAIRED if world.is_ship_part_repaired(part) else State.REPAIRING


func _show(model_node: String, state: State) -> void:
	_states[model_node] = state
	var broken := _model.find_child(model_node + "Broken", true, false) as Node3D
	var repaired := _model.find_child(model_node + "Repaired", true, false) as Node3D
	_stop_printing(model_node, repaired)
	if broken != null:
		broken.visible = state == State.BROKEN
	if repaired == null:
		return
	repaired.visible = state != State.BROKEN

	var spin := repaired.find_child(model_node + "Spin", true, false) as Node3D
	if spin != null:
		if _spinning.has(spin):
			spin.basis = _spinning[spin]
			_spinning.erase(spin)
		if state == State.REPAIRED:
			_spinning[spin] = spin.basis
			_face_sweep(spin)

	if state == State.REPAIRING:
		var ghost := repaired.duplicate() as Node3D
		repaired.add_sibling(ghost)
		var part := ShipRepairs.part_for_model_node(model_node)
		var site := ConstructionSite.new()
		site.name = model_node + "Repair"
		site.progress_source = func() -> float: return float(world.ship_repairs.get(part, 1.0))
		add_child(site)
		site.setup(island, anchor_cell, repaired, ghost)
		_sites[model_node] = site
		_ghosts[model_node] = ghost


# Ends a part's print: frees the site and the hologram, and gives the part its own materials back.
func _stop_printing(model_node: String, repaired: Node3D) -> void:
	if not _sites.has(model_node):
		return
	_sites[model_node].queue_free()
	_ghosts[model_node].queue_free()
	_sites.erase(model_node)
	_ghosts.erase(model_node)
	for node in repaired.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.get_surface_override_material_count():
			mesh_instance.set_surface_override_material(surface, null)
