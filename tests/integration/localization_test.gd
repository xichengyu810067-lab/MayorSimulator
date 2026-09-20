extends SceneTree

const TestCleanup := preload("res://tests/helpers/scene_tree_test_cleanup.gd")
const TEST_SAVE_PATH := "user://mayor_simulator/tests/localization_autosave.json"
const TEST_PREFERENCE_PATH := "user://mayor_simulator/tests/fresh-preference/settings.cfg"
const LOCALES := ["zh_TW", "zh_CN", "en", "ja", "ko"]
const BUILDING_BLUEPRINT_LABEL_SOURCE := "建築 · 藍圖"
const BUILDING_BLUEPRINT_LABEL_EN := "Buildings · Blueprints"
const TRADITIONAL_ONLY_CHARACTERS := "體與為這會個來開關學數據處實務點選擇議審醫療環營運讀檔儲滿廠園場發維護評級圖書館電費離"
const GEOMETRY_EPSILON := 1.5
const MUNICIPAL_LAYOUT_RESOLUTION := Vector2i(1440, 900)
const INFORMATIONAL_PAGE_IDS := ["city_data", "report"]
const ONBOARDING_LOCALIZATION_SOURCES := [
	"現在：%s\n原因：比較城市指標，才能看出政策與建設是否真的改善生活。\n結果：切換到另一個資料分頁後，系統會記錄你已完成一次真實比較。\n代價／風險：只讀資料不扣款；城市時間照常前進，請留意指標可能隨時間改變。",
	"現在：%s\n原因：法案必須經議會程序，市長的回應會改變表決與後續制衡。\n結果：完成議會流程並在真實否決後強制施行，會建立法律、司法與監察案件。\n代價／風險：送審本身不立即扣款；法案會按遊戲日審議，強制施行有司法與彈劾風險。",
	"現在：%s\n原因：司法答辯會進入已連結的真實案件，不能用別的案件代替。\n結果：提交後案件會保存你的答辯，裁決完成時再顯示實際結果。\n代價／風險：答辯不立即扣款；審理需要遊戲時間，可能導致罰款、停止命令或監禁。",
	"現在：%s\n原因：監察答辯針對強制施行所產生的同一件調查。\n結果：提交後調查會保存你的答辯，結案時顯示是否彈劾。\n代價／風險：答辯不立即扣款；調查需要遊戲時間，最重大風險是彈劾成立。",
	"現在：%s\n原因：這是目前可操作的教學目標。\n結果：完成真實操作後才會推進教學。\n代價／風險：此操作不會因教學箭頭而自動扣款或快轉時間。",
	"現在：%s\n原因：住宅提供居民可入住的城市空間，也是後續民意與稅收的基礎。\n結果：確認後會建立一筆真實施工工作，完工才成為可用建築。\n代價／風險：本次權威估價 $%d、預計 %d 個遊戲日、占用 %d 名工人；確認時才扣款。",
	"現在：%s\n原因：住宅提供居民可入住的城市空間，也是後續民意與稅收的基礎。\n結果：依序選擇住宅、核准藍圖與地圖位置後，才會建立施工工作。\n代價／風險：瀏覽與選擇不扣款；最後確認前會顯示由真實施工估價計算的金額、工期與人力。",
	"現在：%s\n原因：可營運路線需要真實站點、連續道路與營運設定，只有圖示不算完成。\n結果：完成套案會建立施工工作；全部完工並驗證後才啟用服務。\n代價／風險：規劃本身不扣款；最後繼續前會用真實站點、路線、設施與工人需求計算總工程費。",
	"現在：%s\n原因：可營運路線需要真實站點、連續道路與營運設定，只有圖示不算完成。\n結果：完成套案會建立施工工作；全部完工並驗證後才啟用服務。\n代價／風險：目前套案總工程費 $%d、每月維護 $%d、需要 %d 名工人；按下最後繼續時才一次扣款。",
	"所得稅草稿目前為 %d%%，正式值仍是 %d%%；只有預覽後執行才會寫入正式設定。",
	"現在：%s\n原因：稅率會改變每月收入，也會提高或降低居民負擔與民意壓力。\n結果：%s\n代價／風險：草稿預估月淨額 $%d，安全緩衝 $%d；調高稅率可能增加收入，也可能降低滿意度。城市時間照常前進。",
	"現在：%s\n原因：「%s」來自目前城市狀態；接受代表市府承諾追蹤它的真實完成條件。\n結果：接受後陳情會從待處理改為已接受，達成條件時再記入人物事件。\n代價／風險：接受本身不立即扣款；後續建設或服務可能花費資金與遊戲時間，拒絕則會留下決策紀錄。",
	"司法案件 %s 已進入合議，答辯收件已結束。可正常遊玩，待裁決完成後將顯示真實結果；也可延後教學。",
	"%s %s 已結案。結果：%s；結案日期：%s。案件已結案，無法再提交答辯；請閱讀結果後繼續教學。",
	"拖曳所得稅滑桿，或先聚焦後用左右方向鍵調整至少 1%",
	"在箭頭指向的可用地圖格按一下；若要移動視角，放大後拖過 8 像素",
	"在箭頭指向的分頁列切換到另一個資料分頁",
	"按下「%s」",
	"操作箭頭指向的控制項",
	"按下「預覽變更」核對剛才真實調整的所得稅草稿",
	"按下「執行變更」套用已預覽且仍相符的草稿",
	"目前居民陳情",
	"司法案件",
	"監察案件",
	"裁處罰款",
	"發布停止命令",
	"判處監禁",
	"司法裁決完成",
	"彈劾成立",
	"調查後不予彈劾",
	"監察調查完成",
	"將目前教學延後 3 個遊戲天",
	"確認已閱讀真實案件結果並繼續教學",
]
const PAGE_TITLES := {
	"buildings": "選擇建築",
	"governance": "政策與法案",
	"judicial": "法院審判與辯護",
	"oversight": "監察質詢與彈劾辯護",
	"transport_planning": "城市交通規劃",
	"blueprint": "設計藍圖",
	"finance": "稅率與公共事業費",
	"public_affairs": "民情中心",
	"city_data": "城市數據",
	"report": "月度報告",
}
const HEALTHCARE_SOURCE_KEYS := [
	"正常",
	"容量不足",
	"無法服務",
	"運作正常",
	"容量低於需求",
	"缺少醫院",
	"缺少道路連接",
	"維護未撥款",
	"服務條件未滿足",
	"%s｜%s｜服務 %d/%d｜覆蓋 %d%%",
	"優先建造：醫院",
	"請以道路連接醫院與城市建築。",
	"恢復維護預算後才會提供醫療。",
	"醫療容量不足，請維修或增建醫院。",
	"醫療服務運作正常。",
]
const HEALTHCARE_LOCALIZATION_CASES := {
	"zh_TW": {
		"status": "無法服務",
		"reason": "缺少道路連接",
		"composite": "無法服務｜缺少道路連接｜服務 0/0｜覆蓋 0%",
		"action": "醫療服務運作正常。",
	},
	"zh_CN": {
		"status": "无法服务",
		"reason": "缺少道路连接",
		"composite": "无法服务｜缺少道路连接｜服务 0/0｜覆盖 0%",
		"action": "医疗服务运行正常。",
	},
	"en": {
		"status": "Unavailable",
		"reason": "No road connection",
		"composite": "Unavailable | No road connection | Serving 0/0 | Coverage 0%",
		"action": "Healthcare service is operating normally.",
	},
	"ja": {
		"status": "利用不可",
		"reason": "道路接続がありません",
		"composite": "利用不可｜道路接続がありません｜サービス提供 0/0｜カバー率 0%",
		"action": "医療サービスは正常に稼働しています。",
	},
	"ko": {
		"status": "서비스 불가",
		"reason": "도로 연결 없음",
		"composite": "서비스 불가｜도로 연결 없음｜서비스 0/0｜보장률 0%",
		"action": "의료 서비스가 정상 운영 중입니다.",
	},
}

var _failed := false
var _failure_count := 0
var _l10n


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_l10n = root.get_node_or_null("L10n")
	if _l10n == null:
		_fail("L10n autoload is not available")
		await TestCleanup.finish(self, [], 1)
		return
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var locale_options: Array = _l10n.locale_options()
	_check(locale_options.size() == 5, "five locale options are registered")
	var option_ids: Array[String] = []
	for option in locale_options:
		option_ids.append(str(option["id"]))
	for locale in LOCALES:
		_check(locale in option_ids, "locale %s is supported" % locale)
		var catalog: Dictionary = _l10n.catalogs.get(locale, {})
		for source_variant in catalog.keys():
			var source := str(source_variant)
			_check(
				not source.contains("## ") and not source.contains("\tvar ")
				and not source.contains(") -> String:") and not source.contains("\tif "),
				"%s catalog source is a UI/data literal, not extracted code: %s" % [locale, source]
			)
	_test_fresh_preference_save()
	await _assert_onboarding_guide_initial_localization()

	_l10n.set_locale("zh_TW", false)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(4)
	main.start_save_path = TEST_SAVE_PATH
	_check(main.start_screen.language_selector != null, "start screen exposes a language selector")
	_check(main.start_screen.language_selector.choice_count() == 5, "start screen language selector preserves five languages")
	_check(main.start_screen.language_selector.visible_popup_item_count() == 5, "start screen exposes all five language choices on one popup page")
	_check(main.start_screen.language_selector.shows_all_choices(), "start screen language selector disables More paging")
	_l10n.set_locale("zh_CN", false)
	var dynamic_sample: String = _l10n.text("社會住宅　$2200\n▲ 人口48  ▲ 滿意2　修 $90/月")
	_check(dynamic_sample.contains("社会住宅") and dynamic_sample.contains("满意"), "formatted building-card text translates through a runtime template: %s" % dynamic_sample)
	_check(
		_l10n.text("童話城市・市政治理模擬") == "童话城市・市政治理模拟",
		"Simplified Chinese start subtitle preserves its separator glyph"
	)
	var simplified_catalog: Dictionary = _l10n.catalogs.get("zh_CN", {})
	for source_variant in simplified_catalog.keys():
		var source := str(source_variant)
		var target := str(simplified_catalog[source_variant])
		_check(
			not target.contains("?") or source.contains("?") or source.contains("？"),
			"Simplified Chinese catalog has no replacement-question-mark corruption: %s => %s" % [source, target]
		)
	_l10n.set_locale("en", false)
	_check(_l10n.text("環保複材") == "Eco composite", "English blueprint material uses a concise, precise label")
	var english_dynamic_sample: String = _l10n.text("社會住宅　$2200\n▲ 人口48  ▲ 滿意2　修 $90/月")
	_check(
		english_dynamic_sample.contains("population 48") and english_dynamic_sample.contains("Satisfied 2"),
		"English runtime metrics keep readable spacing: %s" % english_dynamic_sample
	)
	var english_blueprint_label: String = _l10n.text(BUILDING_BLUEPRINT_LABEL_SOURCE)
	_check(
		english_blueprint_label == BUILDING_BLUEPRINT_LABEL_EN,
		"English building+blueprint label is fully localized and semantic: %s" % english_blueprint_label
	)
	var english_petition: String = _l10n.text("陳情受理｜%s「%s」：%s") % ["Huang Jianhong", "A park", "Residents need green space."]
	_check(
		not english_petition.contains("陳情受理") and english_petition.contains("Huang Jianhong") and english_petition.contains("A park") and english_petition.contains("Residents need green space."),
		"Major-event petition template translates while preserving all runtime content: %s" % english_petition
	)
	_check(_l10n.text("版本更新公告") == "Version update announcement", "Version-update report heading has an English translation")
	_l10n.set_locale("zh_TW", false)

	for locale in LOCALES:
		_l10n.clear_missing_sources()
		_l10n.set_locale(locale, false)
		await _settle(4)
		var localized_blueprint_label: String = _l10n.text(BUILDING_BLUEPRINT_LABEL_SOURCE)
		if locale == "en":
			_check(
				localized_blueprint_label == BUILDING_BLUEPRINT_LABEL_EN,
				"English building+blueprint label stays complete in locale loop: %s" % localized_blueprint_label
			)
		else:
			_check(
				not localized_blueprint_label.contains("?") and not localized_blueprint_label.is_empty(),
				"%s blueprint label stays non-placeholder and non-empty: %s" % [locale, localized_blueprint_label]
			)
		_validate_benchmark_format_templates(locale)
		_validate_healthcare_localization(locale)
		_check_visible_translation(main, locale, "新遊戲", "start screen")
		_check_visible_translation(main, locale, "繼續遊戲", "start screen")
		_check_visible_translation(main, locale, "語言", "start screen")
		_check_horizontal_layout(main.start_screen, root.get_visible_rect(), locale, "start screen")
		_audit_tree(main, locale, "start")
		_check(_l10n.missing_sources.is_empty(), "%s start screen has no runtime translation misses: %s" % [locale, _l10n.missing_sources.keys()])

	_l10n.set_locale("en", false)
	main.start_screen.animation_duration = 0.04
	main.start_screen.new_game_button.emit_signal("pressed")
	for _frame in range(120):
		await process_frame
		if not main.start_screen.is_loading():
			break
	_check(main._game_started, "localized new-game flow reaches the city")
	_check(main.settings_overlay != null and main.language_selector == main.settings_overlay.language_selector, "in-game language selector is owned by settings")
	_check(main.language_selector.choice_count() == 5, "settings preserves all five languages")
	_check(main.language_selector.visible_popup_item_count() == 5, "settings exposes all five language choices on one popup page")
	_check(main.language_selector.shows_all_choices(), "settings language selector disables More paging")
	root.content_scale_size = MUNICIPAL_LAYOUT_RESOLUTION
	root.size = MUNICIPAL_LAYOUT_RESOLUTION
	await _settle(3)
	_check(
		Vector2i(roundi(root.get_visible_rect().size.x), roundi(root.get_visible_rect().size.y)) == MUNICIPAL_LAYOUT_RESOLUTION,
		"municipal localization layout uses the required %s viewport" % MUNICIPAL_LAYOUT_RESOLUTION
	)
	var municipal_button := main.find_child("MunicipalButton", true, false) as Button
	_check(municipal_button != null, "public HUD MunicipalButton exists before municipal localization coverage")
	_check(main.municipal_overlay == null, "municipal overlay remains lazy until the public HUD action")
	if municipal_button != null:
		municipal_button.pressed.emit()
	await _settle(2)
	_check(main.municipal_overlay != null, "public HUD MunicipalButton creates the lazy municipal overlay")
	var forced_case_name := "商業促進法案強制施行審查"
	var forced_case_result: Dictionary = main.vertical_slice.governance.justice_system.open_judicial_case(
		"commerce_act",
		main.vertical_slice.game_day(),
		51,
		forced_case_name
	)
	_check(bool(forced_case_result.get("ok", false)), "forced-enactment judicial case can be seeded for localization regression coverage")
	main.judicial_panel.refresh(main.vertical_slice.governance.justice_system)
	var oversight_case_result: Dictionary = main.vertical_slice.governance.justice_system.open_oversight_case(
		"official_mayor",
		["違法強制施行法案", "未遵守議會否決決議"],
		63,
		main.vertical_slice.game_day()
	)
	_check(bool(oversight_case_result.get("ok", false)), "oversight case can be seeded for defense-toast localization coverage")
	main.oversight_panel.refresh(main.vertical_slice.governance.justice_system)

	for locale in LOCALES:
		_l10n.clear_missing_sources()
		_l10n.set_locale(locale, false)
		await _settle(4)
		var review_template: String = str(_l10n.text("✓ 已收件｜審核中｜剩餘 %d 個遊戲日"))
		_check(review_template.count("%d") == 1, "%s blueprint review text contains only the game-day value: %s" % [locale, review_template])
		for source in ["市政", "設定", "離開"]:
			_check_visible_translation(main, locale, source, "action dock")
		main.municipal_overlay.call("open_hub")
		await process_frame
		_check_visible_translation(main, locale, "市政服務中心", "municipal hub")
		_check_visible_translation(main, locale, "選擇市政工作；七項服務皆可直接開啟。", "municipal hub")
		_check_visible_translation(main, locale, "建設與藍圖", "municipal hub")
		var municipal_back := main.municipal_overlay.find_child("BackButton", true, false) as Button
		_check(
			municipal_back != null and municipal_back.tooltip_text == _l10n.text("返回上一頁（Esc）"),
			"%s municipal BackButton tooltip is exactly localized: %s" % [locale, "<missing>" if municipal_back == null else municipal_back.tooltip_text]
		)
		var municipal_window := main.municipal_overlay.get_node_or_null("MunicipalWindow") as Control
		_check(municipal_window != null, "municipal window exists for layout checks")
		if municipal_window != null:
			_check_horizontal_layout(main.municipal_overlay, municipal_window.get_global_rect(), locale, "municipal hub")
		for page_id in PAGE_TITLES.keys():
			main.municipal_overlay.call("open_page", page_id)
			await _settle(2)
			_check_visible_translation(main, locale, str(PAGE_TITLES[page_id]), "%s page" % page_id)
			await _assert_municipal_page_layout(main, page_id, locale)
			if page_id == "finance":
				if int(main.call("debug_fiscal_draft_state").get("dirty_count", 0)) == 0:
					main.call("_on_tax_changed", float(int(main.tax_rates["income"]) + 1), "income")
					await _settle(2)
				var fiscal_draft_status := main.municipal_overlay.find_child("FiscalDraftStatus", true, false) as Label
				var fiscal_draft_state: Dictionary = main.call("debug_fiscal_draft_state")
				var dirty_count := int(fiscal_draft_state.get("dirty_count", 0))
				_check(
					fiscal_draft_status != null and dirty_count > 0,
					"%s finance page exposes a pending fiscal draft for localization coverage" % locale
				)
				if fiscal_draft_status != null:
					var projected_net := int(fiscal_draft_state.get("projected_net", 0))
					var safety_buffer := int(main.call("_fiscal_safety_buffer"))
					var operating_source := "● 財政安全\n預估淨額已覆蓋市政支出與安全緩衝。" if projected_net >= safety_buffer else ("● 緩衝不足\n可運作，但無法承受收入波動。" if projected_net >= 0 else "● 赤字預警\n目前收費不足以支應每月市政運作。")
					var expected_status := "%s\n%s" % [
						_l10n.text(operating_source),
						_l10n.text("尚未套用：%d 項變更\n可預覽整組草稿後再執行。") % dirty_count,
					]
					_check(
						fiscal_draft_status.text == expected_status,
						"%s pending fiscal draft status is exactly localized: expected='%s' actual='%s'" % [locale, expected_status, fiscal_draft_status.text]
					)
			if page_id == "judicial":
				var case_title := main.judicial_panel.get("_case_title") as Label
				var expected_case_title: String = _l10n.text("違法施行案件：%s") % _l10n.text("商業促進法案")
				_check(
					case_title != null and case_title.text == expected_case_title,
					"%s forced-enactment judicial title is exact: expected='%s' actual='%s'" % [
						locale,
						expected_case_title,
						"<missing>" if case_title == null else case_title.text,
					]
				)
				var judicial_defense_result: Dictionary = main.judicial_panel.submit_current_defense("public_interest")
				_check(bool(judicial_defense_result.get("ok", false)), "%s judicial defense can be submitted" % locale)
				var expected_judicial_toast: String = _l10n.text("%s辯護資料已提交。") % _l10n.text("法院")
				_check(
					main.hint_label.text == expected_judicial_toast,
					"%s judicial defense toast is exact: expected='%s' actual='%s'" % [locale, expected_judicial_toast, main.hint_label.text]
				)
			if page_id == "oversight":
				var oversight_defense_result: Dictionary = main.oversight_panel.submit_current_defense("full_disclosure")
				_check(bool(oversight_defense_result.get("ok", false)), "%s oversight defense can be submitted" % locale)
				var expected_oversight_toast: String = _l10n.text("%s辯護資料已提交。") % _l10n.text("監察質詢")
				_check(
					main.hint_label.text == expected_oversight_toast,
					"%s oversight defense toast is exact: expected='%s' actual='%s'" % [locale, expected_oversight_toast, main.hint_label.text]
				)
			if page_id == "blueprint":
				var material_picker := main.vertical_slice_panel.get("_material_picker") as OptionButton
				var eco_index := -1
				if material_picker != null and material_picker.select_choice("eco_composite"):
					for index in material_picker.item_count:
						if str(material_picker.get_item_metadata(index)) == "eco_composite":
							eco_index = index
							break
				_check(material_picker != null and eco_index >= 0, "%s eco-composite blueprint option exists" % locale)
				if material_picker != null and eco_index >= 0:
					material_picker.emit_signal("choice_selected", "eco_composite")
					var expected_short_material: String = _l10n.text("環保複材")
					var expected_full_material: String = _l10n.text("環境友善複合材料")
					_check(
						material_picker.get_item_text(eco_index) == expected_short_material,
						"%s eco-composite option uses the exact short label: expected='%s' actual='%s'" % [locale, expected_short_material, material_picker.get_item_text(eco_index)]
					)
					_check(
						material_picker.tooltip_text == expected_full_material,
						"%s eco-composite tooltip preserves the full material name: expected='%s' actual='%s'" % [locale, expected_full_material, material_picker.tooltip_text]
					)
			if municipal_window != null:
				_check_horizontal_layout(main.municipal_overlay, municipal_window.get_global_rect(), locale, "%s page" % page_id)
			_audit_tree(main, locale, "city", true)
		# Lazy municipal pages are localized and audited when they become active.
		# Hidden siblings may be refreshed later in the source locale, then are
		# localized again on their next activation, so do not re-audit them eagerly.
		_check(_l10n.missing_sources.is_empty(), "%s city UI has no runtime translation misses: %s" % [locale, _l10n.missing_sources.keys()])
		main.municipal_overlay.call("close_overlay")
		main.settings_button.emit_signal("pressed")
		await process_frame
		for source in ["設定", "介面語言", "顯示模式", "淺色", "深色"]:
			_check_visible_translation(main, locale, source, "settings")
		_audit_tree(main, locale, "settings", true)
		main.settings_overlay.close()
		main.exit_confirmation.call("open")
		await process_frame
		for source in ["要離開 Mayor Simulator 嗎？", "取消", "離開遊戲"]:
			_check_visible_translation(main, locale, source, "exit confirmation")
		_audit_tree(main, locale, "exit confirmation", true)
		main.exit_confirmation.call("close")

	await _assert_onboarding_localization(main)

	_l10n.set_locale("zh_TW", false)
	_cleanup_save()
	var exit_code := 1 if _failed else 0
	if not _failed:
		print("Five-language localization integration test passed. Catalogs=%s" % _l10n.catalog_coverage())
	await TestCleanup.finish(self, [main], exit_code)


func _assert_onboarding_localization(main: Node) -> void:
	if main.onboarding_progress.is_story_pending():
		_check(main.onboarding_progress.begin_guide(), "localization fixture begins the authoritative onboarding guide")
	var progress_before: Dictionary = main.onboarding_progress.snapshot()
	var receipt_before: Array = main.onboarding_progress.receipts()
	var guide: OnboardingGuide = main.onboarding_guide as OnboardingGuide
	_check(guide != null, "city scene provides an onboarding guide for live localization")
	for locale in LOCALES:
		_l10n.clear_missing_sources()
		_l10n.set_locale(locale, false)
		for source in ONBOARDING_LOCALIZATION_SOURCES:
			var localized := str(_l10n.text(source))
			_check(not localized.is_empty(), "%s onboarding source has non-empty localized copy" % locale)
			if locale in ["en", "ko"]:
				_check(not _contains_han(localized), "%s onboarding source contains no untranslated Han text: %s" % [locale, localized])
			if locale == "zh_CN":
				_check(not _contains_any(localized, TRADITIONAL_ONLY_CHARACTERS), "zh_CN onboarding source has no Traditional-only text: %s" % localized)
		if guide != null:
			guide.refresh_localization()
			_check(
				guide.get_node("OnboardingDeferButton").text == _l10n.text("延後教學")
				and guide.get_node("OnboardingResultReviewButton").text == _l10n.text("已閱讀結果，繼續"),
				"%s guide action labels refresh in place" % locale
			)
		_check(_l10n.missing_sources.is_empty(), "%s onboarding copy has no runtime translation misses: %s" % [locale, _l10n.missing_sources.keys()])
	_check(main.onboarding_progress.snapshot() == progress_before and main.onboarding_progress.receipts() == receipt_before, "guide locale changes preserve onboarding progress and receipts")
	if guide != null:
		guide.invalidate_target()


func _assert_onboarding_guide_initial_localization() -> void:
	for locale in LOCALES:
		_l10n.set_locale(locale, false)
		var guide := OnboardingGuide.new()
		root.add_child(guide)
		await process_frame
		_check(
			guide.get_node("OnboardingDeferButton").text == _l10n.text("延後教學")
			and guide.get_node("OnboardingResultReviewButton").text == _l10n.text("已閱讀結果，繼續"),
			"%s guide initializes action labels after joining the scene tree" % locale
		)
		_check(
			guide.get_node("OnboardingDeferButton").tooltip_text == _l10n.text("將目前教學延後 3 個遊戲天")
			and guide.get_node("OnboardingResultReviewButton").tooltip_text == _l10n.text("確認已閱讀真實案件結果並繼續教學"),
			"%s guide initializes action tooltips after joining the scene tree" % locale
		)
		guide.queue_free()
		await process_frame


func _audit_tree(node: Node, locale: String, context: String, visible_only: bool = false) -> void:
	if visible_only and node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if bool(node.get_meta("l10n_skip", false)):
		return
	var values: Array[String] = []
	if node is Label or node is Button or node is RichTextLabel:
		values.append(str(node.get("text")))
	if node is Control:
		values.append(str(node.get("tooltip_text")))
	if node is LineEdit or node is TextEdit:
		values.append(str(node.get("placeholder_text")))
	if node is OptionButton:
		for index in (node as OptionButton).item_count:
			values.append((node as OptionButton).get_item_text(index))
	if node is TabContainer:
		for index in (node as TabContainer).get_tab_count():
			values.append((node as TabContainer).get_tab_title(index))
	for value in values:
		if locale in ["en", "ko"] and _contains_han(value):
			_fail("%s %s contains untranslated Han text on %s: %s" % [locale, context, node.get_path(), value])
		if locale == "zh_CN" and _contains_any(value, TRADITIONAL_ONLY_CHARACTERS):
			_fail("zh_CN %s contains Traditional-only text on %s: %s" % [context, node.get_path(), value])
	for child in node.get_children():
		_audit_tree(child, locale, context, visible_only)


func _check_visible_translation(root_node: Node, locale: String, source: String, context: String) -> void:
	var values: Array[String] = []
	_collect_visible_values(root_node, values)
	var target := str(_l10n.text(source))
	_check(target in values, "%s %s does not show expected translation for '%s': '%s'" % [locale, context, source, target])
	if locale != "zh_TW" and target != source:
		_check(source not in values, "%s %s still shows source-language text: %s" % [locale, context, source])


func _collect_visible_values(node: Node, values: Array[String]) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if bool(node.get_meta("l10n_skip", false)):
		return
	if node is Label or node is Button or node is RichTextLabel:
		values.append(str(node.get("text")))
	if node is Control:
		values.append(str(node.get("tooltip_text")))
	if node is LineEdit or node is TextEdit:
		values.append(str(node.get("placeholder_text")))
	if node is OptionButton:
		for index in (node as OptionButton).item_count:
			values.append((node as OptionButton).get_item_text(index))
	if node is TabContainer:
		for index in (node as TabContainer).get_tab_count():
			values.append((node as TabContainer).get_tab_title(index))
	for child in node.get_children():
		_collect_visible_values(child, values)


func _check_horizontal_layout(node: Node, bounds: Rect2, locale: String, context: String) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Label or node is Button or node is OptionButton or node is LineEdit:
		var control := node as Control
		var rect := control.get_global_rect()
		if rect.size.x > 0.5 and rect.size.y > 0.5:
			var left_ok := rect.position.x >= bounds.position.x - GEOMETRY_EPSILON
			var right_ok := rect.end.x <= bounds.end.x + GEOMETRY_EPSILON
			var top_ok := rect.position.y >= bounds.position.y - GEOMETRY_EPSILON
			var bottom_ok := rect.end.y <= bounds.end.y + GEOMETRY_EPSILON
			var scroll := _scroll_ancestor(control)
			if scroll != null and not (top_ok and bottom_ok):
				var scroll_rect := scroll.get_global_rect()
				var vertical_scroll_is_safe := (
					scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
					and scroll_rect.position.x >= bounds.position.x - GEOMETRY_EPSILON
					and scroll_rect.end.x <= bounds.end.x + GEOMETRY_EPSILON
					and scroll_rect.position.y >= bounds.position.y - GEOMETRY_EPSILON
					and scroll_rect.end.y <= bounds.end.y + GEOMETRY_EPSILON
				)
				top_ok = vertical_scroll_is_safe
				bottom_ok = vertical_scroll_is_safe

			_check(
				left_ok and right_ok and top_ok and bottom_ok,
				"%s %s control escapes its layout bounds on %s: rect=%s bounds=%s text=%s" % [
					locale,
					context,
					node.get_path(),
					rect,
					bounds,
					str(node.get("text")),
				]
			)
			_assert_visible_text_metrics(control, locale, context)
	for child in node.get_children():
		_check_horizontal_layout(child, bounds, locale, context)


func _assert_visible_text_metrics(control: Control, locale: String, context: String) -> void:
	if not _requires_no_trimming(control):
		return
	var text := _visible_control_text(control)
	if text.is_empty():
		return
	var font := control.get_theme_font("font")
	var font_size := control.get_theme_font_size("font_size")
	_check(font != null and font_size > 0, "%s %s control '%s' exposes a theme font and font size" % [locale, context, control.get_path()])
	if font == null or font_size <= 0:
		return
	var content_size := _text_content_size(control)
	var natural_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, -1, TextServer.BREAK_MANDATORY)
	var rendered_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, content_size.x), font_size)
	var wraps := false
	if control is Label:
		wraps = (control as Label).autowrap_mode != TextServer.AUTOWRAP_OFF
	elif control is Button:
		wraps = (control as Button).autowrap_mode != TextServer.AUTOWRAP_OFF
	var required_size := rendered_size if wraps else natural_size
	var minimum_size := control.get_combined_minimum_size()
	var allocated_size := control.get_global_rect().size
	_check(
		content_size.x + GEOMETRY_EPSILON >= required_size.x and content_size.y + GEOMETRY_EPSILON >= required_size.y,
		"%s %s control '%s' renders its theme-font text without overflow: text=%s required=%s content=%s" % [locale, context, control.get_path(), text, required_size, content_size]
	)
	_check(
		allocated_size.x + GEOMETRY_EPSILON >= minimum_size.x and allocated_size.y + GEOMETRY_EPSILON >= minimum_size.y,
		"%s %s control '%s' receives at least its computed minimum size: minimum=%s actual=%s" % [locale, context, control.get_path(), minimum_size, allocated_size]
	)


func _requires_no_trimming(control: Control) -> bool:
	if control is Label:
		return (control as Label).text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING
	if control is Button:
		return (control as Button).text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING
	return false


func _visible_control_text(control: Control) -> String:
	if control is Label or control is Button or control is OptionButton or control is LineEdit:
		return str(control.get("text"))
	return ""


func _text_content_size(control: Control) -> Vector2:
	var content_size := control.get_global_rect().size
	var style_box := control.get_theme_stylebox("normal")
	if style_box != null:
		content_size.x -= style_box.get_margin(SIDE_LEFT) + style_box.get_margin(SIDE_RIGHT)
		content_size.y -= style_box.get_margin(SIDE_TOP) + style_box.get_margin(SIDE_BOTTOM)
	return Vector2(maxf(0.0, content_size.x), maxf(0.0, content_size.y))


func _assert_municipal_page_layout(main: Node, page_id: String, locale: String) -> void:
	if main == null or main.municipal_overlay == null:
		return
	var page_host: Node = main.municipal_overlay.find_child("PageHost", true, false)
	if page_host == null:
		_check(false, "%s %s lacks PageHost for long-copy layout validation" % [locale, page_id])
		return
	var page_host_control: Control = page_host as Control
	var long_label := _longest_visible_label(page_host_control)
	var button := _first_visible_button(page_host_control)
	_check(long_label != null, "%s %s exposes a long label for PageHost reveal validation" % [locale, page_id])
	if long_label != null:
		await _assert_control_reveals_in_page_host(long_label, page_host_control, locale, "%s long label" % page_id)
	if page_id in INFORMATIONAL_PAGE_IDS:
		_check(button == null, "%s %s remains an information page without an invented action button" % [locale, page_id])
		_check(long_label != null, "%s %s exposes a readable content sentinel that vertical scrolling can reveal" % [locale, page_id])
		return
	_check(button != null, "%s %s exposes a button for PageHost reveal validation" % [locale, page_id])
	if button != null:
		await _assert_control_reveals_in_page_host(button, page_host_control, locale, "%s button" % page_id)


func _longest_visible_label(root_node: Node) -> Label:
	var selected: Label
	var selected_length := -1
	if root_node == null:
		return null
	for candidate_variant in root_node.find_children("*", "Label", true, false):
		var candidate := candidate_variant as Label
		if candidate != null and candidate.is_visible_in_tree():
			var length := candidate.text.length()
			if length > selected_length:
				selected = candidate
				selected_length = length
	return selected


func _first_visible_button(root_node: Node) -> BaseButton:
	if root_node == null:
		return null
	for candidate_variant in root_node.find_children("*", "BaseButton", true, false):
		var candidate := candidate_variant as BaseButton
		if candidate != null and candidate.is_visible_in_tree() and not candidate.disabled:
			return candidate
	return null


func _assert_control_reveals_in_page_host(control: Control, page_host: Control, locale: String, context: String) -> void:
	var scroll_positions: Array[Dictionary] = []
	var original_rect := control.get_global_rect()
	var host_rect := page_host.get_global_rect()
	var required_visible_height := minf(original_rect.size.y, host_rect.size.y)
	for scroll: ScrollContainer in _scroll_ancestors(control, page_host):
		required_visible_height = minf(required_visible_height, scroll.get_global_rect().size.y)
	var original_effective_rect := _effective_visible_rect(control).intersection(host_rect)
	var needs_vertical_reveal := original_effective_rect.size.y < required_visible_height - GEOMETRY_EPSILON
	var vertical_reveal_observed := false
	for scroll: ScrollContainer in _scroll_ancestors(control, page_host):
		scroll_positions.append({
			"scroll": scroll,
			"horizontal": scroll.scroll_horizontal,
			"vertical": scroll.scroll_vertical,
		})
		_check(
			scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"%s %s forbids horizontal scrolling inside PageHost" % [locale, context]
		)
		_check(
			scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
			"%s %s permits vertical reveal inside PageHost" % [locale, context]
		)
		var vertical_before := scroll.scroll_vertical
		scroll.ensure_control_visible(control)
		await _settle(2)
		vertical_reveal_observed = vertical_reveal_observed or absf(float(scroll.scroll_vertical - vertical_before)) > GEOMETRY_EPSILON
	var revealed_rect := control.get_global_rect()
	var effective_rect := _effective_visible_rect(control).intersection(host_rect)
	_check(
		_rect_is_finite(revealed_rect)
		and _rect_is_finite(effective_rect)
		and effective_rect.size.x >= revealed_rect.size.x - GEOMETRY_EPSILON
		and effective_rect.size.y >= required_visible_height - GEOMETRY_EPSILON,
		"%s %s is fully revealed inside PageHost: raw=%s effective=%s host=%s" % [locale, context, revealed_rect, effective_rect, host_rect]
	)
	if needs_vertical_reveal:
		_check(vertical_reveal_observed, "%s %s is revealed through an actual vertical scroll movement" % [locale, context])
	if control is Label:
		_check(not (control as Label).clip_text, "%s %s does not clip localized copy" % [locale, context])
	for snapshot in scroll_positions:
		var scroll := snapshot.get("scroll") as ScrollContainer
		if scroll != null and is_instance_valid(scroll):
			scroll.scroll_horizontal = int(snapshot.get("horizontal", 0))
			scroll.scroll_vertical = int(snapshot.get("vertical", 0))
	await _settle(2)


func _scroll_ancestor(control: Control) -> ScrollContainer:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			return ancestor as ScrollContainer
		ancestor = ancestor.get_parent()
	return null


func _scroll_ancestors(control: Control, boundary: Control) -> Array[ScrollContainer]:
	var result: Array[ScrollContainer] = []
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			result.append(ancestor as ScrollContainer)
		if ancestor == boundary:
			break
		ancestor = ancestor.get_parent()
	return result


func _rect_is_finite(rect: Rect2) -> bool:
	return (
		is_finite(rect.position.x)
		and is_finite(rect.position.y)
		and is_finite(rect.size.x)
		and is_finite(rect.size.y)
	)


func _effective_visible_rect(control: Control) -> Rect2:
	var visible_rect := control.get_global_rect()
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents:
			visible_rect = visible_rect.intersection((ancestor as Control).get_global_rect())
		ancestor = ancestor.get_parent()
	return visible_rect


func _contains_han(value: String) -> bool:
	for index in value.length():
		var code := value.unicode_at(index)
		if code >= 0x3400 and code <= 0x9FFF:
			return true
	return false


func _validate_benchmark_format_templates(locale: String) -> void:
	for source in ["高於%s +%s 個百分點", "低於%s −%s 個百分點"]:
		var translated: String = _l10n.text(source)
		var remaining := translated.replace("%s", "").replace("%%", "")
		_check(translated.count("%s") == 2, "%s benchmark template preserves exactly two string placeholders: %s" % [locale, translated])
		_check(not remaining.contains("%"), "%s benchmark template has no unsupported percent formatter: %s" % [locale, translated])


func _validate_healthcare_localization(locale: String) -> void:
	var catalog: Dictionary = _l10n.catalogs.get(locale, {})
	for source in HEALTHCARE_SOURCE_KEYS:
		_check(catalog.has(source), "%s healthcare catalog has exact key: %s" % [locale, source])
	var expected: Dictionary = HEALTHCARE_LOCALIZATION_CASES[locale]
	var status: String = _l10n.text("無法服務")
	var reason: String = _l10n.text("缺少道路連接")
	var composite: String = _l10n.text("%s｜%s｜服務 %d/%d｜覆蓋 %d%%") % [status, reason, 0, 0, 0]
	var action: String = _l10n.text("醫療服務運作正常。")
	_check(status == str(expected["status"]), "%s healthcare status is exact: %s" % [locale, status])
	_check(reason == str(expected["reason"]), "%s healthcare reason is exact: %s" % [locale, reason])
	_check(composite == str(expected["composite"]), "%s healthcare composite is exact: %s" % [locale, composite])
	_check(action == str(expected["action"]), "%s healthcare action is exact: %s" % [locale, action])
	if locale in ["en", "ko"]:
		_check(not _contains_han(composite + action), "%s healthcare copy has no untranslated Han text: %s" % [locale, composite])
	if locale == "zh_CN":
		_check(
			not _contains_any(composite + action, TRADITIONAL_ONLY_CHARACTERS),
			"zh_CN healthcare copy has no Traditional-only text: %s" % composite
		)


func _contains_any(value: String, characters: String) -> bool:
	for index in characters.length():
		if value.contains(characters.substr(index, 1)):
			return true
	return false


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _test_fresh_preference_save() -> void:
	_cleanup_preference_probe()
	var absolute_path := ProjectSettings.globalize_path(TEST_PREFERENCE_PATH)
	var parent_path := absolute_path.get_base_dir()
	_check(not DirAccess.dir_exists_absolute(parent_path), "preference regression starts without its parent directory")
	var original_locale: String = _l10n.current_locale
	_l10n.set_locale("en", false)
	var save_error: int = _l10n.call("_save_preference_file", TEST_PREFERENCE_PATH)
	_check(save_error == OK, "locale preference creates a missing parent directory before saving: %d" % save_error)
	var config := ConfigFile.new()
	var load_error := config.load(TEST_PREFERENCE_PATH)
	_check(load_error == OK, "saved locale preference can be loaded: %d" % load_error)
	_check(str(config.get_value("localization", "locale", "")) == "en", "saved locale preference preserves the selected locale")
	_l10n.set_locale(original_locale, false)
	_cleanup_preference_probe()


func _cleanup_preference_probe() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_PREFERENCE_PATH)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	var parent_path := absolute_path.get_base_dir()
	if DirAccess.dir_exists_absolute(parent_path):
		DirAccess.remove_absolute(parent_path)


func _cleanup_save() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	for candidate in [absolute, absolute + ".tmp", absolute + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	_failure_count += 1
	if _failure_count <= 40:
		push_error("Localization check failed: %s" % message)
