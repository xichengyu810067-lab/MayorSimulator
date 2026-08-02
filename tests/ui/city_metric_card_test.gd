extends SceneTree

const CityMetricCardScript = preload("res://ui/components/city_metric_card.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var component_resource := load("res://ui/components/city_metric_card.gd") as Script
	_check(component_resource != null and component_resource.can_instantiate(), "city metric card script compiles and can instantiate")
	if _failed:
		quit(1)
		return
	await _validate_summary_contract()
	await _validate_service_icon_contract()
	await _validate_status_encoding()
	for resolution in [Vector2i(1920, 1080), Vector2i(2880, 1800)]:
		for dark_mode in [false, true]:
			await _validate_two_column_layout(resolution, dark_mode)

	if _failed:
		quit(1)
	else:
		print("City metric card test passed. Resolutions=1920x1080,2880x1800 Themes=light,dark Delta=authoritative-only Animation=baseline-to-target")
		quit(0)


func _validate_summary_contract() -> void:
	var card = CityMetricCardScript.new()
	root.add_child(card)
	await _settle()

	card.set_metric_from_month_summary({
		"id": "population",
		"icon_key": "population",
		"label": "城市人口",
		"unit": "人",
		"status": "good",
		"interpretation": "就業與住宅容量足以支撐目前人口。",
		"action_hint": "預留住宅與公共服務容量。",
	}, 328, {
		"available": false,
		"population_change": 999,
	}, "population_change")
	_check(card.value_label.text == "328", "current value is injected without rewriting it")
	_check(card.unit_label.text == "人", "current value keeps its explicit unit")
	_check(not card.has_authoritative_delta(), "unavailable month summary never becomes a trend")
	_check(card.delta_label.text.contains("資料不足"), "unavailable month summary states that evidence is missing")
	_check(not card.delta_label.text.contains("999"), "stale/default summary payload is not presented when unavailable")
	_check(not card.delta_label.text.contains("▲") and not card.delta_label.text.contains("▼"), "unavailable delta has no direction arrow")

	card.set_metric_from_month_summary({
		"id": "population",
		"icon_key": "population",
		"label": "城市人口",
		"unit": "人",
		"status": "good",
		"interpretation": "本月人口溫和成長。",
		"action_hint": "持續補足住宅與學校容量。",
	}, 348, {
		"available": true,
		"population_change": 20,
	}, "population_change")
	_check(card.has_authoritative_delta(), "available structured summary exposes its real delta")
	_check(card.delta_label.text.contains("▲ +20 人"), "positive authoritative delta includes direction, sign, amount, and unit")
	_check(card.interpretation_label.text.begins_with("解讀："), "interpretation is visibly labelled")
	_check(card.action_hint_label.text.begins_with("建議："), "improvement action is visibly labelled")
	card.benchmark_chart.set_chart({
		"minimum": 0.0,
		"maximum": 100.0,
		"baseline": 60.0,
		"current": 88.0,
		"current_text": "學生家庭 88%",
		"difference_text": "高於安全線 +28 個百分點",
		"baseline_text": "安全線 60%",
		"duration": 0.82,
	}, true)
	_check(bool(card.benchmark_chart.get_meta("animation_active", false)), "benchmark animation visibly starts from the safety line")
	_check(is_equal_approx(card.benchmark_chart.displayed_value(), 60.0), "benchmark animation begins at the explicit safety line")
	var observed_intermediate := false
	var observation_deadline := Time.get_ticks_msec() + 650
	while Time.get_ticks_msec() < observation_deadline and bool(card.benchmark_chart.get_meta("animation_active", false)):
		await process_frame
		var displayed_value: float = float(card.benchmark_chart.displayed_value())
		if displayed_value > 60.0 and displayed_value < 88.0:
			observed_intermediate = true
			break
	_check(observed_intermediate, "benchmark chart moves through an observable intermediate value")
	var completion_deadline := Time.get_ticks_msec() + 1200
	while Time.get_ticks_msec() < completion_deadline and bool(card.benchmark_chart.get_meta("animation_active", false)):
		await process_frame
	_check(not bool(card.benchmark_chart.get_meta("animation_active", false)), "benchmark animation completes within its bounded duration")
	_check(is_equal_approx(card.benchmark_chart.displayed_value(), 88.0), "benchmark chart settles on the authoritative target")
	_check(card.icon_view.texture != null, "semantic icon is loaded")
	if card.icon_view.texture != null:
		_check(str(card.icon_view.texture.resource_path).contains("/storybook_v2/population.png"), "component uses the active semantic icon catalog")
	card.queue_free()
	await _settle()


func _validate_service_icon_contract() -> void:
	var expected_paths := {
		"security": "/storybook_v2/building_civic.png",
		"environment": "/storybook_v2/environment.png",
		"traffic": "/storybook_v2/building_mobility.png",
		"education": "/storybook_v2/education.png",
		"healthcare": "/storybook_v2/healthcare.png",
	}
	var card = CityMetricCardScript.new()
	root.add_child(card)
	for metric_id in expected_paths:
		card.set_metric({
			"id": metric_id,
			"icon_key": metric_id,
			"label": metric_id,
			"value": 70,
			"unit": "/ 100",
			"status": "good",
			"delta_available": false,
			"interpretation": "服務指標圖示契約。",
			"action_hint": "維持服務品質。",
		})
		_check(card.icon_view.texture != null, "%s service icon loads" % metric_id)
		_check(is_equal_approx(card.benchmark_chart.baseline_value(), 60.0), "%s chart uses the shared 60%% safety line" % metric_id)
		_check(is_equal_approx(card.benchmark_chart.target_value(), 70.0), "%s chart targets the authoritative current value" % metric_id)
		_check(is_equal_approx(card.benchmark_chart.difference_value(), 10.0), "%s chart exposes the ten-point safety gap" % metric_id)
		_check(not card.benchmark_chart.difference_label.text.strip_edges().is_empty(), "%s chart always explains its baseline difference" % metric_id)
		if card.icon_view.texture != null:
			_check(
				str(card.icon_view.texture.resource_path).ends_with(str(expected_paths[metric_id])),
				"%s service icon resolves to its intended Storybook V2 asset" % metric_id
			)
	card.queue_free()
	await _settle()


func _validate_status_encoding() -> void:
	var symbols := {}
	for status in ["good", "attention", "critical", "neutral"]:
		var card = CityMetricCardScript.new()
		root.add_child(card)
		card.set_metric({
			"icon_key": "city_data",
			"label": "測試指標",
			"value": 70,
			"unit": "/ 100",
			"status": status,
			"delta_available": false,
			"interpretation": "狀態以符號、文字與顏色共同表達。",
			"action_hint": "依狀態採取對應措施。",
		})
		await _settle()
		var status_text: String = card.status_label.text
		var symbol := status_text.left(1)
		symbols[symbol] = true
		_check(status_text.length() >= 3, "%s status includes a symbol and visible word" % status)
		_check(not status_text.strip_edges().is_empty(), "%s status is never color-only" % status)
		for dark_mode in [false, true]:
			card.set_dark_mode(dark_mode)
			var chip_style := card._status_chip.get_theme_stylebox("panel") as StyleBoxFlat
			var foreground: Color = card.status_label.get_theme_color("font_color")
			_check(chip_style != null, "%s status has a chip background" % status)
			if chip_style != null:
				_check(_contrast_ratio(foreground, chip_style.bg_color) >= 4.5, "%s status text reaches 4.5:1 contrast in %s mode" % [status, "dark" if dark_mode else "light"])
		card.queue_free()
		await _settle()
	_check(symbols.size() == 4, "all status classes use different non-color symbols")


func _validate_two_column_layout(resolution: Vector2i, dark_mode: bool) -> void:
	root.content_scale_size = resolution
	root.size = resolution
	var screen := Control.new()
	screen.name = "MetricCardLayout_%dx%d_%s" % [resolution.x, resolution.y, "dark" if dark_mode else "light"]
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)

	var background := ColorRect.new()
	background.color = Color("10202a") if dark_mode else Color("f4ead2")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_bottom", 60)
	screen.add_child(margin)

	var grid := GridContainer.new()
	grid.name = "MetricGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	margin.add_child(grid)

	var fixtures: Array[Dictionary] = [
		{
			"id": "funds", "icon_key": "funds", "label": "城市公庫", "value_text": "$250,000", "unit": "城市幣",
			"status": "good", "delta_available": true, "delta": 1998, "delta_unit": "城市幣",
			"interpretation": "預估淨額足以覆蓋本月支出與安全緩衝。", "action_hint": "保留至少一個月的市政支出。",
		},
		{
			"id": "population", "icon_key": "population", "label": "城市人口", "value": 328, "unit": "人",
			"status": "attention", "delta_available": true, "delta": 28,
			"interpretation": "人口成長快於目前醫療服務容量。", "action_hint": "檢查醫院服務範圍並預留擴建用地。",
		},
		{
			"id": "satisfaction", "icon_key": "satisfaction", "label": "居民滿意度", "value": 42, "unit": "/ 100",
			"status": "critical", "delta_available": true, "delta": -6, "delta_unit": "點",
			"interpretation": "醫療與交通同時低於安全門檻。", "action_hint": "先處理影響人口最多的交通瓶頸。",
		},
		{
			"id": "trust", "icon_key": "trust", "label": "市政信任", "value": 70, "unit": "/ 100",
			"status": "neutral", "delta_available": false,
			"interpretation": "尚未完成首次月結，沒有可比較期間。", "action_hint": "等待月結後再判讀變化，避免猜測趨勢。",
		},
	]

	var cards: Array[Control] = []
	for fixture in fixtures:
		var card = CityMetricCardScript.new()
		card.set_dark_mode(dark_mode)
		card.set_metric(fixture)
		grid.add_child(card)
		cards.append(card)
	await _settle(4)

	_check(grid.columns == 2, "%dx%d uses an explicit two-column metric grid" % [resolution.x, resolution.y])
	var screen_rect := Rect2(Vector2.ZERO, Vector2(resolution))
	for card in cards:
		var rect := card.get_global_rect()
		_check(rect.size.x >= CityMetricCardScript.MINIMUM_CARD_SIZE.x, "%dx%d card width preserves the readable minimum" % [resolution.x, resolution.y])
		_check(rect.size.y >= CityMetricCardScript.MINIMUM_CARD_SIZE.y, "%dx%d card height preserves the readable minimum" % [resolution.x, resolution.y])
		_check(screen_rect.encloses(rect), "%dx%d card stays within the viewport" % [resolution.x, resolution.y])
		_validate_card_text_geometry(card, resolution, dark_mode)

	screen.queue_free()
	await _settle()


func _validate_card_text_geometry(card, resolution: Vector2i, dark_mode: bool) -> void:
	var card_rect: Rect2 = card.get_global_rect()
	for label in [card.metric_name_label, card.value_label, card.unit_label, card.delta_label, card.status_label, card.interpretation_label, card.action_hint_label, card.benchmark_chart.current_label, card.benchmark_chart.difference_label, card.benchmark_chart.minimum_label, card.benchmark_chart.baseline_label, card.benchmark_chart.maximum_label]:
		if not label.visible:
			continue
		_check(label.get_theme_font_size("font_size") >= 16, "%dx%d %s label stays at least 16px" % [resolution.x, resolution.y, label.name])
		_check(card_rect.encloses(label.get_global_rect()), "%dx%d %s label remains inside its card" % [resolution.x, resolution.y, label.name])
	_check(card.interpretation_label.max_lines_visible == 2, "interpretation is capped at two readable lines")
	_check(card.action_hint_label.max_lines_visible == 1, "chart-first card caps its secondary action hint at one line")
	var card_style := card.get_theme_stylebox("panel") as StyleBoxFlat
	var foreground: Color = card.metric_name_label.get_theme_color("font_color")
	_check(card_style != null, "card palette has an explicit background")
	if card_style != null:
		_check(_contrast_ratio(foreground, card_style.bg_color) >= 4.5, "%dx%d main text reaches 4.5:1 contrast in %s mode" % [resolution.x, resolution.y, "dark" if dark_mode else "light"])


func _settle(frames: int = 2) -> void:
	for _frame in frames:
		await process_frame


func _contrast_ratio(first: Color, second: Color) -> float:
	var first_luminance := _relative_luminance(first)
	var second_luminance := _relative_luminance(second)
	return (maxf(first_luminance, second_luminance) + 0.05) / (minf(first_luminance, second_luminance) + 0.05)


func _relative_luminance(color: Color) -> float:
	return 0.2126 * _linear_channel(color.r) + 0.7152 * _linear_channel(color.g) + 0.0722 * _linear_channel(color.b)


func _linear_channel(value: float) -> float:
	if value <= 0.04045:
		return value / 12.92
	return pow((value + 0.055) / 1.055, 2.4)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("City metric card check failed: %s" % message)
