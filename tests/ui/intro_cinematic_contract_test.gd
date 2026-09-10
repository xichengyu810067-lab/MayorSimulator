extends SceneTree

const IntroCinematicScript = preload("res://ui/tutorial/intro_cinematic.gd")
const StorySequence = preload("res://data/tutorial/story_sequence.gd")
const DECLINE_SUBTITLE := "賴依德的獨裁與貪腐，讓橋梁、商街與家庭逐漸失去依靠"
const DECLINE_TRANSLATIONS := {
	"zh_TW": "賴依德的獨裁與貪腐，讓橋梁、商街與家庭逐漸失去依靠",
	"zh_CN": "赖依德的独裁与贪腐，让桥梁、商街与家庭逐渐失去依靠",
	"en": "Mayor Laide's dictatorship and corruption left bridges, markets, and families without support.",
	"ja": "頼依德の独裁と腐敗が、橋、市場、そして家族の支えを奪っていった。",
	"ko": "라이더의 독재와 부패는 다리와 상가, 가정의 버팀목을 무너뜨렸다.",
}

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
	_check(cinematic.current_layer.texture is Texture2D, "current shot layer uses a Texture2D")
	_check(cinematic.next_layer.texture is Texture2D, "next shot layer uses a Texture2D")
	_check(cinematic.foreground_layer.texture is Texture2D, "foreground layer uses a Texture2D")
	_check(cinematic.portrait_layer.texture is AtlasTexture, "Xiao Li portrait layer uses an AtlasTexture")
	var initial_portrait := cinematic.portrait_layer.texture as AtlasTexture
	_check(initial_portrait.atlas is Texture2D, "Xiao Li portrait atlas is a Texture2D")
	_check(initial_portrait.region == Rect2(0.0, 0.0, 543.0, 724.0), "first shot selects Xiao Li portrait index zero")
	var old_background: Texture2D = cinematic.current_layer.texture as Texture2D
	var old_foreground: Texture2D = cinematic.foreground_layer.texture as Texture2D
	var old_portrait: AtlasTexture = cinematic.portrait_layer.texture as AtlasTexture
	cinematic.advance()
	if cinematic._transition != null:
		cinematic._transition.kill()
		cinematic._commit_advanced_shot()
	await process_frame
	_check(cinematic.current_layer.texture != old_background and cinematic.next_layer.texture != old_background, "transition clears the old background layer reference")
	_check(cinematic.foreground_layer.texture != old_foreground, "transition clears the old foreground layer reference")
	_check(cinematic.portrait_layer.texture != old_portrait, "transition clears the old portrait layer reference")
	var decline_portrait := cinematic.portrait_layer.texture as AtlasTexture
	_check(decline_portrait.atlas is Texture2D and decline_portrait.region == Rect2(1086.0, 0.0, 543.0, 724.0), "second shot selects Xiao Li portrait index two")
	for _step in range(StorySequence.SHOTS.size() - 2):
		cinematic.advance()
		if cinematic._transition != null:
			cinematic._transition.kill()
			cinematic._commit_advanced_shot()
		await process_frame
	_check(cinematic.title_label.text == _l10n("把黎明留在城諾"), "final title resolves through localization")
	cinematic.advance()
	await process_frame
	_check(completed_count == 1, "completion emits exactly once")
	cinematic.advance()
	await process_frame
	_check(completed_count == 1, "completion never emits twice")
	_check(cinematic.current_layer.texture == null and cinematic.next_layer.texture == null, "close clears both shot layers")
	_check(cinematic.foreground_layer.texture == null and cinematic.portrait_layer.texture == null, "close clears foreground and Xiao Li portrait layers")
	var missing = IntroCinematicScript.new()
	root.add_child(missing)
	await process_frame
	missing._fail_closed("開場 CG 素材遺失：固定契約測試素材")
	_check(missing.error_label.visible and missing.error_label.text.contains("素材遺失"), "missing asset provides human-readable error")
	_check(missing.current_layer.texture == null and missing.next_layer.texture == null and missing.foreground_layer.texture == null and missing.portrait_layer.texture == null, "fail-closed clears every cinematic layer")
	for locale in ["zh_TW", "zh_CN", "en", "ja", "ko"]:
		var l10n = root.get_node_or_null("L10n")
		_check(l10n != null and bool(l10n.set_locale(locale, false)), "locale available: %s" % locale)
		if l10n != null:
			_check(not str(l10n.text("城諾市：重光之日")).is_empty(), "cinematic locale key resolves: %s" % locale)
			_check(str(l10n.text(DECLINE_SUBTITLE)) == str(DECLINE_TRANSLATIONS[locale]), "decline story localization is exact: %s" % locale)
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
