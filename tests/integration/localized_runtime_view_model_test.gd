extends SceneTree

const PopulationRequestScript = preload("res://scripts/systems/population/population_request.gd")

const COORDINATOR_PATH := "res://scripts/app/vertical_slice_coordinator.gd"
const LOCALES := ["zh_TW", "zh_CN", "en", "ja", "ko"]
const TEST_SEED := 24_072_026
const TEST_FUNDS := 5_000_000
const TEST_TILE := 55
const OPERATION_LABELS := {
	"build": "興建工程",
	"demolish": "拆除工程",
	"move": "搬遷工程",
}
const DURABILITY_CASES := {
	"excellent": {"value": 100, "label": "極佳"},
	"good": {"value": 85, "label": "良好"},
	"worn": {"value": 70, "label": "磨損"},
	"critical": {"value": 45, "label": "危急"},
	"scrapped": {"value": 35, "label": "報廢"},
}
const FAILURE_CASES := {
	"imprisonment_judgment": "監禁判決",
	"grievance_above_80": "民怨超過 80",
	"municipal_trust_below_40": "市政信任低於 40",
}
const REQUEST_STATUS_LABELS := {
	"pending": "待回應",
	"accepted": "已受理",
	"rejected": "已拒絕",
	"completed": "已完成",
}

var _failed := false
var _checks := 0
var _l10n


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_l10n = root.get_node_or_null("L10n")
	_check(_l10n != null, "L10n autoload is available")
	if _l10n == null:
		quit(1)
		return
	var original_locale: String = _l10n.current_locale
	var coordinator_script := ResourceLoader.load(COORDINATOR_PATH, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
	_check(
		coordinator_script != null and coordinator_script.can_instantiate(),
		"the vertical-slice coordinator compiles and can instantiate"
	)
	if coordinator_script == null or not coordinator_script.can_instantiate():
		_l10n.set_locale(original_locale, false)
		quit(1)
		return
	var coordinator = coordinator_script.new(TEST_SEED, TEST_FUNDS)
	var registered: Dictionary = coordinator.register_existing_building(TEST_TILE, "住宅")
	_check(not registered.is_empty(), "the selected runtime building is registered")
	if registered.is_empty():
		_l10n.set_locale(original_locale, false)
		quit(1)
		return
	var building_id := str(registered.get("building_id", ""))
	var npc_ids: Array[String] = coordinator.population.sorted_npc_ids()
	_check(not npc_ids.is_empty(), "the runtime population exposes a selectable resident")
	if npc_ids.is_empty():
		_l10n.set_locale(original_locale, false)
		quit(1)
		return
	var request = _seed_active_request(coordinator, npc_ids[0])

	for locale in LOCALES:
		_check(_l10n.set_locale(locale, false), "%s locale can be selected" % locale)
		_test_active_operations(coordinator, locale)
		_test_selected_durability(coordinator, building_id, locale)
		_test_failure_reasons(coordinator, locale)
		_test_request_statuses(coordinator, request, locale)

	_l10n.set_locale(original_locale, false)
	if _failed:
		quit(1)
	else:
		print("Localized runtime view-model test passed. Checks=%d" % _checks)
		quit(0)


func _seed_active_request(coordinator, npc_id: String):
	coordinator.population.requests.clear()
	var request = PopulationRequestScript.new()
	request.request_id = "request_l10n_runtime"
	request.npc_id = npc_id
	request.request_type = "park"
	request.title = "想要一座公園"
	request.description = "居民希望城市多一處能散步與休息的綠地。"
	request.status = PopulationRequestScript.STATUS_PENDING
	request.created_day = coordinator.game_day()
	request.payload = {"target_min": 1}
	coordinator.population.requests[request.request_id] = request
	coordinator.selected_npc_id = npc_id
	coordinator.selected_request_id = request.request_id
	return request


func _test_active_operations(coordinator, locale: String) -> void:
	for operation_variant in OPERATION_LABELS.keys():
		var operation := str(operation_variant)
		coordinator.construction.jobs.clear()
		coordinator.construction.jobs["job_%s" % operation] = {
			"id": "job_%s" % operation,
			"operation": operation,
			"status": "active",
			"worker_count": 1,
			"projected_remaining_days": 2,
			"metadata": {},
		}
		var actual := str(coordinator.get_view_model().get("construction_text", ""))
		var expected_line: String = _l10n.text("%s 尚需約 %d 天") % [
			_l10n.text(str(OPERATION_LABELS[operation])),
			2,
		]
		_check(
			actual.get_slice("\n", actual.get_slice_count("\n") - 1) == expected_line,
			"%s %s job uses the exact localized operation label: expected='%s' actual='%s'" % [locale, operation, expected_line, actual]
		)
		_check(
			not _contains_standalone_token(actual, operation),
			"%s %s job does not expose its internal operation ID: %s" % [locale, operation, actual]
		)
	coordinator.construction.jobs.clear()


func _test_selected_durability(coordinator, building_id: String, locale: String) -> void:
	for tier_variant in DURABILITY_CASES.keys():
		var tier := str(tier_variant)
		var durability_case: Dictionary = DURABILITY_CASES[tier]
		var durability_value := int(durability_case["value"])
		var durability_record: Dictionary = coordinator.durability.buildings[building_id]
		durability_record["durability"] = durability_value
		durability_record["tier"] = tier
		durability_record["status"] = "scrapped" if tier == "scrapped" else "active"
		coordinator.durability.buildings[building_id] = durability_record
		var actual := str(coordinator.get_view_model(TEST_TILE).get("durability_text", ""))
		var expected: String = _l10n.text("%s｜耐久 %d｜%s") % [
			_l10n.text("住宅"),
			durability_value,
			_l10n.text(str(durability_case["label"])),
		]
		_check(
			actual == expected,
			"%s %s durability tier is exact: expected='%s' actual='%s'" % [locale, tier, expected, actual]
		)
		_check(
			not _contains_standalone_token(actual, tier),
			"%s %s durability does not expose its internal tier ID: %s" % [locale, tier, actual]
		)


func _test_failure_reasons(coordinator, locale: String) -> void:
	for reason_variant in FAILURE_CASES.keys():
		var reason := str(reason_variant)
		coordinator.governance.imprisonment_judgment = reason == "imprisonment_judgment"
		coordinator.governance.grievance = 81 if reason == "grievance_above_80" else 50
		coordinator.governance.municipal_trust = 39 if reason == "municipal_trust_below_40" else 60
		var actual := str(coordinator.get_view_model().get("warning_text", ""))
		var expected_line: String = _l10n.text("遊戲失敗：%s") % _l10n.text(str(FAILURE_CASES[reason]))
		_check(
			actual.get_slice("\n", actual.get_slice_count("\n") - 1) == expected_line,
			"%s %s failure uses the exact localized player label: expected='%s' actual='%s'" % [locale, reason, expected_line, actual]
		)
		_check(
			not actual.contains(reason),
			"%s failure does not expose internal reason ID %s: %s" % [locale, reason, actual]
		)
	coordinator.governance.imprisonment_judgment = false
	coordinator.governance.grievance = 50
	coordinator.governance.municipal_trust = 60


func _test_request_statuses(coordinator, request, locale: String) -> void:
	var proxy: Dictionary = coordinator.population.materialize_proxy(request.npc_id)
	var expected_header: String = _l10n.text("%s｜%d 歲｜%s") % [
		_l10n.person_name(
			str(proxy.get("family_name", "")),
			str(proxy.get("given_name", "")),
			str(proxy.get("display_name", request.npc_id)),
			str(proxy.get("latin_display_name", ""))
		),
		int(proxy.get("age", 0)),
		_l10n.text(str(proxy.get("personality", "居民"))),
	]
	for status_variant in REQUEST_STATUS_LABELS.keys():
		var status := str(status_variant)
		request.status = status
		coordinator.population.requests[request.request_id] = request
		var actual := str(coordinator.get_view_model().get("citizen_text", ""))
		var expected: String = _l10n.text("%s\n%s：%s（%s）") % [
			expected_header,
			_l10n.text(request.title),
			_l10n.text(request.description),
			_l10n.text(str(REQUEST_STATUS_LABELS[status])),
		]
		_check(
			actual == expected,
			"%s %s request status is exact: expected='%s' actual='%s'" % [locale, status, expected, actual]
		)
		_check(
			not _contains_standalone_token(actual, status),
			"%s request does not expose internal status ID %s: %s" % [locale, status, actual]
		)
	request.status = PopulationRequestScript.STATUS_PENDING
	coordinator.population.requests[request.request_id] = request


func _contains_standalone_token(value: String, token: String) -> bool:
	var expression := RegEx.new()
	if expression.compile("(^|[^A-Za-z_])%s([^A-Za-z_]|$)" % token) != OK:
		return value.contains(token)
	return expression.search(value) != null


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("Localized runtime view-model check failed: %s" % message)
