extends ScrollContainer

const ProgressiveOptionButtonScript = preload("res://ui/components/progressive_option_button.gd")
const UiIconCatalog = preload("res://ui/theme/ui_icon_catalog.gd")

const UI_BODY_FONT_SIZE := 20
const UI_PICKER_FONT_SIZE := 18
const UI_TITLE_FONT_SIZE := 24
const UI_CONTROL_HEIGHT := 44
const UI_ACTION_HEIGHT := 50
const LIGHT_TEXT := Color(0.07, 0.12, 0.18)
const LIGHT_MUTED := Color(0.24, 0.31, 0.38)
const DARK_TEXT := Color(0.90, 0.94, 0.97)
const DARK_MUTED := Color(0.68, 0.76, 0.82)
const ACCENT := Color(0.05, 0.43, 0.70)
const ACCENT_DARK := Color(0.03, 0.31, 0.52)
const GOOD := Color(0.05, 0.55, 0.30)
const CAUTION := Color(0.82, 0.55, 0.05)
const BLUEPRINT_ICON_KEYS := {
	"hero": "blueprint",
	"material": "material",
	"size": "size",
	"floors": "floors",
	"workers": "workers",
	"decoration": "decoration"
}

signal blueprint_submit_requested(payload: Dictionary)
signal placement_requested(building_name: String)
signal worker_count_changed(count: int)
signal design_changed(payload: Dictionary)
signal blueprint_library_selection_requested(building_name: String, library_id: String)

var _building_name := "住宅"
var _material_picker: OptionButton
var _size_picker: OptionButton
var _floor_input: SpinBox
var _worker_input: SpinBox
var _decor_picker: OptionButton
var _construction_label: Label
var _review_label: Label
var _quote_label: Label
var _workers_label: Label
var _workers_bar: ProgressBar
var _submit_button: Button
var _custom_submit_button: Button
var _library_picker: OptionButton
var _library_label: Label
var _selected_building_label: Label
var _dark_mode := false
var _text_labels: Array[Label] = []
var _styled_controls: Array[Control] = []
var _visual_cards: Array[PanelContainer] = []
var _action_variants: Dictionary = {}
var _primary_action_mode := "submit"
var _last_review_binding := ""
var _library_signature := ""
var _suppress_design_change := false
var _active_review: Dictionary = {}
var _last_view_model: Dictionary = {}
var _transport_station_mode := false

func _init() -> void:
	name = "設計藍圖"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_build_content()

func set_selected_building(display_name: String) -> void:
	_building_name = display_name
	if _selected_building_label != null:
		_selected_building_label.text = L10n.text("正在設計：%s") % L10n.text(_building_name)

func set_dark_mode(enabled: bool) -> void:
	_dark_mode = enabled
	_refresh_palette()

func set_view_model(view_model: Dictionary) -> void:
	_last_view_model = view_model.duplicate(true)
	_transport_station_mode = bool(view_model.get("transport_station_mode", false))
	var available_workers := int(view_model.get("available_workers", 20))
	_construction_label.text = "⌂  " + str(view_model.get("construction_text", L10n.text("目前沒有施工或送審案件。")))
	_workers_label.text = L10n.text("工  工程隊 %d / 20 可用  •  %d%%") % [available_workers, available_workers * 5]
	_set_visual_bar(_workers_bar, available_workers, GOOD if available_workers >= 10 else CAUTION)
	_apply_blueprint_library(
		view_model.get("blueprint_library", []),
		str(view_model.get("active_blueprint_id", ""))
	)
	var review_variant = view_model.get("blueprint_review", {})
	var review: Dictionary = review_variant if review_variant is Dictionary else {}
	_active_review = review.duplicate(true)
	_sync_blueprint_from_review(review)
	_apply_review_state(review)
	var quote_variant = view_model.get("placement_quote", {})
	_update_placement_quote(quote_variant if quote_variant is Dictionary else {})


func refresh_localization() -> void:
	# Static labels keep their original source metadata. Dynamic values below are
	# rebuilt from authority after the locale changes so they never retain a
	# previous language merely because their content signature did not change.
	L10n.localize_tree(self)
	for picker in [_material_picker, _size_picker, _decor_picker, _library_picker]:
		if picker != null and picker.has_method("refresh_localization"):
			picker.call("refresh_localization")
	_library_signature = ""
	_apply_blueprint_library(
		_last_view_model.get("blueprint_library", []),
		str(_last_view_model.get("active_blueprint_id", ""))
	)
	set_selected_building(_building_name)
	_apply_review_state(_active_review)
	var quote_variant = _last_view_model.get("placement_quote", {})
	_update_placement_quote(quote_variant if quote_variant is Dictionary else {})

func selected_worker_count() -> int:
	return int(_worker_input.value)

func _build_content() -> void:
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(900, 0)
	content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_theme_constant_override("separation", 12)
	add_child(content)

	var hero := _visual_card()
	hero.name = "BlueprintHero"
	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", 16)
	hero.add_child(hero_row)
	hero_row.add_child(_icon_rect(str(BLUEPRINT_ICON_KEYS["hero"]), Vector2(112, 96)))
	var hero_copy := VBoxContainer.new()
	hero_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_copy.add_theme_constant_override("separation", 2)
	hero_row.add_child(hero_copy)
	hero_copy.add_child(_title("設計藍圖"))
	_selected_building_label = _status_label("正在設計：%s" % _building_name)
	_selected_building_label.set_meta("l10n_skip", true)
	_selected_building_label.add_theme_font_size_override("font_size", UI_TITLE_FONT_SIZE)
	hero_copy.add_child(_selected_building_label)
	var guide := _status_label("五項設計會同頁顯示；每次調整都立即重算開工前估價。")
	guide.custom_minimum_size = Vector2(0, 56)
	hero_copy.add_child(guide)
	content.add_child(hero)

	var library_card := _visual_card(true)
	library_card.name = "ApprovedBlueprintLibrary"
	var library_row := HBoxContainer.new()
	library_row.add_theme_constant_override("separation", 12)
	library_card.add_child(library_row)
	library_row.add_child(_icon_rect("blueprint", Vector2(70, 64)))
	var library_copy := VBoxContainer.new()
	library_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_copy.add_theme_constant_override("separation", 3)
	library_row.add_child(library_copy)
	_library_label = _status_label("永久藍圖庫｜載入中")
	_library_label.name = "BlueprintLibraryStatus"
	_library_label.set_meta("l10n_skip", true)
	_library_label.set_meta("readability_muted", false)
	library_copy.add_child(_library_label)
	_library_picker = _picker([{"id": "loading", "name": "載入核准藍圖中"}])
	_library_picker.name = "ApprovedBlueprintPicker"
	_library_picker.custom_minimum_size = Vector2(460, UI_CONTROL_HEIGHT)
	_library_picker.connect("choice_selected", _on_library_choice_selected)
	library_copy.add_child(_library_picker)
	content.add_child(library_card)

	_material_picker = _picker([
		{"id": "wood", "name": "木造"},
		{"id": "brick", "name": "磚造"},
		{"id": "steel", "name": "鋼構"},
		{"id": "eco_composite", "name": "環保複材", "tooltip": "環境友善複合材料"}
	])
	_material_picker.name = "BlueprintMaterial"
	_material_picker.choice_selected.connect(_on_design_control_changed)

	_size_picker = _picker([
		{"id": "small", "name": "小型"},
		{"id": "medium", "name": "中型"},
		{"id": "large", "name": "大型"}
	])
	_size_picker.select(1)
	_size_picker.name = "BlueprintSize"
	_size_picker.choice_selected.connect(_on_design_control_changed)

	_floor_input = SpinBox.new()
	_floor_input.min_value = 1
	_floor_input.max_value = 40
	_floor_input.value = 2
	_floor_input.custom_minimum_size = Vector2(112, UI_CONTROL_HEIGHT)
	_style_control(_floor_input)
	_floor_input.name = "BlueprintFloors"
	_floor_input.value_changed.connect(func(_value: float) -> void: _on_design_control_changed())

	_worker_input = SpinBox.new()
	_worker_input.min_value = 1
	_worker_input.max_value = 20
	_worker_input.value = 5
	_worker_input.custom_minimum_size = Vector2(112, UI_CONTROL_HEIGHT)
	_style_control(_worker_input)
	_worker_input.name = "BlueprintWorkers"
	_worker_input.value_changed.connect(_on_worker_count_changed)

	_decor_picker = _picker([
		{"id": "flowers", "name": "花草"},
		{"id": "flags", "name": "旗幟"},
		{"id": "window_trim", "name": "窗框"}
	])
	_decor_picker.name = "BlueprintDecoration"
	_decor_picker.choice_selected.connect(_on_design_control_changed)

	var design_workspace := HBoxContainer.new()
	design_workspace.name = "BlueprintDesignWorkspace"
	design_workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	design_workspace.add_theme_constant_override("separation", 12)
	design_workspace.set_meta("single_page_design", true)
	design_workspace.set_meta("design_control_count", 5)
	design_workspace.add_child(_design_group_card(
		"size",
		"建築規格",
		"材質、規模與樓層",
		[
			{"label": "材質", "control": _material_picker},
			{"label": "規模", "control": _size_picker},
			{"label": "樓層", "control": _floor_input},
		]
	))
	design_workspace.add_child(_design_group_card(
		"workers",
		"施工配置",
		"人力與裝飾",
		[
			{"label": "人力", "control": _worker_input},
			{"label": "裝飾", "control": _decor_picker},
		]
	))
	content.add_child(design_workspace)

	var quote_card := _visual_card(true)
	quote_card.name = "BlueprintQuoteCard"
	var quote_stack := VBoxContainer.new()
	quote_card.add_child(quote_stack)
	_quote_label = _status_label("調整任何選項後，總價、工期與占地會立即更新。")
	_quote_label.name = "BlueprintPlacementQuote"
	_quote_label.set_meta("l10n_skip", true)
	_quote_label.set_meta("readability_muted", false)
	quote_stack.add_child(_quote_label)
	content.add_child(quote_card)

	_submit_button = _action_button("送審藍圖", true)
	_submit_button.name = "SubmitBlueprintButton"
	_submit_button.icon = UiIconCatalog.texture(str(BLUEPRINT_ICON_KEYS["hero"]))
	_submit_button.add_theme_constant_override("icon_max_width", 42)
	_submit_button.expand_icon = true
	_submit_button.tooltip_text = "送交審查；核准後即可回到地圖點空地開工。"
	_submit_button.pressed.connect(_on_primary_action_pressed)
	_custom_submit_button = _action_button("將目前調整送審為自訂版")
	_custom_submit_button.name = "SubmitCustomBlueprintButton"
	_custom_submit_button.icon = UiIconCatalog.texture("new")
	_custom_submit_button.add_theme_constant_override("icon_max_width", 36)
	_custom_submit_button.expand_icon = true
	_custom_submit_button.tooltip_text = "目前核准版仍會保留；新版本通過後會另存進永久藍圖庫。"
	_custom_submit_button.pressed.connect(_emit_blueprint)
	_custom_submit_button.visible = false

	var status_card := _visual_card(true)
	status_card.name = "BlueprintStatus"
	var status_stack := VBoxContainer.new()
	status_stack.add_theme_constant_override("separation", 5)
	status_card.add_child(status_stack)
	_review_label = _status_label("尚未送審｜完成設計後按上方按鈕。")
	_review_label.name = "BlueprintReviewStatus"
	_review_label.set_meta("l10n_skip", true)
	_review_label.set_meta("readability_muted", false)
	_construction_label = _status_label("目前沒有施工或送審案件。")
	_construction_label.set_meta("l10n_skip", true)
	_workers_label = _status_label("工程隊：20 / 20 人可用")
	_workers_label.set_meta("l10n_skip", true)
	status_stack.add_child(_review_label)
	status_stack.add_child(_construction_label)
	status_stack.add_child(_workers_label)
	_workers_bar = _visual_bar(20, GOOD)
	status_stack.add_child(_workers_bar)
	content.add_child(status_card)
	content.add_child(_custom_submit_button)
	content.add_child(_submit_button)

func _apply_review_state(review: Dictionary) -> void:
	if _review_label == null or _submit_button == null:
		return
	var status := str(review.get("status", "none"))
	var remaining_days := int(review.get("remaining_days", 0))
	_primary_action_mode = "submit"
	_submit_button.disabled = false
	_custom_submit_button.visible = false
	_submit_button.tooltip_text = L10n.text("送交審查；核准後即可回到地圖點空地開工。")
	_set_parameter_editability(status)
	match status:
		"under_review":
			_review_label.text = L10n.text("✓ 已收件｜審核中｜剩餘 %d 個遊戲日") % remaining_days
			_review_label.add_theme_color_override("font_color", CAUTION)
			_submit_button.text = L10n.text("審核中｜剩餘 %d 日") % remaining_days
			_submit_button.disabled = true
		"approved":
			var title := L10n.text(str(review.get("title", "核准藍圖")))
			var usage_count := int(review.get("usage_count", 0))
			if _approved_design_is_dirty(review):
				_review_label.text = L10n.text("目前草稿與已核准版不同｜請先送審這份自訂版，核准後才能開工。")
				_submit_button.text = L10n.text("送審自訂版")
				_submit_button.tooltip_text = L10n.text("草稿會改變核准藍圖的設計、價格或占地；請先送審。")
				_primary_action_mode = "submit"
			elif str(review.get("source", "")) == "default":
				_review_label.text = L10n.text("✓ 已載入「%s」｜可直接放置；調整參數後可另送審自訂版。") % title
				_submit_button.text = L10n.text("開始連續站點規劃") if _transport_station_mode else L10n.text("回到地圖放置")
				_submit_button.tooltip_text = L10n.text("在同一次規劃中連續放置多座站點，再接著鋪設路網與設定路線。") if _transport_station_mode else L10n.text("返回城市地圖，選擇空地開始施工。")
				_primary_action_mode = "placement"
				_custom_submit_button.visible = true
			else:
				_review_label.text = L10n.text("✓ 已載入「%s」｜永久保存，已套用 %d 次。") % [title, usage_count]
				_submit_button.text = L10n.text("開始連續站點規劃") if _transport_station_mode else L10n.text("回到地圖放置")
				_submit_button.tooltip_text = L10n.text("在同一次規劃中連續放置多座站點，再接著鋪設路網與設定路線。") if _transport_station_mode else L10n.text("返回城市地圖，選擇空地開始施工。")
				_primary_action_mode = "placement"
				_custom_submit_button.visible = true
			_review_label.add_theme_color_override("font_color", GOOD if _primary_action_mode == "placement" else CAUTION)
		"rejected":
			_review_label.text = L10n.text("! 審核未通過｜%s｜修改參數後可重新送審。") % L10n.text(_review_reason(str(review.get("decision_reason", ""))))
			_review_label.add_theme_color_override("font_color", CAUTION)
			_submit_button.text = L10n.text("修改後重新送審")
		"in_construction":
			_review_label.text = L10n.text("⌂ 已核准並施工中｜完工後可送審新版。")
			_review_label.add_theme_color_override("font_color", GOOD)
			_submit_button.text = L10n.text("施工中")
			_submit_button.disabled = true
		"completed":
			_review_label.text = L10n.text("✓ 上一版已完工｜目前可以送審新版。")
			_review_label.add_theme_color_override("font_color", GOOD)
			_submit_button.text = L10n.text("送審新版藍圖")
		_:
			_review_label.text = L10n.text("尚未送審｜完成設計後按上方按鈕。")
			_review_label.add_theme_color_override("font_color", _muted_color())
			_submit_button.text = L10n.text("送審藍圖")

func _sync_blueprint_from_review(review: Dictionary) -> void:
	var review_id := str(review.get("id", ""))
	var sequence := int(review.get("sequence", 0))
	var binding := "%s|%s|%d" % [_building_name, review_id, sequence]
	if binding == _last_review_binding:
		return
	_last_review_binding = binding
	var blueprint_variant = review.get("blueprint", {})
	if not blueprint_variant is Dictionary:
		return
	var blueprint: Dictionary = blueprint_variant
	if blueprint.is_empty():
		return
	_suppress_design_change = true
	_select_picker_id(_material_picker, str(blueprint.get("material_id", "")))
	_select_picker_id(_size_picker, str(blueprint.get("size_tier", "")))
	_floor_input.value = clampf(float(blueprint.get("floors", _floor_input.value)), _floor_input.min_value, _floor_input.max_value)
	_worker_input.value = clampf(float(blueprint.get("requested_workers", blueprint.get("workers", _worker_input.value))), _worker_input.min_value, _worker_input.max_value)
	_select_picker_id(_decor_picker, str(blueprint.get("decoration_id", blueprint.get("decor_id", ""))))
	_suppress_design_change = false


func active_design_state() -> Dictionary:
	var has_active := str(_active_review.get("status", "")) == "approved"
	var design_dirty := has_active and _approved_design_is_dirty(_active_review)
	return {
		"has_active_approved": has_active,
		"design_dirty": design_dirty,
		"matches_active_approved": has_active and not design_dirty,
	}


func _approved_design_is_dirty(review: Dictionary) -> bool:
	var approved_variant = review.get("blueprint", {})
	if not approved_variant is Dictionary:
		return false
	var approved: Dictionary = approved_variant
	if approved.is_empty():
		return false
	var draft := current_design_payload()
	# Roof/wall colors are persisted for compatibility but are not currently
	# player-editable in this surface.  They therefore cannot make a visible
	# design draft dirty, especially when restoring older approved blueprints.
	for field_name: String in ["material_id", "size_tier", "decor_id"]:
		var approved_field := "decoration_id" if field_name == "decor_id" else field_name
		if str(draft.get(field_name, "")) != str(approved.get(approved_field, "")):
			return true
	# JSON persistence can restore whole-number floors as 4.0 while controls
	# always expose an integer 4. Compare the semantic numeric value, not its
	# serialized spelling, or a valid historical approved design stays dirty.
	return (
		int(draft.get("floors", 0)) != int(approved.get("floors", 0))
		or int(approved.get("decoration_count", 1)) != 1
	)


func _apply_blueprint_library(entries_variant: Variant, active_id: String) -> void:
	if _library_picker == null or _library_label == null:
		return
	var choices: Array[Dictionary] = []
	if entries_variant is Array:
		for entry_variant in entries_variant:
			if not entry_variant is Dictionary:
				continue
			var entry: Dictionary = entry_variant
			var source_label := L10n.text("官方" if str(entry.get("source", "")) == "default" else "玩家")
			var usage_count := int(entry.get("usage_count", 0))
			var entry_title := L10n.text(str(entry.get("title", "核准藍圖")))
			choices.append({
				"id": str(entry.get("id", "")),
				"name": L10n.text("%s｜%s｜已用 %d 次") % [entry_title, source_label, usage_count],
				"tooltip": L10n.text("%s｜核准後永久保存，可反覆套用。") % entry_title,
			})
	var signature := JSON.stringify([choices, active_id])
	if signature == _library_signature:
		return
	_library_signature = signature
	_library_label.text = L10n.text("永久藍圖庫｜%d 份核准版本") % choices.size()
	_library_picker.disabled = choices.is_empty()
	if choices.is_empty():
		_library_picker.call("set_choices", [{"id": "none", "name": "尚無核准藍圖"}], "none")
		return
	_library_picker.set_meta("l10n_tooltips_by_id", {})
	_library_picker.call("set_choices", choices, active_id if not active_id.is_empty() else str(choices[0]["id"]))
	_sync_picker_tooltip(_library_picker, _library_picker.selected)

func _select_picker_id(picker: OptionButton, item_id: String) -> void:
	if picker == null or item_id.is_empty():
		return
	if picker.has_method("select_choice"):
		picker.call("select_choice", item_id)
		_sync_picker_tooltip(picker, picker.selected)
		return
	for index in range(picker.item_count):
		if str(picker.get_item_metadata(index)) == item_id:
			picker.select(index)
			_sync_picker_tooltip(picker, index)
			return

func _update_placement_quote(quote: Dictionary) -> void:
	if _quote_label == null:
		return
	if quote.is_empty() or not bool(quote.get("available", true)):
		_quote_label.visible = true
		_quote_label.text = L10n.text("調整任何選項後，總價、工期與占地會立即更新。")
		_quote_label.add_theme_color_override("font_color", _muted_color())
		return
	var estimate_variant = quote.get("estimate", {})
	var estimate: Dictionary = estimate_variant if estimate_variant is Dictionary else {}
	var base_cost := int(quote.get("base_cost", quote.get("non_labor_cost", 0)))
	var labor_cost := int(quote.get("total_labor_cost", quote.get("labor_cost", estimate.get("total_labor_cost", 0))))
	var total_cost := int(quote.get("total_cost", base_cost + labor_cost))
	var duration_days := int(quote.get("duration_days", quote.get("days", estimate.get("duration_days", 0))))
	var blueprint: Dictionary = quote.get("blueprint", {})
	var footprint_count := int(quote.get("footprint_count", {"small": 1, "medium": 2, "large": 3}.get(str(blueprint.get("size_tier", "")), 0)))
	_quote_label.text = L10n.text("草稿估價｜%s・%s・%d 樓・%s・%s｜占地 %d 格｜基礎／設計 $%s ＋ 人工 $%s ＝ 總額 $%s｜工期 %d 日") % [
		_selected_text(_material_picker), _selected_text(_size_picker), int(blueprint.get("floors", 0)), _selected_text(_worker_input), _selected_text(_decor_picker),
		footprint_count, _format_money(base_cost), _format_money(labor_cost), _format_money(total_cost), duration_days
	]
	_quote_label.add_theme_color_override("font_color", _text_color())
	# Keep the complete live estimate inside the first 1280x800 view. The quote
	# text already names the card, so a second title only consumed the final row.
	_quote_label.custom_minimum_size = Vector2(0, 64)
	_quote_label.visible = true

func _format_money(amount: int) -> String:
	var digits := str(absi(amount))
	var insert_at := digits.length() - 3
	while insert_at > 0:
		digits = digits.insert(insert_at, ",")
		insert_at -= 3
	return ("-" if amount < 0 else "") + digits

func _set_parameter_editability(status: String) -> void:
	var design_locked := status in ["under_review", "in_construction"]
	_material_picker.disabled = design_locked
	_size_picker.disabled = design_locked
	_floor_input.editable = not design_locked
	_decor_picker.disabled = design_locked
	_worker_input.editable = status not in ["under_review", "in_construction"]

func _on_primary_action_pressed() -> void:
	if _primary_action_mode == "placement":
		placement_requested.emit(_building_name)
		return
	_emit_blueprint()

func _on_worker_count_changed(value: float) -> void:
	worker_count_changed.emit(int(value))
	_on_design_control_changed()


func current_design_payload() -> Dictionary:
	return {
		"building_name": _building_name,
		"material_id": _selected_id(_material_picker),
		"size_tier": _selected_id(_size_picker),
		"floors": int(_floor_input.value),
		"workers": int(_worker_input.value),
		"decor_id": _selected_id(_decor_picker),
		"roof_color": "blue",
		"wall_color": "cream",
	}


func _on_design_control_changed(_unused: Variant = null) -> void:
	if _suppress_design_change:
		return
	if str(_active_review.get("status", "")) == "approved":
		_apply_review_state(_active_review)
	design_changed.emit(current_design_payload())


func _on_library_choice_selected(library_id: String) -> void:
	if library_id in ["", "none", "loading"]:
		return
	blueprint_library_selection_requested.emit(_building_name, library_id)

func _review_reason(reason: String) -> String:
	match reason:
		"insufficient_budget": return "預算不足"
		"insufficient_public_support": return "民意支持不足"
		_: return "請調整設計條件"

func _emit_blueprint() -> void:
	blueprint_submit_requested.emit(current_design_payload())

func _selected_id(picker: OptionButton) -> String:
	if picker.has_method("selected_choice_id"):
		return str(picker.call("selected_choice_id"))
	return str(picker.get_item_metadata(picker.selected))


func _selected_text(control: Control) -> String:
	if control is OptionButton:
		var option_id := _selected_id(control as OptionButton)
		match control.name:
			"BlueprintMaterial":
				return L10n.text({"wood": "木造", "brick": "磚造", "steel": "鋼構", "eco_composite": "環保複材"}.get(option_id, option_id))
			"BlueprintSize":
				return L10n.text({"small": "小型", "medium": "中型", "large": "大型"}.get(option_id, option_id))
			"BlueprintDecoration":
				return L10n.text({"flowers": "花草", "flags": "旗幟", "window_trim": "窗框"}.get(option_id, option_id))
		return option_id
	if control is SpinBox:
		return L10n.text("%d 人") % int((control as SpinBox).value)
	return ""

func _picker(items: Array[Dictionary]) -> OptionButton:
	var picker := ProgressiveOptionButtonScript.new() as OptionButton
	var tooltip_sources: Array[String] = []
	var tooltip_by_id: Dictionary = {}
	picker.custom_minimum_size = Vector2(166, UI_CONTROL_HEIGHT)
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_style_control(picker)
	picker.add_theme_font_size_override("font_size", UI_PICKER_FONT_SIZE)
	for item in items:
		tooltip_sources.append(str(item.get("tooltip", item["name"])))
		tooltip_by_id[str(item["id"])] = str(item.get("tooltip", item["name"]))
	picker.set_meta("l10n_tooltip_sources", tooltip_sources)
	picker.set_meta("l10n_tooltips_by_id", tooltip_by_id)
	picker.call("set_choices", items, str(items[0].get("id", "")) if not items.is_empty() else "")
	picker.connect("choice_selected", func(_choice_id: String) -> void: _sync_picker_tooltip(picker, picker.selected))
	_sync_picker_tooltip(picker, picker.selected)
	return picker

func _sync_picker_tooltip(picker: OptionButton, index: int) -> void:
	if picker == null or index < 0 or index >= picker.item_count:
		return
	if picker.has_method("selected_choice_id"):
		var tooltip_by_id: Dictionary = picker.get_meta("l10n_tooltips_by_id", {})
		picker.tooltip_text = L10n.text(str(tooltip_by_id.get(str(picker.call("selected_choice_id")), "")))
		return
	var sources: Array = picker.get_meta("l10n_tooltip_sources", [])
	var source := str(sources[index]) if index < sources.size() else picker.get_item_text(index)
	picker.tooltip_text = source
	L10n.localize_tree(picker)

func _icon_rect(icon_key: String, minimum_size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = UiIconCatalog.texture(icon_key)
	icon.custom_minimum_size = minimum_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _visual_card(padded_content: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.set_meta("padded_content", padded_content)
	panel.add_theme_constant_override("margin_left", 12)
	panel.add_theme_constant_override("margin_top", 10)
	panel.add_theme_constant_override("margin_right", 12)
	panel.add_theme_constant_override("margin_bottom", 10)
	_visual_cards.append(panel)
	_apply_visual_card_palette(panel)
	return panel

func _design_group_card(icon_key: String, title_text: String, detail_text: String, fields: Array) -> PanelContainer:
	var card := _visual_card(true)
	card.name = "BlueprintGroup_%s" % icon_key.capitalize()
	card.custom_minimum_size = Vector2(0, 258)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	card.add_child(stack)
	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 10)
	heading_row.add_child(_icon_rect(str(BLUEPRINT_ICON_KEYS.get(icon_key, "hero")), Vector2(56, 56)))
	var heading_copy := VBoxContainer.new()
	heading_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_copy.add_child(_title(title_text))
	heading_copy.add_child(_status_label(detail_text))
	heading_row.add_child(heading_copy)
	stack.add_child(heading_row)
	for field_variant in fields:
		if not field_variant is Dictionary:
			continue
		var field: Dictionary = field_variant
		var control := field.get("control") as Control
		if control == null:
			continue
		stack.add_child(_labeled_control(str(field.get("label", "")), control))
	return card

func _parameter_card(icon_key: String, title_text: String, control: Control) -> PanelContainer:
	var card := _visual_card()
	card.name = "BlueprintCard_%s" % icon_key
	card.custom_minimum_size = Vector2(190, 190)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 5)
	card.add_child(stack)
	stack.add_child(_icon_rect(str(BLUEPRINT_ICON_KEYS[icon_key]), Vector2(150, 92)))
	var heading := Label.new()
	heading.text = title_text
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", UI_BODY_FONT_SIZE)
	_register_label(heading)
	stack.add_child(heading)
	var control_minimum := control.custom_minimum_size
	control_minimum.x = 166
	control.custom_minimum_size = control_minimum
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(control)
	return card

func _labeled_control(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", UI_BODY_FONT_SIZE)
	_register_label(label)
	row.add_child(label)
	row.add_child(control)
	return row

func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UI_TITLE_FONT_SIZE)
	label.custom_minimum_size = Vector2(0, 40)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_register_label(label)
	return label

func _status_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", UI_BODY_FONT_SIZE)
	label.custom_minimum_size = Vector2(0, 32)
	_register_label(label, true)
	return label

func _visual_bar(max_value: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max_value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.18, 0.25, 0.32) if _dark_mode else Color(0.79, 0.86, 0.90)
	background.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", background)
	_set_visual_bar(bar, 0, color)
	return bar

func _set_visual_bar(bar: ProgressBar, value: float, color: Color) -> void:
	if bar == null:
		return
	bar.value = clampf(value, bar.min_value, bar.max_value)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)

func _action_button(text: String, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0, UI_ACTION_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_control(button)
	_action_variants[button] = primary
	_apply_action_palette(button, primary)
	return button

func _style_control(control: Control) -> void:
	if not _styled_controls.has(control):
		_styled_controls.append(control)
	control.add_theme_font_size_override("font_size", UI_BODY_FONT_SIZE)
	_apply_control_palette(control)

func _register_label(label: Label, muted: bool = false) -> void:
	if not _text_labels.has(label):
		_text_labels.append(label)
	label.set_meta("readability_muted", muted)
	label.add_theme_color_override("font_color", _muted_color() if muted else _text_color())

func _refresh_palette() -> void:
	for label in _text_labels:
		if is_instance_valid(label):
			label.add_theme_color_override("font_color", _muted_color() if bool(label.get_meta("readability_muted", false)) else _text_color())
	for control in _styled_controls:
		if is_instance_valid(control):
			_apply_control_palette(control)
	for action in _action_variants.keys():
		if is_instance_valid(action):
			_apply_action_palette(action, bool(_action_variants[action]))
	for card in _visual_cards:
		if is_instance_valid(card):
			_apply_visual_card_palette(card)
	for bar in [_workers_bar]:
		if bar != null and is_instance_valid(bar):
			var background := StyleBoxFlat.new()
			background.bg_color = Color(0.18, 0.25, 0.32) if _dark_mode else Color(0.79, 0.86, 0.90)
			background.set_corner_radius_all(6)
			bar.add_theme_stylebox_override("background", background)

func _apply_visual_card_palette(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.22, 0.29) if _dark_mode else Color(0.97, 0.94, 0.85)
	style.border_color = Color(0.36, 0.47, 0.56) if _dark_mode else Color(0.69, 0.54, 0.31)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	if bool(panel.get_meta("padded_content", false)):
		style.content_margin_left = 12
		style.content_margin_top = 10
		style.content_margin_right = 12
		style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.14)
	style.shadow_size = 3
	panel.add_theme_stylebox_override("panel", style)

func _apply_control_palette(control: Control) -> void:
	control.add_theme_color_override("font_color", _text_color())
	control.add_theme_color_override("font_hover_color", _text_color())
	control.add_theme_color_override("font_pressed_color", _text_color())
	control.add_theme_color_override("font_hover_pressed_color", _text_color())
	control.add_theme_color_override("font_focus_color", _text_color())
	control.add_theme_color_override("font_disabled_color", _muted_color())
	if control is OptionButton:
		var picker := control as OptionButton
		picker.add_theme_constant_override("modulate_arrow", 1)
		picker.add_theme_constant_override("arrow_margin", 10)
		picker.add_theme_stylebox_override("normal", _form_control_style(_form_background(), _form_border()))
		picker.add_theme_stylebox_override("hover", _form_control_style(_form_hover_background(), _form_border()))
		picker.add_theme_stylebox_override("pressed", _form_control_style(_form_pressed_background(), _form_border()))
		picker.add_theme_stylebox_override("hover_pressed", _form_control_style(_form_pressed_background(), _form_border()))
		picker.add_theme_stylebox_override("focus", _form_focus_style())
		picker.add_theme_stylebox_override("disabled", _form_control_style(_form_disabled_background(), _form_disabled_border()))
		_apply_picker_popup_palette(picker.get_popup())
	if control is SpinBox:
		var spin_box := control as SpinBox
		var line_edit := spin_box.get_line_edit()
		spin_box.add_theme_constant_override("buttons_width", 24)
		spin_box.add_theme_constant_override("field_and_buttons_separation", 4)
		spin_box.add_theme_color_override("up_icon_modulate", _text_color())
		spin_box.add_theme_color_override("up_hover_icon_modulate", _text_color())
		spin_box.add_theme_color_override("up_pressed_icon_modulate", _text_color())
		spin_box.add_theme_color_override("up_disabled_icon_modulate", _muted_color())
		spin_box.add_theme_color_override("down_icon_modulate", _text_color())
		spin_box.add_theme_color_override("down_hover_icon_modulate", _text_color())
		spin_box.add_theme_color_override("down_pressed_icon_modulate", _text_color())
		spin_box.add_theme_color_override("down_disabled_icon_modulate", _muted_color())
		spin_box.add_theme_stylebox_override("up_background", _spin_button_style(_form_background(), _form_border()))
		spin_box.add_theme_stylebox_override("up_background_hovered", _spin_button_style(_form_hover_background(), _form_border()))
		spin_box.add_theme_stylebox_override("up_background_pressed", _spin_button_style(_form_pressed_background(), _form_border()))
		spin_box.add_theme_stylebox_override("up_background_disabled", _spin_button_style(_form_disabled_background(), _form_disabled_border()))
		spin_box.add_theme_stylebox_override("down_background", _spin_button_style(_form_background(), _form_border()))
		spin_box.add_theme_stylebox_override("down_background_hovered", _spin_button_style(_form_hover_background(), _form_border()))
		spin_box.add_theme_stylebox_override("down_background_pressed", _spin_button_style(_form_pressed_background(), _form_border()))
		spin_box.add_theme_stylebox_override("down_background_disabled", _spin_button_style(_form_disabled_background(), _form_disabled_border()))
		spin_box.add_theme_stylebox_override("field_and_buttons_separator", StyleBoxEmpty.new())
		spin_box.add_theme_stylebox_override("up_down_buttons_separator", StyleBoxEmpty.new())
		line_edit.add_theme_font_size_override("font_size", UI_BODY_FONT_SIZE)
		line_edit.add_theme_color_override("font_color", _text_color())
		line_edit.add_theme_color_override("font_uneditable_color", _muted_color())
		line_edit.add_theme_color_override("caret_color", _text_color())
		line_edit.add_theme_color_override("selection_color", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.34))
		line_edit.add_theme_stylebox_override("normal", _form_control_style(_form_background(), _form_border()))
		line_edit.add_theme_stylebox_override("focus", _form_focus_style())
		line_edit.add_theme_stylebox_override("read_only", _form_control_style(_form_disabled_background(), _form_disabled_border()))

func _apply_picker_popup_palette(popup: PopupMenu) -> void:
	if popup == null:
		return
	var panel := _form_control_style(_form_background(), _form_border(), 9)
	panel.content_margin_left = 4
	panel.content_margin_top = 4
	panel.content_margin_right = 4
	panel.content_margin_bottom = 4
	popup.add_theme_stylebox_override("panel", panel)
	popup.add_theme_stylebox_override("hover", _form_control_style(_form_hover_background(), _form_border(), 6))
	popup.add_theme_color_override("font_color", _text_color())
	popup.add_theme_color_override("font_hover_color", _text_color())
	popup.add_theme_color_override("font_disabled_color", _muted_color())
	popup.add_theme_color_override("font_accelerator_color", _muted_color())
	popup.add_theme_font_size_override("font_size", UI_PICKER_FONT_SIZE)

func _form_control_style(background: Color, border: Color, radius: int = 7) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_top = 7
	style.content_margin_right = 10
	style.content_margin_bottom = 7
	return style

func _spin_button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style

func _form_focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(0.45, 0.76, 0.96) if _dark_mode else Color(0.52, 0.36, 0.17)
	style.set_border_width_all(3)
	style.set_corner_radius_all(7)
	return style

func _form_background() -> Color:
	return Color(0.10, 0.15, 0.20) if _dark_mode else Color(0.99, 0.96, 0.88)

func _form_hover_background() -> Color:
	return Color(0.16, 0.24, 0.31) if _dark_mode else Color(1.0, 0.98, 0.91)

func _form_pressed_background() -> Color:
	return Color(0.08, 0.13, 0.18) if _dark_mode else Color(0.90, 0.82, 0.67)

func _form_disabled_background() -> Color:
	return Color(0.16, 0.20, 0.24) if _dark_mode else Color(0.86, 0.86, 0.82)

func _form_border() -> Color:
	return Color(0.36, 0.47, 0.56) if _dark_mode else Color(0.58, 0.42, 0.22)

func _form_disabled_border() -> Color:
	return Color(0.42, 0.48, 0.54) if _dark_mode else Color(0.56, 0.61, 0.66)

func _apply_action_palette(button: Button, primary: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = ACCENT if primary else (Color(0.18, 0.25, 0.32) if _dark_mode else Color(0.96, 0.91, 0.80))
	normal.border_color = ACCENT_DARK if primary else (Color(0.38, 0.48, 0.56) if _dark_mode else Color(0.58, 0.42, 0.22))
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.08, 0.52, 0.82) if primary else (Color(0.23, 0.32, 0.42) if _dark_mode else Color(1.0, 0.96, 0.84))
	var pressed := normal.duplicate()
	pressed.bg_color = ACCENT_DARK if primary else (Color(0.13, 0.22, 0.31) if _dark_mode else Color(0.86, 0.75, 0.56))
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.30, 0.36, 0.42) if _dark_mode else Color(0.78, 0.82, 0.85)
	disabled.border_color = Color(0.42, 0.48, 0.54) if _dark_mode else Color(0.56, 0.61, 0.66)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color(0.67, 0.86, 1.0) if primary else (Color(0.45, 0.76, 0.96) if _dark_mode else Color(0.52, 0.36, 0.17))
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color.WHITE if primary else _text_color())
	button.add_theme_color_override("font_hover_color", Color.WHITE if primary else _text_color())
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE if primary else _text_color())
	button.add_theme_color_override("font_disabled_color", DARK_MUTED if _dark_mode else LIGHT_MUTED)

func _text_color() -> Color:
	return DARK_TEXT if _dark_mode else LIGHT_TEXT

func _muted_color() -> Color:
	return DARK_MUTED if _dark_mode else LIGHT_MUTED
