extends SceneTree

const IntroCinematicScript = preload("res://ui/tutorial/intro_cinematic.gd")
const StorySequence = preload("res://data/tutorial/story_sequence.gd")

var failed := false
var checks := 0
var completed_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(StorySequence.is_valid(), "story sequence is fixed and valid")
	_check(StorySequence.SHOTS.size() == 8, "story has exactly eight distinct shots")
	var ids := {}
	for shot in StorySequence.SHOTS:
		var id := str(shot["id"])
		_check(not ids.has(id), "shot id is unique: %s" % id)
		ids[id] = true
		_check(ResourceLoader.exists(str(shot["asset"])), "fixed shot asset exists: %s" % id)
		_check(ResourceLoader.exists(str(shot["foreground"])), "fixed foreground asset exists: %s" % id)
	var cinematic = IntroCinematicScript.new()
	root.add_child(cinematic)
	cinematic.completed.connect(func() -> void: completed_count += 1)
	await process_frame
	_check(cinematic.open(), "cinematic opens from the fixed sequence")
	await process_frame
	_check(cinematic.resident_texture_count() == 2, "only current and next shot textures are resident")
	_check(cinematic.current_layer.texture != null and cinematic.next_layer.texture != null, "current and next layers are prepared")
	for _step in range(StorySequence.SHOTS.size() - 1):
		cinematic.advance()
		if cinematic._transition != null:
			cinematic._transition.kill()
			cinematic._commit_advanced_shot()
		await process_frame
		_check(cinematic.resident_texture_count() <= 2, "resident shot textures stay bounded during transition")
	_check(cinematic.title_label.text == _l10n("把黎明留在城諾"), "final title resolves through localization")
	cinematic.advance()
	await process_frame
	_check(completed_count == 1, "completion emits exactly once")
	cinematic.advance()
	await process_frame
	_check(completed_count == 1, "completion never emits twice")
	_check(cinematic.resident_texture_count() == 0, "close releases current and next textures")
	var missing = IntroCinematicScript.new()
	root.add_child(missing)
	await process_frame
	missing._fail_closed("開場 CG 素材遺失：固定契約測試素材")
	_check(missing.error_label.visible and missing.error_label.text.contains("素材遺失"), "missing asset provides human-readable error")
	for locale in ["zh_TW", "zh_CN", "en", "ja", "ko"]:
		var l10n = root.get_node_or_null("L10n")
		_check(l10n != null and bool(l10n.set_locale(locale, false)), "locale available: %s" % locale)
		if l10n != null:
			_check(not str(l10n.text("城諾市：重光之日")).is_empty(), "cinematic locale key resolves: %s" % locale)
	if failed:
		quit(1)
	else:
		print("Intro cinematic contract test passed. Shots=%d Checks=%d" % [StorySequence.SHOTS.size(), checks])
		quit(0)


func _l10n(source: String) -> String:
	var l10n = root.get_node_or_null("L10n")
	return str(l10n.text(source)) if l10n != null else source


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("Intro cinematic contract failed: %s" % message)
