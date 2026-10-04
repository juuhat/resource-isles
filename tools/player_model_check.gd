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
	player.queue_free()
	renderer.queue_free()
	await process_frame
	print("Player model import, animation and movement: PASS")
	quit()
