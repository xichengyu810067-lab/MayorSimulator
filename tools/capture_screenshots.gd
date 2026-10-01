extends SceneTree

const LOCALES := ["zh_TW", "zh_CN", "en", "ja", "ko"]
# Captures the municipal center once per locale. Pass
# `-- --capture-output-dir=<dir>` to choose where the PNG files go.
const DEFAULT_OUTPUT_DIR := "res://artifacts/screenshots/locales"
const OUTPUT_ARGUMENT_PREFIX := "--capture-output-dir="


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_dir := _output_directory()
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_error("Unable to create screenshot directory: %s" % output_dir)
		quit(1)
		return
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
		var save_path := "%s/gameplay_%s.png" % [output_dir, locale]
		var err := img.save_png(save_path)
		print("Saved screenshot for %s to %s (result code: %d)" % [locale, save_path, err])

	quit(0)


func _output_directory() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(OUTPUT_ARGUMENT_PREFIX):
			return argument.trim_prefix(OUTPUT_ARGUMENT_PREFIX)
	return DEFAULT_OUTPUT_DIR


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame
