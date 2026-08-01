extends RefCounted

const AUDIO_STOP_SETTLE_FRAMES := 3
const AUDIO_DETACH_SETTLE_FRAMES := 3
const FREE_SETTLE_FRAMES := 3


static func finish(tree: SceneTree, fixtures: Array, exit_code: int) -> void:
	await release_fixtures(tree, fixtures)
	tree.quit(exit_code)


static func release_fixtures(tree: SceneTree, fixtures: Array) -> void:
	for fixture_variant in fixtures:
		var fixture := fixture_variant as Node
		if fixture == null or not is_instance_valid(fixture):
			continue
		_stop_audio(fixture)

	# Let AudioServer consume the stop command before changing the stream.  Doing
	# both in one frame can non-deterministically strand a looping playback.
	for _frame in range(AUDIO_STOP_SETTLE_FRAMES):
		await tree.process_frame

	for fixture_variant in fixtures:
		var fixture := fixture_variant as Node
		if fixture == null or not is_instance_valid(fixture):
			continue
		_detach_audio_streams(fixture)

	for _frame in range(AUDIO_DETACH_SETTLE_FRAMES):
		await tree.process_frame

	for fixture_variant in fixtures:
		var fixture := fixture_variant as Node
		if fixture == null or not is_instance_valid(fixture):
			continue
		fixture.free()

	# Deferred callbacks and object deletion complete in later engine phases.
	for _frame in range(FREE_SETTLE_FRAMES):
		await tree.process_frame


static func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		var player := node as AudioStreamPlayer
		player.stop()
	elif node is AudioStreamPlayer2D:
		var player_2d := node as AudioStreamPlayer2D
		player_2d.stop()
	elif node is AudioStreamPlayer3D:
		var player_3d := node as AudioStreamPlayer3D
		player_3d.stop()

	for child_variant in node.get_children():
		_stop_audio(child_variant as Node)


static func _detach_audio_streams(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer2D:
		(node as AudioStreamPlayer2D).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

	for child_variant in node.get_children():
		_detach_audio_streams(child_variant as Node)
