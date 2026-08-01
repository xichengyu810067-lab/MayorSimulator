extends SceneTree

const AssemblerScript = preload("res://scripts/app/vertical_slice_view_model_assembler.gd")

const EXPECTED_KEYS := [
	"active_jobs",
	"active_request_count",
	"available_workers",
	"can_accept_request",
	"can_demolish",
	"can_force_enact",
	"can_repair",
	"citizen_requests",
	"citizen_text",
	"commands_locked",
	"construction_text",
	"date",
	"durability_text",
	"failure_reason",
	"governance_text",
	"grievance",
	"judicial_active",
	"judicial_capacity",
	"judicial_committee_text",
	"maintenance_enabled",
	"metrics",
	"municipal_trust",
	"oversight_active",
	"oversight_capacity",
	"oversight_committee_text",
	"population",
	"reviews_approved",
	"reviews_under",
	"save_text",
	"selected_durability",
	"selected_npc_name",
	"treasury",
	"unpaid_maintenance_months",
	"warning_text",
]

var failed := false
var _l10n


func _initialize() -> void:
	_l10n = root.get_node_or_null("L10n")
	_check(_l10n != null, "L10n autoload is available")
	if _l10n == null:
		quit(1)
		return
	var request := {
		"request_id": "request_000001",
		"npc_id": "npc_000001",
		"title": "想要一座公園",
		"description": "居民希望城市多一處能散步與休息的綠地。",
		"status": "pending",
	}
	var accepted_request: Dictionary = request.duplicate(true)
	accepted_request["request_id"] = "request_000002"
	accepted_request["status"] = "accepted"
	var rejected_request: Dictionary = request.duplicate(true)
	rejected_request["request_id"] = "request_000003"
	rejected_request["status"] = "rejected"
	var completed_request: Dictionary = request.duplicate(true)
	completed_request["request_id"] = "request_000004"
	completed_request["status"] = "completed"
	var proxy := {
		"npc_id": "npc_000001",
		"display_name": "王曉明",
		"family_name": "王",
		"given_name": "曉明",
		"latin_display_name": "Xiaoming Wang",
		"age": 31,
		"personality": "務實",
		"archetype": "一般居民",
	}
	var input := {
		"localizer": _l10n,
		"core": {"date": {"year": 2, "month": 3, "day": 4}, "metrics": {"population": 300}},
		"treasury": 123_456,
		"reviews": {
			"review_1": {"status": "under_review"},
			"review_2": {"status": "approved"},
			"review_3": {"status": "rejected"},
		},
		"jobs": [{"id": "job_1", "operation": "demolish", "projected_remaining_days": 3}],
		"available_workers": 17,
		"selected_building": {"building_id": "building_1", "building_name": "住宅", "status": "active", "durability": 100},
		"durability_records": {"building_1": {"durability": 65, "tier": "worn"}},
		"committee": {
			"judicial_active": 12,
			"judicial_capacity": 15,
			"judicial_term_years": 5,
			"judicial_open_cases": 2,
			"oversight_active": 8,
			"oversight_capacity": 10,
			"oversight_term_years": 3,
			"oversight_open_cases": 1,
		},
		"pending_bill": {},
		"bill_definitions": {"environment_relief": {"name": "環境改善法"}},
		"active_laws": {},
		"latest_rejected_bill_id": "environment_relief",
		"grievance": 75,
		"municipal_trust": 49,
		"failure": "",
		"active_requests": [request, accepted_request],
		"public_affairs_requests": [request, accepted_request, rejected_request, completed_request],
		"npc_proxies": {"npc_000001": proxy},
		"selected_npc_id": "npc_000001",
		"selected_request_id": "request_000001",
		"population": 300,
		"save_text": "已儲存：第 2 年 3 月 4 日",
		"maintenance_enabled": true,
		"unpaid_maintenance_months": 2,
	}
	var input_before := JSON.stringify(input)
	var view_model: Dictionary = AssemblerScript.assemble(input)

	_check(_sorted_strings(view_model.keys()) == EXPECTED_KEYS, "public view-model key set is exact")
	_check(JSON.stringify(input) == input_before, "assembler does not mutate its input snapshot")
	_check(view_model.get("date", {}) == input["core"]["date"] and view_model.get("metrics", {}) == input["core"]["metrics"], "core date and metric dictionaries retain their values")
	_check(int(view_model.get("treasury", 0)) == 123_456 and int(view_model.get("population", 0)) == 300, "treasury and population fields retain their exact values")
	_check(int(view_model.get("reviews_under", 0)) == 1 and int(view_model.get("reviews_approved", 0)) == 1 and int(view_model.get("active_jobs", 0)) == 1, "review and active-job counters retain their definitions")
	var expected_construction: String = _l10n.text("送審 %d｜已核准 %d｜施工 %d") % [1, 1, 1]
	expected_construction += "\n" + _l10n.text("已核准藍圖：選擇同類建築後點擊空地開工。")
	expected_construction += "\n" + _l10n.text("%s 尚需約 %d 天") % [_l10n.text("拆除工程"), 3]
	_check(str(view_model.get("construction_text", "")) == expected_construction, "construction summary text and line order are exact")
	_check(str(view_model.get("durability_text", "")) == _l10n.text("%s｜耐久 %d｜%s") % [_l10n.text("住宅"), 65, _l10n.text("磨損")], "durability text retains localized labels and separators")
	_check(int(view_model.get("selected_durability", -1)) == 65, "selected durability value remains numeric")
	_check(str(view_model.get("governance_text", "")) == "環境改善法遭否決；可強制執行，但會啟動後續法律與行政責任程序。", "rejected-law governance text is exact")
	_check(str(view_model.get("judicial_committee_text", "")) == "司法委員會 12 / 15｜任期 5 年｜審理中 2", "judicial committee text is exact")
	_check(str(view_model.get("oversight_committee_text", "")) == "監察委員會 8 / 10｜任期 3 年｜調查中 1", "oversight committee text is exact")

	var localized_name: String = _l10n.person_name("王", "曉明", "王曉明", "Xiaoming Wang")
	var expected_citizen: String = _l10n.text("%s｜%d 歲｜%s") % [localized_name, 31, _l10n.text("務實")]
	expected_citizen = _l10n.text("%s\n%s：%s（%s）") % [
		expected_citizen,
		_l10n.text("想要一座公園"),
		_l10n.text("居民希望城市多一處能散步與休息的綠地。"),
		_l10n.text("待回應"),
	]
	_check(str(view_model.get("citizen_text", "")) == expected_citizen, "selected citizen request text is exact")
	_check(str(view_model.get("selected_npc_name", "")) == localized_name, "selected NPC name keeps locale-aware formatting")
	var decorated_requests: Array = view_model.get("citizen_requests", [])
	_check(decorated_requests.size() == 4 and str(decorated_requests[0].get("npc_name", "")) == localized_name, "public-affairs request history preserves terminal records and localized NPC names")
	_check(
		[str(decorated_requests[0].get("status", "")), str(decorated_requests[1].get("status", "")), str(decorated_requests[2].get("status", "")), str(decorated_requests[3].get("status", ""))]
		== ["pending", "accepted", "rejected", "completed"],
		"public-affairs request history preserves all four authoritative statuses"
	)
	_check(int(view_model.get("active_request_count", 0)) == 2, "active request count excludes rejected and completed history")
	_check(not request.has("npc_name") and not request.has("npc_model_seed"), "request decoration does not leak into the source request")
	_check(str(view_model.get("warning_text", "")).ends_with(_l10n.text("預警：請處理居民請求、恢復維護並停止濫權。")), "governance warning threshold text is exact")
	_check(bool(view_model.get("can_force_enact", false)) and bool(view_model.get("can_accept_request", false)), "open rejected law and pending request retain their command capabilities")
	_check(bool(view_model.get("can_repair", false)) and bool(view_model.get("can_demolish", false)), "selected worn active building retains repair and demolition capabilities")
	_check(not bool(view_model.get("commands_locked", true)), "healthy governance leaves commands unlocked")
	var rejected_input := input.duplicate(true)
	rejected_input["active_requests"] = []
	rejected_input["selected_request_id"] = "request_000003"
	var rejected_view: Dictionary = AssemblerScript.assemble(rejected_input)
	var expected_rejected_citizen: String = str(_l10n.text("%s\n%s：%s（%s）")) % [
		_l10n.text("%s｜%d 歲｜%s") % [localized_name, 31, _l10n.text("務實")],
		_l10n.text("想要一座公園"),
		_l10n.text("居民希望城市多一處能散步與休息的綠地。"),
		_l10n.text("已拒絕"),
	]
	_check(str(rejected_view.get("citizen_text", "")) == expected_rejected_citizen, "selected rejected request reports rejected instead of completed")
	_check(not bool(rejected_view.get("can_accept_request", true)), "rejected request cannot be accepted again")

	var failed_input := input.duplicate(true)
	failed_input["failure"] = "municipal_trust_below_40"
	var failed_view: Dictionary = AssemblerScript.assemble(failed_input)
	_check(bool(failed_view.get("commands_locked", false)), "terminal governance locks commands")
	_check(not bool(failed_view.get("can_force_enact", true)) and not bool(failed_view.get("can_accept_request", true)) and not bool(failed_view.get("can_repair", true)) and not bool(failed_view.get("can_demolish", true)), "terminal governance disables every exposed command")
	_check(str(failed_view.get("warning_text", "")).ends_with(_l10n.text("遊戲失敗：%s") % _l10n.text("市政信任低於 40")), "terminal failure reason uses the exact localized label")

	if failed:
		quit(1)
	else:
		print("Vertical-slice view-model assembler self-test passed. Keys=%d" % view_model.size())
		quit(0)


func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	result.sort()
	return result


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failed = true
	push_error("Vertical-slice view-model assembler self-test failed: %s" % label)
