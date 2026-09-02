class_name VerticalSliceViewModelAssembler
extends RefCounted

## Pure presentation projection for the vertical-slice facade.
##
## The assembler owns no coordinator, subsystem, clock, save path, or mutable
## simulation state. Given a plain input snapshot, it returns the exact public
## view-model dictionary consumed by the application shell.

const CONSTRUCTION_OPERATION_LABELS := {
	"build": "興建工程",
	"demolish": "拆除工程",
	"move": "搬遷工程",
}
const DURABILITY_TIER_LABELS := {
	"excellent": "極佳",
	"good": "良好",
	"worn": "磨損",
	"critical": "危急",
	"scrapped": "報廢",
}
const REQUEST_STATUS_LABELS := {
	"open": "待回應",
	"pending": "待回應",
	"accepted": "已受理",
	"rejected": "已拒絕",
	"completed": "已完成",
}
const FAILURE_REASON_LABELS := {
	"imprisonment_judgment": "監禁判決",
	"grievance_above_80": "民怨超過 80",
	"municipal_trust_below_40": "市政信任低於 40",
}


static func assemble(input: Dictionary) -> Dictionary:
	var localizer = input.get("localizer")
	var core: Dictionary = input.get("core", {})
	var reviews: Dictionary = input.get("reviews", {})
	var jobs := _dictionary_array(input.get("jobs", []))
	var active_requests := _dictionary_array(input.get("active_requests", []))
	var public_affairs_requests := _dictionary_array(input.get("public_affairs_requests", active_requests))
	var npc_proxies: Dictionary = input.get("npc_proxies", {})
	var reviews_under := 0
	var reviews_approved := 0
	for review_variant: Variant in reviews.values():
		if not review_variant is Dictionary:
			continue
		var review: Dictionary = review_variant
		if str(review.get("status", "")) == "under_review":
			reviews_under += 1
		elif str(review.get("status", "")) == "approved":
			reviews_approved += 1

	var construction_text := _text(localizer, "送審 %d｜已核准 %d｜施工 %d") % [reviews_under, reviews_approved, jobs.size()]
	if reviews_approved > 0:
		construction_text += "\n" + _text(localizer, "已核准藍圖：選擇同類建築後點擊空地開工。")
	if not jobs.is_empty():
		var first_job: Dictionary = jobs[0]
		construction_text += "\n" + _text(localizer, "%s 尚需約 %d 天") % [
			_construction_operation_text(str(first_job.get("operation", "")), localizer),
			int(first_job.get("projected_remaining_days", 0)),
		]

	var selected_building: Dictionary = input.get("selected_building", {})
	var durability_records: Dictionary = input.get("durability_records", {})
	var durability_text := _text(localizer, "選取建築後可查看耐久與維修。")
	var durability_value := -1
	var can_repair := false
	var can_demolish := false
	if not selected_building.is_empty():
		var durability_variant: Variant = durability_records.get(str(selected_building.get("building_id", "")), {})
		var durability_record: Dictionary = durability_variant if durability_variant is Dictionary else {}
		durability_value = int(durability_record.get("durability", selected_building.get("durability", 100)))
		durability_text = _text(localizer, "%s｜耐久 %d｜%s") % [
			_text(localizer, str(selected_building.get("building_name", "建築"))),
			durability_value,
			_durability_tier_text(str(durability_record.get("tier", "excellent")), localizer),
		]
		can_repair = durability_value < 100 and durability_value >= 40 and str(selected_building.get("status", "active")) == "active"
		can_demolish = str(selected_building.get("status", "active")) != "demolition"

	var committee: Dictionary = input.get("committee", {})
	var judicial_committee_text := "司法委員會 %d / %d｜任期 %d 年｜審理中 %d" % [
		int(committee.get("judicial_active", 0)),
		int(committee.get("judicial_capacity", 15)),
		int(committee.get("judicial_term_years", 5)),
		int(committee.get("judicial_open_cases", 0)),
	]
	var oversight_committee_text := "監察委員會 %d / %d｜任期 %d 年｜調查中 %d" % [
		int(committee.get("oversight_active", 0)),
		int(committee.get("oversight_capacity", 10)),
		int(committee.get("oversight_term_years", 3)),
		int(committee.get("oversight_open_cases", 0)),
	]
	var governance_text := _governance_text(input, localizer)

	var citizen_requests: Array[Dictionary] = []
	for request_variant: Dictionary in public_affairs_requests:
		var request := request_variant.duplicate(true)
		var request_npc_id := str(request.get("npc_id", ""))
		var proxy_variant: Variant = npc_proxies.get(request_npc_id, {})
		var proxy: Dictionary = proxy_variant if proxy_variant is Dictionary else {}
		request["npc_name"] = _localized_proxy_name(proxy, request_npc_id, localizer)
		request["npc_archetype"] = str(proxy.get("archetype", "一般居民"))
		request["npc_model_seed"] = absi(hash(request_npc_id))
		citizen_requests.append(request)

	var selected_npc_id := str(input.get("selected_npc_id", ""))
	var selected_npc_name := ""
	if not selected_npc_id.is_empty():
		var selected_proxy_variant: Variant = npc_proxies.get(selected_npc_id, {})
		var selected_proxy: Dictionary = selected_proxy_variant if selected_proxy_variant is Dictionary else {}
		selected_npc_name = _localized_proxy_name(selected_proxy, selected_npc_id, localizer)
	var citizen_text := _citizen_text(
		selected_npc_id,
		str(input.get("selected_request_id", "")),
		public_affairs_requests,
		npc_proxies,
		localizer
	)

	var grievance := int(input.get("grievance", 0))
	var municipal_trust := int(input.get("municipal_trust", 0))
	var failure := str(input.get("failure", ""))
	var warning_text := _text(localizer, "民怨 %d（警戒 80）｜市政信任 %d（警戒 40）") % [grievance, municipal_trust]
	if not failure.is_empty():
		warning_text += "\n" + _text(localizer, "遊戲失敗：%s") % _failure_reason_text(failure, localizer)
	elif grievance >= 70 or municipal_trust <= 50:
		warning_text += "\n" + _text(localizer, "預警：請處理居民請求、恢復維護並停止濫權。")

	var latest_rejected_bill_id := str(input.get("latest_rejected_bill_id", ""))
	var selected_request_id := str(input.get("selected_request_id", ""))
	return {
		"date": core["date"],
		"treasury": int(input.get("treasury", 0)),
		"metrics": core["metrics"],
		"population": int(input.get("population", 0)),
		"available_workers": int(input.get("available_workers", 0)),
		"reviews_under": reviews_under,
		"reviews_approved": reviews_approved,
		"active_jobs": jobs.size(),
		"selected_durability": durability_value,
		"construction_text": construction_text,
		"durability_text": durability_text,
		"governance_text": governance_text,
		"judicial_committee_text": judicial_committee_text,
		"oversight_committee_text": oversight_committee_text,
		"judicial_active": int(committee.get("judicial_active", 0)),
		"judicial_capacity": int(committee.get("judicial_capacity", 15)),
		"oversight_active": int(committee.get("oversight_active", 0)),
		"oversight_capacity": int(committee.get("oversight_capacity", 10)),
		"grievance": grievance,
		"municipal_trust": municipal_trust,
		"citizen_text": citizen_text,
		"citizen_requests": citizen_requests,
		"selected_npc_name": selected_npc_name,
		"active_request_count": active_requests.size(),
		"warning_text": warning_text,
		"save_text": str(input.get("save_text", "")),
		"maintenance_enabled": bool(input.get("maintenance_enabled", true)),
		"can_force_enact": failure.is_empty() and not latest_rejected_bill_id.is_empty(),
		"can_accept_request": failure.is_empty() and _selected_request_is_open(active_requests, selected_request_id),
		"can_repair": failure.is_empty() and can_repair,
		"can_demolish": failure.is_empty() and can_demolish,
		"commands_locked": not failure.is_empty(),
		"failure_reason": failure,
		"unpaid_maintenance_months": int(input.get("unpaid_maintenance_months", 0)),
	}


static func _construction_operation_text(operation: String, localizer) -> String:
	return _text(localizer, str(CONSTRUCTION_OPERATION_LABELS.get(operation, "工程")))


static func _durability_tier_text(tier: String, localizer) -> String:
	return _text(localizer, str(DURABILITY_TIER_LABELS.get(tier, "良好")))


static func _request_status_text(status: String, localizer) -> String:
	return _text(localizer, str(REQUEST_STATUS_LABELS.get(status, "待回應")))


static func _failure_reason_text(reason: String, localizer) -> String:
	return _text(localizer, str(FAILURE_REASON_LABELS.get(reason, "狀態未知")))


static func _localized_proxy_name(proxy: Dictionary, fallback: String, localizer) -> String:
	if localizer == null:
		return str(proxy.get("display_name", fallback))
	return localizer.person_name(
		str(proxy.get("family_name", "")),
		str(proxy.get("given_name", "")),
		str(proxy.get("display_name", fallback)),
		str(proxy.get("latin_display_name", ""))
	)


static func _citizen_text(
	selected_npc_id: String,
	selected_request_id: String,
	active_requests: Array[Dictionary],
	npc_proxies: Dictionary,
	localizer
) -> String:
	if selected_npc_id.is_empty():
		return _text(localizer, "點擊地圖居民查看請求。")
	var proxy_variant: Variant = npc_proxies.get(selected_npc_id, {})
	var proxy: Dictionary = proxy_variant if proxy_variant is Dictionary else {}
	var header := _text(localizer, "%s｜%d 歲｜%s") % [
		_localized_proxy_name(proxy, selected_npc_id, localizer),
		int(proxy.get("age", 0)),
		_text(localizer, str(proxy.get("personality", "居民"))),
	]
	if selected_request_id.is_empty():
		return header + "\n" + _text(localizer, "目前沒有可接受的請求。")
	for request: Dictionary in active_requests:
		if str(request.get("request_id", "")) == selected_request_id:
			return _text(localizer, "%s\n%s：%s（%s）") % [
				header,
				_text(localizer, str(request.get("title", "居民請求"))),
				_text(localizer, str(request.get("description", ""))),
				_request_status_text(str(request.get("status", "open")), localizer),
			]
	return header + "\n" + _text(localizer, "請求已完成並寫入人物事件簿。")


static func _governance_text(input: Dictionary, localizer) -> String:
	var pending_bill: Dictionary = input.get("pending_bill", {})
	var bill_definitions: Dictionary = input.get("bill_definitions", {})
	if not pending_bill.is_empty():
		var bill_id := str(pending_bill.get("bill_id", ""))
		var bill_name := _text(localizer, str(bill_definitions.get(bill_id, {}).get("name", bill_id)))
		return _text(localizer, "%s 審核中，預計第 %d 天完成兩院表決。") % [bill_name, int(pending_bill.get("decision_day", 0))]
	var rejected_id := str(input.get("latest_rejected_bill_id", ""))
	var active_laws: Dictionary = input.get("active_laws", {})
	if not rejected_id.is_empty() and not active_laws.has(rejected_id):
		return _text(localizer, "%s遭否決；可強制執行，但會啟動後續法律與行政責任程序。") % _text(localizer, str(bill_definitions.get(rejected_id, {}).get("name", rejected_id)))
	return _text(localizer, "生效法案 %d｜目前無待審法案") % [active_laws.size()]


static func _selected_request_is_open(active_requests: Array[Dictionary], selected_request_id: String) -> bool:
	if selected_request_id.is_empty():
		return false
	for request: Dictionary in active_requests:
		if str(request.get("request_id", "")) == selected_request_id:
			return str(request.get("status", "")) == "pending"
	return false


static func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for item: Variant in value:
		if item is Dictionary:
			result.append(item)
	return result


static func _text(localizer, source: String) -> String:
	return str(localizer.text(source)) if localizer != null else source
