extends SceneTree

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const PlayerScript := preload("res://scripts/player/player_unit.gd")


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_check_model")


func _check_model() -> void:
	var renderer := IslandRenderer.new()
	# Movement only needs terrain heights, not the expensive world scene or any save files.
	var island := IslandData.new(4, 4)
	for y in 4:
		for x in 4:
			island.set_terrain(Vector2i(x, y), GameTypes.Terrain.GRASS)
	renderer.island = island
	root.add_child(renderer)
	var player := PlayerScript.new()
	player.setup(renderer)
	root.add_child(player)
	player.place_at(Vector2i(1, 1))
	CheckWatchdog.require(player._animation_player != null, "Robot must import an AnimationPlayer")
	CheckWatchdog.require(not player._idle_animation.is_empty(), "Idle clip must be found")
	CheckWatchdog.require(not player._walk_animation.is_empty(), "Walk clip must be found")
	CheckWatchdog.require(not player._run_animation.is_empty(), "Run clip must be found")
	CheckWatchdog.require(player._move_animation == player._run_animation, "The robot runs while moving")
	CheckWatchdog.require(player._animation_player.current_animation == player._idle_animation)
	var model := player._model
	CheckWatchdog.require(player._blink._eyes.size() == 2, "Both amber eyes must support blinking")
	var eye: MeshInstance3D = player._blink._eyes[0]
	var open_bounds: AABB = eye.transform * eye.get_aabb()
	player._blink._blink_wait = 0.0
	player._blink.update(0.0)
	player._blink.update(0.08)
	var closed_bounds: AABB = eye.transform * eye.get_aabb()
	CheckWatchdog.require(closed_bounds.size.y < open_bounds.size.y * 0.1, "Blink must close vertically")
	CheckWatchdog.require(closed_bounds.get_center().is_equal_approx(open_bounds.get_center()), "Blink must keep the eye centred")
	player._animation_player.advance(0.02)
	CheckWatchdog.require((eye.transform * eye.get_aabb()).size.y < open_bounds.size.y * 0.1,
		"Body animation must preserve the blink")
	player._blink.update(PlayerScript.RobotBlink.BLINK_DURATION)
	for i in player._blink._eyes.size():
		CheckWatchdog.require(player._blink._eyes[i].transform.is_equal_approx(player._blink._eye_rest_transforms[i]), "Blink must fully reopen both eyes")
	CheckWatchdog.require(player._blink._blink_wait >= 2.5 and player._blink._blink_wait <= 5.0, "Blinks must have a natural pause")
	var head := model.find_child("HeadPivot", true, false) as Node3D
	var leg := model.find_child("LeftLegPivot", true, false) as Node3D
	CheckWatchdog.require(head != null and leg != null, "Export must preserve articulated pivots")
	var root_origin := model.position
	player._animation_player.seek(0.0, true)
	var head_rest := head.transform
	player._animation_player.seek(0.75, true)
	CheckWatchdog.require(not head.transform.is_equal_approx(head_rest), "Idle must animate the head")
	var path: Array[Vector2i] = [Vector2i(2, 1)]
	player.follow_path(path)
	player._update_animation()
	CheckWatchdog.require(player._animation_player.current_animation == player._move_animation)
	CheckWatchdog.require(player._animation_player.get_animation(player._move_animation).loop_mode == Animation.LOOP_LINEAR)
	var walk_clip := player._animation_player.get_animation(player._move_animation)
	var cycle_distance := PlayerScript.RUN_CYCLE_DISTANCE * model.scale.z
	var walk_rate := player._animation_player.speed_scale
	CheckWatchdog.require(is_equal_approx(cycle_distance * walk_rate / walk_clip.length, player.move_speed),
		"Walk stride must cover the same world distance per second as movement")
	player.move_speed *= 0.5
	player._update_animation()
	CheckWatchdog.require(is_equal_approx(player._animation_player.speed_scale, walk_rate * 0.5),
		"Walk cadence must follow speed changes during a route")
	player.move_speed *= 2.0
	model.scale *= 2.0
	player._update_animation()
	CheckWatchdog.require(is_equal_approx(player._animation_player.speed_scale, walk_rate * 0.5),
		"A larger robot needs fewer steps to cover the same distance")
	model.scale *= 0.5
	player._update_animation()
	player._animation_player.advance(0.2)
	player._animation_player.seek(0.0, true)
	var leg_rest := leg.transform
	player._animation_player.seek(0.2, true)
	CheckWatchdog.require(not leg.transform.is_equal_approx(leg_rest), "Walk must animate the legs")
	CheckWatchdog.require(model.position.is_equal_approx(root_origin), "Walk must not add root motion")
	for i in 120:
		player._process(1.0 / 60.0)
	player._update_animation()
	CheckWatchdog.require(player.current_cell == Vector2i(2, 1), "Animated player must finish the movement command")
	CheckWatchdog.require(not player.is_moving())
	CheckWatchdog.require(player._animation_player.current_animation == player._idle_animation)
	CheckWatchdog.require(is_equal_approx(player._animation_player.speed_scale, 1.0), "Idle must keep its authored timing")

	# Harvesting swings: each plays its clip with only its own tool in hand, and walking or
	# stopping puts the tool away.
	var axe := model.find_child("HeldAxe", true, false) as Node3D
	var pickaxe := model.find_child("HeldPickaxe", true, false) as Node3D
	CheckWatchdog.require(axe != null and pickaxe != null, "Export must include the held tools")
	CheckWatchdog.require(not axe.visible and not pickaxe.visible, "Tools stay hidden outside a swing")
	for kind in ["chop", "mine"]:
		CheckWatchdog.require(player._work_animations.has(kind), "%s clip must be found" % kind)
		player.set_work(kind)
		CheckWatchdog.require(player._animation_player.current_animation == player._work_animations[kind])
		CheckWatchdog.require(is_equal_approx(player._animation_player.speed_scale, 1.0), "Work must keep its authored timing")
		CheckWatchdog.require(axe.visible == (kind == "chop") and pickaxe.visible == (kind == "mine"))
	var wrist := model.find_child("ToolPivot", true, false) as Node3D
	player._animation_player.advance(0.2)
	player._animation_player.seek(0.0, true)
	var wrist_rest := wrist.transform
	player._animation_player.seek(0.6, true)
	CheckWatchdog.require(not wrist.transform.is_equal_approx(wrist_rest), "Mine must swing the tool")
	player.follow_path([Vector2i(1, 1)] as Array[Vector2i])
	player._update_animation()
	CheckWatchdog.require(player._animation_player.current_animation == player._move_animation)
	CheckWatchdog.require(not pickaxe.visible, "Walking puts the tool away")
	for i in 120:
		player._process(1.0 / 60.0)
	CheckWatchdog.require(pickaxe.visible, "The swing resumes once parked")
	player.set_work("")
	CheckWatchdog.require(player._animation_player.current_animation == player._idle_animation)
	CheckWatchdog.require(not axe.visible and not pickaxe.visible)

	# Operate: the hand PTO shows instead of a tool, the forearm holds level and the spindle
	# spins. The nose sits 0.345 ahead at 0.53 up (native units) on the right hand (-X), which
	# the sawmill's generator socket is placed to meet (tools/sawmill_model_check.gd).
	var pto := model.find_child("HeldPTO", true, false) as Node3D
	var spindle := model.find_child("PTOSpindle", true, false) as Node3D
	var nose := model.find_child("PTO nose", true, false) as Node3D
	CheckWatchdog.require(pto != null and spindle != null and nose != null, "Export must include the hand PTO")
	CheckWatchdog.require(not pto.visible, "The PTO stays hidden outside Operate")
	CheckWatchdog.require(player._work_animations.has("operate"), "Operate clip must be found")
	player.set_work("operate")
	CheckWatchdog.require(player._animation_player.current_animation == player._work_animations["operate"])
	CheckWatchdog.require(pto.visible and not axe.visible and not pickaxe.visible, "Operate shows only the PTO")
	player._animation_player.advance(0.3)  # finish the crossfade from the previous clip
	pto.scale = Vector3.ONE  # what the equip pop-in tween ends on (tweens don't run here)
	player._animation_player.seek(0.0, true)
	var nose_at := model.global_transform.affine_inverse() * nose.global_position
	CheckWatchdog.require(nose_at.distance_to(Vector3(-0.29, 0.53, 0.345)) < 0.01, "Forearm level, PTO pointing ahead: %s" % nose_at)
	var spin_rest := spindle.transform
	player._animation_player.seek(0.1, true)
	CheckWatchdog.require(not spindle.transform.is_equal_approx(spin_rest), "Operate must spin the spindle")
	player.set_work("")
	CheckWatchdog.require(not pto.visible, "Stopping puts the PTO away")
	player.queue_free()
	renderer.queue_free()
	await process_frame
	_check_planted_boots()
	print("Player model import, animation and movement: PASS")
	quit()


# Run the robot down a long straight path at gameplay speed and follow its boots in world space. A
# boot on the floor should hold roughly still (the run is matched to the movement speed), and both
# should leave the floor between steps (the trot's float). Boots are tracked by their bounds'
# centre, which shifts a little as they tilt, so "still" allows some drift.
func _check_planted_boots() -> void:
	var renderer := IslandRenderer.new()
	var island := IslandData.new(30, 3)
	for y in 3:
		for x in 30:
			island.set_terrain(Vector2i(x, y), GameTypes.Terrain.GRASS)
	renderer.island = island
	root.add_child(renderer)
	var player := PlayerScript.new()
	player.setup(renderer)
	root.add_child(player)
	player.place_at(Vector2i(1, 1))
	var path: Array[Vector2i] = []
	for x in range(2, 28):
		path.append(Vector2i(x, 1))
	player.follow_path(path)
	var boots := player._model.find_children("* boot", "MeshInstance3D", true, false)
	CheckWatchdog.require(boots.size() == 2, "Both boots must be exported as meshes")
	const STEP := 1.0 / 1000.0
	const ON_FLOOR := 0.8  # world units above the tile top
	var previous_x := [0.0, 0.0]
	var drift := 0.0
	var on_floor_samples := 0
	var airborne_samples := 0
	var samples := 0
	for i in 1500:
		player._process(STEP)
		player._animation_player.advance(STEP)
		var both_up := true
		for k in 2:
			var bounds: AABB = boots[k].global_transform * (boots[k] as MeshInstance3D).get_aabb()
			var height := bounds.position.y - player.position.y
			var x := bounds.get_center().x
			if i > 200 and height < ON_FLOOR:
				drift += absf(x - previous_x[k]) / STEP
				on_floor_samples += 1
			both_up = both_up and height >= ON_FLOOR
			previous_x[k] = x
		if i > 200:
			samples += 1
			airborne_samples += 1 if both_up else 0
	var mean_drift := drift / maxf(on_floor_samples, 1)
	CheckWatchdog.require(on_floor_samples > 0, "The boots must touch the floor")
	CheckWatchdog.require(mean_drift < 0.35 * player.move_speed,
		"A boot on the floor must hold roughly still (drifting %.0f at speed %.0f)" % [mean_drift, player.move_speed])
	CheckWatchdog.require(float(airborne_samples) / samples > 0.25, "The run must leave the floor between steps")
	player.free()
	renderer.free()
