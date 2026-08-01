class_name MayorLocalizationService
extends Node

signal locale_changed(locale: String)

const SOURCE_LOCALE := "zh_TW"
const SETTINGS_PATH := "user://mayor_simulator/settings.cfg"
const MANUAL_OVERRIDES_PATH := "res://data/localization/manual_overrides.json"
const FEATURE_OVERRIDES_PATH := "res://data/localization/progressive_disclosure_overrides.json"
const JULY_FEATURE_OVERRIDES_PATH := "res://data/localization/feature_2026_07_31_overrides.json"
const AUGUST_GOAL_OVERRIDES_PATH := "res://data/localization/goal_2026_08_01_overrides.json"
const SUPPORTED_LOCALES := ["zh_TW", "zh_CN", "en", "ja", "ko"]
const LOCALE_NAMES := {
	"zh_TW": "繁體中文",
	"zh_CN": "简体中文",
	"en": "English",
	"ja": "日本語",
	"ko": "한국어",
}
const CATALOG_PATHS := {
	"zh_TW": "res://data/localization/zh_TW.json",
	"zh_CN": "res://data/localization/zh_CN.json",
	"en": "res://data/localization/en.json",
	"ja": "res://data/localization/ja.json",
	"ko": "res://data/localization/ko.json",
}

var current_locale := SOURCE_LOCALE
var catalogs: Dictionary = {}
var template_entries: Dictionary = {}
var replacement_entries: Dictionary = {}
var missing_sources: Dictionary = {}


func _ready() -> void:
	_load_catalogs()
	_load_preference()
	TranslationServer.set_locale(current_locale)


func locale_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for locale in SUPPORTED_LOCALES:
		options.append({"id": locale, "name": str(LOCALE_NAMES[locale])})
	return options


func set_locale(locale: String, persist: bool = true) -> bool:
	if locale not in SUPPORTED_LOCALES:
		return false
	if locale == current_locale:
		return true
	current_locale = locale
	TranslationServer.set_locale(locale)
	if persist:
		_save_preference()
	locale_changed.emit(locale)
	return true


func text(source: String) -> String:
	if source.is_empty():
		return source
	var catalog: Dictionary = catalogs.get(current_locale, {})
	if catalog.has(source):
		return _normalize_output(str(catalog[source]))
	for entry_variant in template_entries.get(current_locale, []):
		var entry: Dictionary = entry_variant
		var expression: RegEx = entry["regex"]
		var matched := expression.search(source)
		if matched == null:
			continue
		var captures: Array[String] = []
		for index in range(1, matched.get_group_count() + 1):
			var captured := matched.get_string(index)
			var localized_captured := text(captured) if captured != source else captured
			captures.append(localized_captured)
		var translated := _render_template_target(str(entry["target"]), captures)
		return _normalize_output(translated)
	var replaced := source
	var changed := false
	for entry_variant in replacement_entries.get(current_locale, []):
		var entry: Dictionary = entry_variant
		var key := str(entry["source"])
		if not replaced.contains(key):
			continue
		replaced = replaced.replace(key, str(entry["target"]))
		changed = true
	
	var final_result := replaced if changed else source
	if current_locale == "zh_CN":
		final_result = _to_simplified(final_result)
	elif current_locale != SOURCE_LOCALE and not changed and _contains_han(source):
		if catalogs.get(SOURCE_LOCALE, {}).has(source):
			missing_sources[source] = current_locale
	return _normalize_output(final_result)


func person_name(
	family_name_source: String,
	given_name_source: String,
	fallback_display_name: String,
	latin_display_name: String = ""
) -> String:
	## Personal names need a context-aware formatter.  Feeding a concatenated
	## Chinese name through the generic replacement catalog can translate a
	## surname as a common noun (for example, 黃 -> Yellow) and removes the word
	## boundary required by Latin-script output.
	var family_name := family_name_source.strip_edges()
	var given_name := given_name_source.strip_edges()
	if family_name.is_empty() or given_name.is_empty():
		return text(fallback_display_name).strip_edges()
	if current_locale == "en" and not latin_display_name.strip_edges().is_empty():
		return latin_display_name.strip_edges()
	var localized_family := text(family_name).strip_edges()
	var localized_given := text(given_name).strip_edges()
	var separator := "" if current_locale in ["zh_TW", "zh_CN", "ja"] else " "
	return "%s%s%s" % [localized_family, separator, localized_given]


func _normalize_output(value: String) -> String:
	if current_locale != "en" or value.length() < 2:
		return value
	var result := ""
	for index in value.length():
		var code := value.unicode_at(index)
		if index > 0 and code >= 0x30 and code <= 0x39:
			var previous_code := value.unicode_at(index - 1)
			var previous_is_ascii_letter := (
				(previous_code >= 0x41 and previous_code <= 0x5A)
				or (previous_code >= 0x61 and previous_code <= 0x7A)
			)
			if previous_is_ascii_letter:
				result += " "
		result += value.substr(index, 1)
	return result


func _render_template_target(target: String, captures: Array[String]) -> String:
	var rendered := target
	var used_indexed_tokens := false
	for capture_index in captures.size():
		var token := "{%d}" % capture_index
		if rendered.contains(token):
			rendered = rendered.replace(token, captures[capture_index])
			used_indexed_tokens = true
	if used_indexed_tokens:
		return rendered.replace("%%", "%")

	var result := ""
	var capture_index := 0
	var index := 0
	while index < rendered.length():
		if rendered.substr(index, 1) != "%":
			result += rendered.substr(index, 1)
			index += 1
			continue
		if index + 1 < rendered.length() and rendered.substr(index + 1, 1) == "%":
			result += "%"
			index += 2
			continue
		var cursor := index + 1
		if cursor < rendered.length() and rendered.substr(cursor, 1) == "+":
			cursor += 1
		if cursor < rendered.length() and rendered.substr(cursor, 1) == "0":
			cursor += 1
			while cursor < rendered.length() and rendered.substr(cursor, 1).is_valid_int():
				cursor += 1
		if cursor < rendered.length() and rendered.substr(cursor, 1) in ["d", "f", "s"] and capture_index < captures.size():
			result += captures[capture_index]
			capture_index += 1
			index = cursor + 1
			continue
		result += "%"
		index += 1
	return result


func _contains_han(text_val: String) -> bool:
	for index in text_val.length():
		var code := text_val.unicode_at(index)
		if code >= 0x3400 and code <= 0x9FFF:
			return true
	return false


const TRAD_TO_SIMP := {
	"體": "体", "與": "与", "為": "为", "這": "这", "會": "会", "個": "个", "來": "来", "開": "开",
	"關": "关", "學": "学", "數": "数", "據": "据", "處": "处", "實": "实", "務": "务", "點": "点",
	"選": "选", "擇": "择", "議": "议", "審": "审", "醫": "医", "療": "疗", "環": "环", "營": "营",
	"運": "运", "讀": "读", "檔": "档", "儲": "储", "滿": "满", "廠": "厂", "園": "园", "場": "场",
	"發": "发", "維": "维", "護": "护", "評": "评", "級": "级", "圖": "图", "書": "书", "館": "馆",
	"電": "电", "費": "费", "離": "离", "總": "总", "預": "预", "算": "算", "規": "规", "劃": "划",
	"設": "设", "計": "计", "藍": "蓝", "變": "变", "動": "动", "無": "无", "備": "备", "辦": "办",
	"佇": "队", "列": "列", "納": "纳", "應": "应", "陳": "陈", "情": "情", "質": "质", "詢": "询",
	"彈": "弹", "劾": "劾", "辯": "辩", "證": "证", "強": "强", "度": "度", "嚴": "严", "重": "重",
	"裁": "裁", "決": "决", "執": "执", "行": "行", "檢": "检", "視": "视", "產": "产", "業": "业",
	"億": "亿", "萬": "万", "稅": "税", "條": "条", "例": "例", "約": "约", "鐘": "钟", "剩": "剩",
	"餘": "余", "暫": "暂", "停": "停", "進": "进", "網": "网", "路": "路", "廢": "废", "棄": "弃",
	"風": "风", "險": "险", "災": "灾", "害": "害", "標": "标", "準": "准", "優": "优", "氣": "气",
	"車": "车", "轉": "转", "機": "机", "歷": "历", "史": "史", "專": "专", "區": "区", "單": "单",
	"項": "项", "缺": "缺", "口": "口", "統": "统", "復": "复", "態": "态", "現": "现", "續": "续",
	"將": "将", "寫": "写", "類": "类", "資": "资", "訊": "讯", "構": "构", "適": "适", "當": "当",
	"過": "过", "節": "节", "熱": "热", "監": "监", "察": "察", "職": "职", "權": "权", "貪": "贪",
	"污": "污", "瀆": "渎", "違": "违", "法": "法"
}

func _to_simplified(text_val: String) -> String:
	var result := text_val
	for trad in TRAD_TO_SIMP.keys():
		if result.contains(trad):
			result = result.replace(trad, TRAD_TO_SIMP[trad])
	return result


func localize_tree(root: Node) -> void:
	if root == null:
		return
	_localize_node(root)
	for child in root.get_children():
		localize_tree(child)


func clear_missing_sources() -> void:
	missing_sources.clear()


func catalog_coverage() -> Dictionary:
	var counts := {}
	for locale in SUPPORTED_LOCALES:
		counts[locale] = 0 if locale == SOURCE_LOCALE else Dictionary(catalogs.get(locale, {})).size()
	return counts


func _load_catalogs() -> void:
	catalogs.clear()
	template_entries.clear()
	replacement_entries.clear()
	var overrides := _load_manual_overrides()
	for locale in CATALOG_PATHS.keys():
		var path := str(CATALOG_PATHS[locale])
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error("Localization catalog could not be opened: %s" % path)
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if not parsed is Dictionary:
			push_error("Localization catalog is invalid: %s" % path)
			continue
		var catalog: Dictionary = parsed
		var locale_overrides: Dictionary = overrides.get(locale, {})
		for source in locale_overrides.keys():
			catalog[source] = locale_overrides[source]
		catalogs[locale] = catalog
		_build_runtime_indexes(str(locale), catalog)


func _load_manual_overrides() -> Dictionary:
	var merged := {}
	for path in [MANUAL_OVERRIDES_PATH, FEATURE_OVERRIDES_PATH, JULY_FEATURE_OVERRIDES_PATH, AUGUST_GOAL_OVERRIDES_PATH]:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if not parsed is Dictionary:
			push_error("Localization override is invalid: %s" % path)
			continue
		for locale_variant in parsed.keys():
			var locale := str(locale_variant)
			if not merged.has(locale):
				merged[locale] = {}
			for source_variant in Dictionary(parsed[locale_variant]).keys():
				merged[locale][source_variant] = parsed[locale_variant][source_variant]
	return merged


func _build_runtime_indexes(locale: String, catalog: Dictionary) -> void:
	var templates: Array[Dictionary] = []
	var replacements: Array[Dictionary] = []
	for source_variant in catalog.keys():
		var source := str(source_variant)
		var target := str(catalog[source_variant])
		var compiled: Variant = _compile_template(source)
		if compiled != null:
			templates.append({
				"source": source,
				"target": target,
				"regex": compiled,
				"specificity": _template_specificity(source),
			})
		elif not source.is_empty():
			replacements.append({"source": source, "target": target})
	templates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_specificity := int(a.get("specificity", 0))
		var b_specificity := int(b.get("specificity", 0))
		if a_specificity != b_specificity:
			return a_specificity > b_specificity
		return str(a["source"]).length() > str(b["source"]).length()
	)
	replacements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["source"]).length() > str(b["source"]).length())
	template_entries[locale] = templates
	replacement_entries[locale] = replacements


func _compile_template(source: String):
	var pattern := "^"
	var capture_count := 0
	var found_placeholder := false
	var index := 0
	while index < source.length():
		var character := source.substr(index, 1)
		if character != "%":
			pattern += _escape_regex_character(character)
			index += 1
			continue
		if index + 1 < source.length() and source.substr(index + 1, 1) == "%":
			pattern += "%"
			index += 2
			continue
		var cursor := index + 1
		if cursor < source.length() and source.substr(cursor, 1) == "+":
			cursor += 1
		if cursor < source.length() and source.substr(cursor, 1) == "0":
			cursor += 1
			while cursor < source.length() and source.substr(cursor, 1).is_valid_int():
				cursor += 1
		if cursor >= source.length():
			pattern += "%"
			index += 1
			continue
		var format_type := source.substr(cursor, 1)
		match format_type:
			"d": pattern += "([+-]?\\d+)"
			"f": pattern += "([+-]?\\d+(?:\\.\\d+)?)"
			"s": pattern += "(.+?)"
			_:
				pattern += "%"
				index += 1
				continue
		found_placeholder = true
		capture_count += 1
		index = cursor + 1
	pattern += "$"
	if not found_placeholder:
		return null
	var expression := RegEx.new()
	if expression.compile(pattern) != OK:
		push_error("Localization template failed to compile: %s" % source)
		return null
	return expression


func _template_specificity(source: String) -> int:
	var literal_count := 0
	var index := 0
	while index < source.length():
		if source.substr(index, 1) != "%":
			literal_count += 1
			index += 1
			continue
		if index + 1 < source.length() and source.substr(index + 1, 1) == "%":
			literal_count += 1
			index += 2
			continue
		var cursor := index + 1
		if cursor < source.length() and source.substr(cursor, 1) == "+":
			cursor += 1
		if cursor < source.length() and source.substr(cursor, 1) == "0":
			cursor += 1
			while cursor < source.length() and source.substr(cursor, 1).is_valid_int():
				cursor += 1
		if cursor < source.length() and source.substr(cursor, 1) in ["d", "f", "s"]:
			index = cursor + 1
			continue
		literal_count += 1
		index += 1
	return literal_count


func _escape_regex_character(character: String) -> String:
	if character in ["\\", ".", "^", "$", "|", "?", "*", "+", "(", ")", "[", "]", "{", "}"]:
		return "\\" + character
	return character


func _localize_node(node: Node) -> void:
	if bool(node.get_meta("l10n_skip", false)):
		return
	if node is Label or node is Button or node is RichTextLabel:
		_localize_string_property(node, "text")
	if node is Control:
		_localize_string_property(node, "tooltip_text")
	if node is LineEdit or node is TextEdit:
		_localize_string_property(node, "placeholder_text")
	if node is OptionButton:
		_localize_option_items(node as OptionButton)
	if node is TabContainer:
		_localize_tab_titles(node as TabContainer)


func _localize_string_property(node: Object, property_name: String) -> void:
	var current := str(node.get(property_name))
	var source_key := "l10n_source_%s" % property_name
	var last_key := "l10n_last_%s" % property_name
	if not node.has_meta(source_key):
		node.set_meta(source_key, current)
	else:
		var previous_source := str(node.get_meta(source_key))
		var previous_translation := str(node.get_meta(last_key, previous_source))
		if current != previous_source and current != previous_translation:
			node.set_meta(source_key, current)
	var source := str(node.get_meta(source_key))
	var translated := text(source)
	node.set_meta(last_key, translated)
	if current != translated:
		node.set(property_name, translated)


func _localize_option_items(option: OptionButton) -> void:
	var sources: Array = option.get_meta("l10n_option_sources", [])
	var last_values: Array = option.get_meta("l10n_option_last", [])
	if sources.size() != option.item_count:
		sources.clear()
		last_values.clear()
		for index in option.item_count:
			sources.append(option.get_item_text(index))
			last_values.append("")
	for index in option.item_count:
		var current := option.get_item_text(index)
		if current != str(last_values[index]) and current != str(sources[index]):
			sources[index] = current
		var translated := text(str(sources[index]))
		option.set_item_text(index, translated)
		last_values[index] = translated
	option.set_meta("l10n_option_sources", sources)
	option.set_meta("l10n_option_last", last_values)


func _localize_tab_titles(tabs: TabContainer) -> void:
	var sources: Array = tabs.get_meta("l10n_tab_sources", [])
	var last_values: Array = tabs.get_meta("l10n_tab_last", [])
	if sources.size() != tabs.get_tab_count():
		sources.clear()
		last_values.clear()
		for index in tabs.get_tab_count():
			sources.append(tabs.get_tab_title(index))
			last_values.append("")
	for index in tabs.get_tab_count():
		var current := tabs.get_tab_title(index)
		if current != str(last_values[index]) and current != str(sources[index]):
			sources[index] = current
		var translated := text(str(sources[index]))
		tabs.set_tab_title(index, translated)
		last_values[index] = translated
	tabs.set_meta("l10n_tab_sources", sources)
	tabs.set_meta("l10n_tab_last", last_values)


func _load_preference() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		current_locale = SOURCE_LOCALE
		return
	var saved := str(config.get_value("localization", "locale", SOURCE_LOCALE))
	current_locale = saved if saved in SUPPORTED_LOCALES else SOURCE_LOCALE


func _save_preference() -> void:
	var error := _save_preference_file(SETTINGS_PATH)
	if error != OK:
		push_error("Localization preference could not be saved: %d" % error)


func _save_preference_file(path: String) -> Error:
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("localization", "locale", current_locale)
	return config.save(path)
