extends SceneTree

const LOCALES := ["zh_TW", "zh_CN", "en", "ja", "ko"]
const ARTIFACT_DIR := "C:/Users/USER/.gemini/antigravity-cli/brain/c5ec00a6-64bf-42ce-8b4f-93011bd8513f"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var l10n = root.get_node_or_null("L10n")
	if l10n == null:
		push_error("L10n autoload not found")
		quit(1)
		return

	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)

	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(6)

	main.start_screen.animation_duration = 0.01
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			break

	main.call("_open_municipal_center")
	await _settle(6)

	for locale in LOCALES:
		l10n.set_locale(locale, false)
		await _settle(4)
		l10n.localize_tree(main)
		main.call("_update_ui")
		await _settle(4)

		var viewport := root.get_viewport()
		var img := viewport.get_texture().get_image()
		var save_path := "%s/gameplay_%s.png" % [ARTIFACT_DIR, locale]
		var err := img.save_png(save_path)
		print("Saved screenshot for %s to %s (result code: %d)" % [locale, save_path, err])

	quit(0)


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame
