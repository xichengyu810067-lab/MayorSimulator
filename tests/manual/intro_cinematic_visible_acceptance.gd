extends SceneTree

const IntroCinematicScene = preload("res://ui/tutorial/intro_cinematic.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	var cinematic = IntroCinematicScene.instantiate()
	root.add_child(cinematic)
	if not cinematic.open():
		push_error("Visible cinematic acceptance could not open the fixed CG sequence.")
		quit(1)
		return
	print("VISIBLE_INTRO_CINEMATIC_READY: Inspect each CG shot, subtitle readability, fade, push, and close behavior. This script is intentionally not assertion-matrix registered.")
	await create_timer(2.0).timeout
	for _shot in range(7):
		cinematic.advance()
		await create_timer(1.0).timeout
	await create_timer(2.0).timeout
	cinematic.advance()
	print("VISIBLE_INTRO_CINEMATIC_ACCEPTANCE_COMPLETED")
	quit(0)
