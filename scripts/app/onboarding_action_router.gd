class_name OnboardingActionRouter
extends RefCounted

const SUPPORTED_TARGETS: Array[String] = [
	"build",
	"blueprint",
	"route",
	"fiscal",
	"city_data",
	"public_affairs",
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
