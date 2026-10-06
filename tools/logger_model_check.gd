extends SceneTree

# Godot --headless --path . --script res://tools/logger_model_check.gd
# Checks imported geometry, robot docking and the renderer's powered felling stroke.

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
# The tree's front face (the notch's mouth) and centre, as Godot z in model units
# (tools/build_logger_camp.py: Blender y = .43 and .60).
const TRUNK_FRONT_Z := -.43
const TRUNK_CENTRE_Z := -.60


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_check")


func _check() -> void:
	var manager := BuildingManager.new()
	var definition := manager.get_definition(GameTypes.BuildingType.LOGGER_CAMP)
	CheckWatchdog.require(definition.true_tile_model, "Docking needs fixed tile scale")
	var model := definition.model.instantiate() as Node3D
	root.add_child(model)
	var spot := model.find_child("WorkSpot", true, false) as Node3D
	var dock := model.find_child("DockPoint", true, false) as Node3D
	CheckWatchdog.require(spot != null and dock != null)
	var offset := dock.global_position - spot.global_position
	CheckWatchdog.require(offset.distance_to(Vector3(.2175, .40, -.20)) < .01,
		"Socket must meet the operating robot's right forearm")
	var bounds := _bounds(model, model.find_children("*", "MeshInstance3D", true, false))
	CheckWatchdog.require(bounds.position.y >= -.001, "Feet rest on the tile")
	CheckWatchdog.require(bounds.size.x < 1.7 and bounds.size.z < 1.5, "Leave room on a single tile")
	CheckWatchdog.require(bounds.end.z < spot.position.z - .18, "Operator body clears the machine")
	CheckWatchdog.require(absf(bounds.size.x / 2.0 - definition.visual_size_tiles.x) < .01,
		"visual_size_tiles matches the model's width (%.3f tiles)" % (bounds.size.x / 2.0))

	var island := IslandData.new(1, 1)
	island.buildings[Vector2i.ZERO] = {type = GameTypes.BuildingType.LOGGER_CAMP}
	var renderer := IslandRenderer.new()
	renderer.island = island
	renderer._add_powered_spinner(Vector2i.ZERO, model)
	var spinner := model.get_child(model.get_child_count() - 1) as PoweredSpinner
	CheckWatchdog.require(spinner != null and spinner._targets.size() == 3 and spinner._chops.size() == 1,
		"Renderer wires the axe stroke, pulley, flywheel and socket")
	spinner.set_process(false)
	var helve := model.find_child("AxeHelvePivot", true, false) as Node3D
	CheckWatchdog.require(helve != null and helve.get_child_count() > 0, "Shaft, helve and head stay under the pivot")
	var axe: Array = helve.find_children("*", "MeshInstance3D", true, false)
	var generator := _bounds(model, model.find_child("SharedGenerator", true, false).find_children("*", "MeshInstance3D", true, false))
	var authored := helve.transform
	var idle_reach := _head_reach(model, axe, helve.position)
	CheckWatchdog.require(idle_reach < TRUNK_FRONT_Z - .03 and idle_reach > TRUNK_CENTRE_Z,
		"An idle camp rests with the bit in the notch (reach %.3f)" % idle_reach)

	var initial: Array[Basis] = []
	for target in spinner._targets:
		initial.append(target.basis)
	spinner._process(.1)
	for i in initial.size():
		CheckWatchdog.require(spinner._targets[i].basis.is_equal_approx(initial[i]), "Unpowered parts stay still")
	CheckWatchdog.require(helve.transform.is_equal_approx(authored), "Unpowered axe stays in the notch")
	island.consumer_powered_states[Vector2i.ZERO] = true
	spinner._process(.1)
	for i in initial.size():
		CheckWatchdog.require(not spinner._targets[i].basis.is_equal_approx(initial[i]), "Powered parts turn")
	CheckWatchdog.require(helve.transform.is_equal_approx(authored), "Powering up starts from the notch")

	# Several full strokes: the swing stays flat and bounded, pulls clear of the tree, bites back
	# into the notch, and never reaches the generator or the operator.
	var furthest := -INF
	for frame in 400:
		spinner._process(.02)
		var swing := authored.basis.inverse() * helve.basis
		var angle := swing.get_euler().y
		CheckWatchdog.require(absf(swing.get_euler().x) < .001 and absf(swing.get_euler().z) < .001,
			"Axe swings flat about its shaft")
		CheckWatchdog.require(angle >= -.001 and angle <= deg_to_rad(IslandRenderer.AXE_STRIKE_DEGREES) + .001,
			"Axe moves only between pulled back and in the notch")
		CheckWatchdog.require(helve.position.is_equal_approx(authored.origin), "Shaft stays planted")
		var axe_bounds := _bounds(model, axe)
		furthest = maxf(furthest, _head_reach(model, axe, helve.position))
		CheckWatchdog.require(not _touches(model, axe, generator), "Axe clears the generator")
		CheckWatchdog.require(axe_bounds.end.z < spot.position.z - .18, "Axe clears the operator")
	CheckWatchdog.require(furthest > TRUNK_FRONT_Z + .15, "Axe pulls well clear of the tree (reach %.3f)" % furthest)
	CheckWatchdog.require(dock.global_position.distance_to(spot.global_position + offset) < .001,
		"Running the mechanism must not move the docking point")

	island.consumer_powered_states[Vector2i.ZERO] = false
	spinner._process(2.0)
	var stopped := spinner._targets[0].basis
	var stopped_helve := helve.transform
	spinner._process(.1)
	CheckWatchdog.require(spinner._targets[0].basis.is_equal_approx(stopped), "Machine stops after coasting down")
	CheckWatchdog.require(helve.transform.is_equal_approx(stopped_helve), "Axe stops after coasting down")
	print("Logger bounds ", bounds, " socket offset ", offset, " idle reach ", idle_reach, " pulled back ", furthest)
	print("LOGGER_CAMP MODEL CHECK OK")
	renderer.free()
	model.free()
	quit()


# Exact bounds from the vertices: a rotated part's transformed AABB would overstate its reach.
func _bounds(model: Node3D, meshes: Array) -> AABB:
	var result := AABB()
	var first := true
	for node in meshes:
		var mesh := node as MeshInstance3D
		var to_model := model.global_transform.affine_inverse() * mesh.global_transform
		for vertex in mesh.mesh.get_faces():
			var point := to_model * vertex
			result = AABB(point, Vector3.ZERO) if first else result.expand(point)
			first = false
	return result


# Whether any vertex of the meshes lies inside box: a swung part's own AABB would overstate it.
func _touches(model: Node3D, meshes: Array, box: AABB) -> bool:
	for node in meshes:
		var mesh := node as MeshInstance3D
		var to_model := model.global_transform.affine_inverse() * mesh.global_transform
		for vertex in mesh.mesh.get_faces():
			if box.has_point(to_model * vertex):
				return true
	return false


# How far the axe head reaches toward the tree (lowest z), ignoring the shaft and collar.
func _head_reach(model: Node3D, meshes: Array, shaft: Vector3) -> float:
	var reach := INF
	for node in meshes:
		var mesh := node as MeshInstance3D
		var to_model := model.global_transform.affine_inverse() * mesh.global_transform
		for vertex in mesh.mesh.get_faces():
			var point := to_model * vertex
			if Vector2(point.x - shaft.x, point.z - shaft.z).length() > .3:
				reach = minf(reach, point.z)
	return reach
