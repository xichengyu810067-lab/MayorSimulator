class_name OnboardingActionRouter
extends RefCounted

const SUPPORTED_TARGETS: Array[String] = [
	"build",
	"blueprint",
	"route",
	"fiscal",
	"city_data",
	"public_affairs",
	"governance",
	"judicial",
	"oversight",
]
const BLUEPRINT_FIELDS: Array[String] = [
	"material_id",
	"size_tier",
	"floors",
	"workers",
	"decor_id",
]

var _progress
var _blueprint_baseline: Dictionary = {}
var _blueprint_changed := false
var _city_data_initial_tab := -1


func _init(progress = null) -> void:
	_progress = progress


func bind_progress(progress) -> void:
	_progress = progress
	reset_transient_evidence()


func reset_transient_evidence() -> void:
	_blueprint_baseline.clear()
	_blueprint_changed = false
	_city_data_initial_tab = -1


func begin_blueprint_design(payload: Dictionary) -> bool:
	if not _is_current("blueprint"):
		return false
	var normalized := _normalized_blueprint(payload)
	if normalized.is_empty():
		return false
	if _blueprint_baseline.is_empty():
		_blueprint_baseline = normalized
		_blueprint_changed = false
	return true


func note_blueprint_design(payload: Dictionary) -> bool:
	if not _is_current("blueprint") or _blueprint_baseline.is_empty():
		return false
	var normalized := _normalized_blueprint(payload)
	if normalized.is_empty() or str(normalized.get("building_name", "")) != str(_blueprint_baseline.get("building_name", "")):
		return false
	for field_name in BLUEPRINT_FIELDS:
		if normalized.get(field_name) != _blueprint_baseline.get(field_name):
			_blueprint_changed = true
			return true
	return false


func blueprint_design_changed() -> bool:
	return _blueprint_changed


func record_build_success(building_name: String, is_transport_station: bool, result: Dictionary, game_day: int) -> bool:
	if is_transport_station or building_name.is_empty() or not bool(result.get("ok", false)):
		return false
	var job := _dictionary(result.get("job", {}))
	return _commit("build", "construction_job", str(job.get("id", "")), game_day)


func record_blueprint_success(payload: Dictionary, result: Dictionary, game_day: int) -> bool:
	if not _is_current("blueprint") or not _blueprint_changed or not bool(result.get("ok", false)):
		return false
	var normalized := _normalized_blueprint(payload)
	if normalized.is_empty() or str(normalized.get("building_name", "")) != str(_blueprint_baseline.get("building_name", "")):
		return false
	var review := _dictionary(result.get("review", {}))
	return _commit("blueprint", "blueprint_review", str(review.get("id", "")), game_day)


func record_route_package_success(result: Dictionary, game_day: int) -> bool:
	if not bool(result.get("ok", false)):
		return false
	var session := _dictionary(result.get("session", {}))
	if str(session.get("workflow", "")) != "route_package_v1":
		return false
	return _commit("route", "transport_session", str(session.get("id", "")), game_day)


func record_fiscal_apply_success(
	preview_revision: int,
	draft_revision: int,
	changed_count: int,
	apply_generation: int,
	game_day: int
) -> bool:
	if changed_count <= 0 or preview_revision < 0 or preview_revision != draft_revision or apply_generation <= 0:
		return false
	return _commit(
		"fiscal",
		"fiscal_draft",
		"fiscal_apply_%06d" % apply_generation,
		game_day
	)


func note_city_data_opened(tab_index: int, tab_count: int) -> bool:
	if not _is_current("city_data") or tab_count < 2 or tab_index < 0 or tab_index >= tab_count:
		return false
	_city_data_initial_tab = tab_index
	return true


func record_city_data_tab_changed(tab_index: int, tab_count: int, game_day: int) -> bool:
	if not _is_current("city_data") or _city_data_initial_tab < 0:
		return false
	if tab_count < 2 or tab_index < 0 or tab_index >= tab_count or tab_index == _city_data_initial_tab:
		return false
	return _commit("city_data", "city_data_dashboard", "tab_%d" % tab_index, game_day)


func record_public_request_accept_success(before: Dictionary, after: Dictionary, game_day: int) -> bool:
	if str(before.get("status", "")) != "pending" or str(after.get("status", "")) != "accepted":
		return false
	var request_id := str(before.get("request_id", ""))
	if request_id.is_empty() or request_id != str(after.get("request_id", "")):
		return false
	return _commit("public_affairs", "resident_request", request_id, game_day)


func record_governance_force_success(
	result: Dictionary,
	governance,
	event_book: Array,
	checks_history: Array,
	game_day: int
) -> bool:
	if not _is_current("governance") or not bool(result.get("ok", false)) or governance == null:
		return false
	var law := _dictionary(result.get("law", {}))
	var judicial_case := _dictionary(result.get("case", {}))
	var oversight_case := _dictionary(result.get("oversight_case", {}))
	var event := _dictionary(result.get("event", {}))
	var bill_id := str(law.get("bill_id", ""))
	var judicial_id := str(judicial_case.get("id", ""))
	var oversight_id := str(oversight_case.get("id", ""))
	if bill_id.is_empty() or judicial_id.is_empty() or oversight_id.is_empty():
		return false
	if not bool(law.get("forced", false)) or str(law.get("status", "")) != "active":
		return false
	if (
		str(judicial_case.get("bill_id", "")) != bill_id
		or int(judicial_case.get("opened_day", -1)) != game_day
		or str(judicial_case.get("status", "")) != "investigating"
	):
		return false
	if (
		str(oversight_case.get("target_official_id", "")) != "official_mayor"
		or int(oversight_case.get("opened_day", -1)) != game_day
		or str(oversight_case.get("status", "")) != "investigating"
	):
		return false
	var allegations: Array = oversight_case.get("allegations", [])
	if not allegations.has("違法強制施行法案") or not allegations.has("未遵守議會否決決議"):
		return false
	if (
		str(event.get("type", "")) != "bill_force_enacted"
		or str(event.get("subject_id", "")) != bill_id
		or int(event.get("game_day", -1)) != game_day
		or str(event.get("reason_tag", "")) != "governance.force_enactment"
	):
		return false
	var event_payload := _dictionary(event.get("payload", {}))
	if str(event_payload.get("case_id", "")) != judicial_id or str(event_payload.get("oversight_case_id", "")) != oversight_id:
		return false
	if not _governance_result_matches_authority(governance, law, judicial_case, oversight_case):
		return false
	if _matching_force_fact_count(event_book, judicial_id, oversight_id) != 1:
		return false
	if _matching_force_check_count(checks_history, bill_id, game_day) != 1:
		return false
	return _commit("governance", "bill_force_enactment", judicial_id, game_day)


func record_judicial_defense_success(
	case_id: String,
	defense_id: String,
	result: Dictionary,
	governance,
	event_book: Array,
	game_day: int
) -> bool:
	if not _is_current("judicial") or governance == null:
		return false
	var force_receipt := _receipt_for_kind("governance")
	if str(force_receipt.get("authority_id", "")) != "bill_force_enactment" or str(force_receipt.get("entity_id", "")) != case_id:
		return false
	if _linked_oversight_case_id(event_book, case_id).is_empty():
		return false
	if not _defense_result_matches_authority(result, governance.judiciary_cases, case_id, defense_id):
		return false
	return _commit("judicial", "judicial_case", case_id, game_day)


func record_oversight_defense_success(
	case_id: String,
	defense_id: String,
	result: Dictionary,
	governance,
	event_book: Array,
	game_day: int
) -> bool:
	if not _is_current("oversight") or governance == null:
		return false
	var force_receipt := _receipt_for_kind("governance")
	var judicial_receipt := _receipt_for_kind("judicial")
	var judicial_id := str(force_receipt.get("entity_id", ""))
	if (
		str(force_receipt.get("authority_id", "")) != "bill_force_enactment"
		or str(judicial_receipt.get("authority_id", "")) != "judicial_case"
		or str(judicial_receipt.get("entity_id", "")) != judicial_id
	):
		return false
	if _linked_oversight_case_id(event_book, judicial_id) != case_id:
		return false
	if not _defense_result_matches_authority(result, governance.oversight_cases, case_id, defense_id):
		return false
	return _commit("oversight", "oversight_case", case_id, game_day)


func linked_case_id(mode: String, event_book: Array) -> String:
	var force_receipt := _receipt_for_kind("governance")
	if str(force_receipt.get("authority_id", "")) != "bill_force_enactment":
		return ""
	var judicial_id := str(force_receipt.get("entity_id", ""))
	if _linked_oversight_case_id(event_book, judicial_id).is_empty():
		return ""
	if mode == "judicial":
		return judicial_id
	if mode == "oversight":
		return _linked_oversight_case_id(event_book, judicial_id)
	return ""


func supports_current_target() -> bool:
	return _current_target() in SUPPORTED_TARGETS


func debug_snapshot() -> Dictionary:
	return {
		"current_target": _current_target(),
		"supported": supports_current_target(),
		"blueprint_baseline": _blueprint_baseline.duplicate(true),
		"blueprint_changed": _blueprint_changed,
		"city_data_initial_tab": _city_data_initial_tab,
	}


func _commit(target_id: String, authority_id: String, entity_id: String, game_day: int) -> bool:
	if target_id not in SUPPORTED_TARGETS or not _is_current(target_id) or entity_id.is_empty():
		return false
	var receipt := {
		"kind": target_id,
		"authority_id": authority_id,
		"entity_id": entity_id,
		"game_day": game_day,
	}
	if not bool(_progress.call("record_current_target", target_id, receipt)):
		return false
	reset_transient_evidence()
	return true


func _receipt_for_kind(kind: String) -> Dictionary:
	if _progress == null or not _progress.has_method("receipts"):
		return {}
	var matches: Array[Dictionary] = []
	for receipt_variant: Variant in _progress.call("receipts"):
		if receipt_variant is Dictionary and str(Dictionary(receipt_variant).get("kind", "")) == kind:
			matches.append(Dictionary(receipt_variant))
	return matches[0].duplicate(true) if matches.size() == 1 else {}


func _governance_result_matches_authority(
	governance,
	law: Dictionary,
	judicial_case: Dictionary,
	oversight_case: Dictionary
) -> bool:
	var bill_id := str(law.get("bill_id", ""))
	var judicial_id := str(judicial_case.get("id", ""))
	var oversight_id := str(oversight_case.get("id", ""))
	return (
		governance.active_laws.has(bill_id)
		and _dictionary(governance.active_laws.get(bill_id, {})) == law
		and governance.judiciary_cases.has(judicial_id)
		and _dictionary(governance.judiciary_cases.get(judicial_id, {})) == judicial_case
		and governance.oversight_cases.has(oversight_id)
		and _dictionary(governance.oversight_cases.get(oversight_id, {})) == oversight_case
	)


func _defense_result_matches_authority(
	result: Dictionary,
	cases: Dictionary,
	case_id: String,
	defense_id: String
) -> bool:
	if case_id.is_empty() or defense_id.is_empty() or not bool(result.get("ok", false)):
		return false
	var returned_case := _dictionary(result.get("case", {}))
	return (
		str(returned_case.get("id", "")) == case_id
		and str(returned_case.get("status", "")) == "investigating"
		and str(returned_case.get("defense_template_id", "")) == defense_id
		and cases.has(case_id)
		and _dictionary(cases.get(case_id, {})) == returned_case
	)


func _matching_force_fact_count(event_book: Array, judicial_id: String, oversight_id: String) -> int:
	var count := 0
	for record_variant: Variant in event_book:
		if not (record_variant is Dictionary):
			continue
		var record := record_variant as Dictionary
		if (
			str(record.get("fact_type", "")) == "bill_force_enacted"
			and str(record.get("case_id", "")) == judicial_id
			and str(record.get("oversight_case_id", "")) == oversight_id
		):
			count += 1
	return count


func _matching_force_check_count(checks_history: Array, bill_id: String, game_day: int) -> int:
	var count := 0
	for check_variant: Variant in checks_history:
		if not (check_variant is Dictionary):
			continue
		var check := check_variant as Dictionary
		if (
			str(check.get("action", "")) == "executive_override_checked"
			and str(check.get("subject_id", "")) == bill_id
			and int(check.get("game_day", -1)) == game_day
		):
			count += 1
	return count


func _linked_oversight_case_id(event_book: Array, judicial_id: String) -> String:
	if judicial_id.is_empty():
		return ""
	var matches: Array[String] = []
	var fact_count := 0
	for record_variant: Variant in event_book:
		if not (record_variant is Dictionary):
			continue
		var record := record_variant as Dictionary
		if str(record.get("fact_type", "")) != "bill_force_enacted" or str(record.get("case_id", "")) != judicial_id:
			continue
		fact_count += 1
		var oversight_id := str(record.get("oversight_case_id", ""))
		if not oversight_id.is_empty():
			matches.append(oversight_id)
	return matches[0] if fact_count == 1 and matches.size() == 1 else ""


func _is_current(target_id: String) -> bool:
	return (
		_progress != null
		and _progress.has_method("is_active")
		and bool(_progress.call("is_active"))
		and _current_target() == target_id
	)


func _current_target() -> String:
	if _progress == null or not _progress.has_method("current_target"):
		return ""
	return str(_progress.call("current_target"))


func _normalized_blueprint(payload: Dictionary) -> Dictionary:
	var building_name := str(payload.get("building_name", ""))
	if building_name.is_empty():
		return {}
	var result := {"building_name": building_name}
	for field_name in BLUEPRINT_FIELDS:
		if not payload.has(field_name):
			return {}
		result[field_name] = int(payload[field_name]) if field_name in ["floors", "workers"] else str(payload[field_name])
	return result


func _dictionary(value: Variant) -> Dictionary:
	return Dictionary(value) if value is Dictionary else {}
