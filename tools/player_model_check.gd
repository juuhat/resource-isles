extends SceneTree

const PlayerScript := preload("res://scripts/player/player_unit.gd")


func _initialize() -> void:
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
	assert(player._animation_player != null, "Robot must import an AnimationPlayer")
	assert(not player._idle_animation.is_empty(), "Idle clip must be found")
	assert(not player._walk_animation.is_empty(), "Walk clip must be found")
	assert(player._animation_player.current_animation == player._idle_animation)
	var model := player._model
	var head := model.find_child("HeadPivot", true, false) as Node3D
	var leg := model.find_child("LeftLegPivot", true, false) as Node3D
	assert(head != null and leg != null, "Export must preserve articulated pivots")
	var root_origin := model.position
	player._animation_player.seek(0.0, true)
	var head_rest := head.transform
	player._animation_player.seek(0.75, true)
	assert(not head.transform.is_equal_approx(head_rest), "Idle must animate the head")
	var path: Array[Vector2i] = [Vector2i(2, 1)]
	player.follow_path(path)
	player._update_animation()
	assert(player._animation_player.current_animation == player._walk_animation)
	assert(player._animation_player.get_animation(player._walk_animation).loop_mode == Animation.LOOP_LINEAR)
	player._animation_player.advance(0.2)
	player._animation_player.seek(0.0, true)
	var leg_rest := leg.transform
	player._animation_player.seek(0.2, true)
	assert(not leg.transform.is_equal_approx(leg_rest), "Walk must animate the legs")
	assert(model.position.is_equal_approx(root_origin), "Walk must not add root motion")
	for i in 120:
		player._process(1.0 / 60.0)
	player._update_animation()
	assert(player.current_cell == Vector2i(2, 1), "Animated player must finish the movement command")
	assert(not player.is_moving())
	assert(player._animation_player.current_animation == player._idle_animation)

	# Harvesting swings: each plays its clip with only its own tool in hand, and walking or
	# stopping puts the tool away.
	var axe := model.find_child("HeldAxe", true, false) as Node3D
	var pickaxe := model.find_child("HeldPickaxe", true, false) as Node3D
	assert(axe != null and pickaxe != null, "Export must include the held tools")
	assert(not axe.visible and not pickaxe.visible, "Tools stay hidden outside a swing")
	for kind in ["chop", "mine"]:
		assert(player._work_animations.has(kind), "%s clip must be found" % kind)
		player.set_work(kind)
		assert(player._animation_player.current_animation == player._work_animations[kind])
		assert(axe.visible == (kind == "chop") and pickaxe.visible == (kind == "mine"))
	var wrist := model.find_child("ToolPivot", true, false) as Node3D
	player._animation_player.advance(0.2)
	player._animation_player.seek(0.0, true)
	var wrist_rest := wrist.transform
	player._animation_player.seek(0.6, true)
	assert(not wrist.transform.is_equal_approx(wrist_rest), "Mine must swing the tool")
	player.follow_path([Vector2i(1, 1)] as Array[Vector2i])
	player._update_animation()
	assert(player._animation_player.current_animation == player._walk_animation)
	assert(not pickaxe.visible, "Walking puts the tool away")
	for i in 120:
		player._process(1.0 / 60.0)
	assert(pickaxe.visible, "The swing resumes once parked")
	player.set_work("")
	assert(player._animation_player.current_animation == player._idle_animation)
	assert(not axe.visible and not pickaxe.visible)

	# Operate: the hand PTO shows instead of a tool, the forearm holds level and the spindle
	# spins. The nose sits 0.345 ahead at 0.53 up (native units) on the right hand (-X), which
	# the sawmill's generator socket is placed to meet (tools/sawmill_model_check.gd).
	var pto := model.find_child("HeldPTO", true, false) as Node3D
	var spindle := model.find_child("PTOSpindle", true, false) as Node3D
	var nose := model.find_child("PTO nose", true, false) as Node3D
	assert(pto != null and spindle != null and nose != null, "Export must include the hand PTO")
	assert(not pto.visible, "The PTO stays hidden outside Operate")
	assert(player._work_animations.has("operate"), "Operate clip must be found")
	player.set_work("operate")
	assert(player._animation_player.current_animation == player._work_animations["operate"])
	assert(pto.visible and not axe.visible and not pickaxe.visible, "Operate shows only the PTO")
	player._animation_player.advance(0.3)  # finish the crossfade from the previous clip
	pto.scale = Vector3.ONE  # what the equip pop-in tween ends on (tweens don't run here)
	player._animation_player.seek(0.0, true)
	var nose_at := model.global_transform.affine_inverse() * nose.global_position
	assert(nose_at.distance_to(Vector3(-0.29, 0.53, 0.345)) < 0.01, "Forearm level, PTO pointing ahead: %s" % nose_at)
	var spin_rest := spindle.transform
	player._animation_player.seek(0.1, true)
	assert(not spindle.transform.is_equal_approx(spin_rest), "Operate must spin the spindle")
	player.set_work("")
	assert(not pto.visible, "Stopping puts the PTO away")
	player.queue_free()
	renderer.queue_free()
	await process_frame
	print("Player model import, animation and movement: PASS")
	quit()
