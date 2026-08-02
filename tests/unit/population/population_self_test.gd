extends SceneTree

const PopulationSystem = preload("res://scripts/systems/population/population_system.gd")
const PopulationRequest = preload("res://scripts/systems/population/population_request.gd")
const NpcRecord = preload("res://scripts/systems/population/npc_record.gd")

var failed := false


func _init() -> void:
	var first = PopulationSystem.new()
	first.initialize(300, 42_4242)
	_assert(first.population_count() == 300, "initial population")
	_assert(first.get_visible_proxy_data().size() == 80, "visible proxy cap")
	_assert(first.get_visible_proxy_data(PackedStringArray(), 500).size() == 80, "hard proxy cap")
	var structured_name_count := 0
	for resident_id: String in first.sorted_npc_ids():
		var name_proxy: Dictionary = first.materialize_proxy(resident_id)
		var family_name := str(name_proxy.get("family_name", ""))
		var given_name := str(name_proxy.get("given_name", ""))
		var latin_display_name := str(name_proxy.get("latin_display_name", ""))
		_assert(family_name + given_name == str(name_proxy.get("display_name", "")), "structured name preserves the authoritative display name: %s" % resident_id)
		_assert(not latin_display_name.is_empty() and latin_display_name.contains(" "), "Latin-script name has a family/given boundary: %s" % resident_id)
		structured_name_count += 1
	_assert(structured_name_count == 300, "all 300 authoritative residents expose structured names")

	var first_id: String = first.sorted_npc_ids()[0]
	var attitude: Dictionary = first.calculate_policy_attitude(first_id, "parks", [
		{"key": "income", "score": 9},
		{"key": "preference", "score": 8},
		{"key": "education", "score": 7},
		{"key": "age", "score": -6},
		{"key": "address", "score": 5},
		{"key": "ignored_sixth", "score": 4},
	])
	_assert(int(attitude.modifier) == 10, "top-five modifier clamp")
	_assert(int(attitude.final) >= -100 and int(attitude.final) <= 100, "attitude bounds")

	var before_age: int = first.get_record(first_id).age
	first.advance_year(2, 365)
	_assert(first.get_record(first_id).age == before_age + 1, "annual aging")

	var created: Array[Dictionary] = first.generate_requests(366, {
		"park_count": 0,
		"hospital_count": 0,
		"school_count": 0,
		"utility_fee": 120,
	}, 4)
	_assert(created.size() == 4, "four deterministic request types")
	var request_id: String = str(created[0].request_id)
	_assert(first.accept_request(request_id, 367), "accept request")
	var request_type: String = str(created[0].request_type)
	var completed_context := {
		"park_count": 99,
		"hospital_count": 99,
		"school_count": 99,
		"utility_fee": 10,
	}
	_assert(first.complete_request(request_id, 368, completed_context), "complete request")
	_assert(first.event_book.events_for_subject(str(created[0].npc_id)).size() >= 3, "event book history")
	var rejected_request_id := str(created[1].request_id)
	_assert(first.reject_request(rejected_request_id, 367), "reject pending request")
	_assert(not first.accept_request(rejected_request_id, 368), "rejected request cannot be accepted")
	_assert(not first.complete_request(rejected_request_id, 368, completed_context), "rejected request cannot be completed")
	var rejected_request: Dictionary = first.requests[rejected_request_id].to_dict()
	_assert(str(rejected_request.get("status", "")) == "rejected", "rejected request reaches terminal status")
	_assert(int(rejected_request.get("rejected_day", -1)) == 367, "rejected request records its decision day")
	_assert(first.public_affairs_requests().size() == 4, "public-affairs history retains every request")
	_assert(first.active_requests().size() == 2, "completed and rejected requests leave only active requests")

	var json_text: String = first.to_json()
	var restored = PopulationSystem.from_json(json_text)
	_assert(restored != null, "JSON parse")
	if restored != null and first.stable_hash() != restored.stable_hash():
		_print_first_difference(first.to_json(), restored.to_json())
	_assert(first.stable_hash() == restored.stable_hash(), "JSON round-trip hash")
	_assert(first.stable_summary() == restored.stable_summary(), "stable summary")
	if restored != null:
		var restored_rejected: Dictionary = restored.requests[rejected_request_id].to_dict()
		_assert(str(restored_rejected.get("status", "")) == "rejected" and int(restored_rejected.get("rejected_day", -1)) == 367, "rejected status survives JSON round trip")

	var second = PopulationSystem.new()
	second.initialize(300, 42_4242)
	second.advance_year(2, 365)
	var second_created: Array[Dictionary] = second.generate_requests(366, {
		"park_count": 0,
		"hospital_count": 0,
		"school_count": 0,
		"utility_fee": 120,
	}, 4)
	second.accept_request(str(second_created[0].request_id), 367)
	second.complete_request(str(second_created[0].request_id), 368, completed_context)
	second.reject_request(str(second_created[1].request_id), 367)
	_assert(first.stable_hash() == second.stable_hash(), "same seed and commands")

	var operational_requests = PopulationSystem.new()
	operational_requests.initialize(300, 73_001)
	var operational_created: Array[Dictionary] = operational_requests.generate_requests(1, {
		"park_count": 99,
		"hospital_count": 99,
		"operational_hospital_count": 0,
		"operational_hospital_capacity": 0,
		"school_count": 99,
		"utility_fee": 0,
	}, 4)
	_assert(operational_created.size() == 1 and str(operational_created[0].get("request_type", "")) == "hospital", "operational hospital count takes precedence over the raw placed count")
	var operational_request_id := str(operational_created[0].get("request_id", ""))
	var operational_payload: Dictionary = operational_created[0].get("payload", {})
	_assert(int(operational_payload.get("target_min", 0)) == 2 and int(operational_payload.get("target_capacity", 0)) == 300, "new hospital requests preserve count and effective-capacity targets")
	_assert(operational_requests.accept_request(operational_request_id, 2), "operational healthcare request can be accepted")
	_assert(not operational_requests.can_complete_request(operational_request_id, {
		"hospital_count": 99,
		"operational_hospital_count": 2,
		"operational_hospital_capacity": 250,
	}), "placed hospital count cannot complete a request while effective capacity is insufficient")
	_assert(operational_requests.complete_request(operational_request_id, 3, {
		"hospital_count": 0,
		"operational_hospital_count": 2,
		"operational_hospital_capacity": 300,
	}), "operational count and sufficient effective capacity complete a healthcare request")

	var sufficient_healthcare = PopulationSystem.new()
	sufficient_healthcare.initialize(300, 73_002)
	var sufficient_created: Array[Dictionary] = sufficient_healthcare.generate_requests(1, {
		"park_count": 99,
		"hospital_count": 0,
		"operational_hospital_count": 2,
		"operational_hospital_capacity": 300,
		"school_count": 99,
		"utility_fee": 0,
	}, 4)
	_assert(sufficient_created.is_empty(), "sufficient operational healthcare suppresses the hospital request even when raw count is stale")

	var capacity_shortfall = PopulationSystem.new()
	capacity_shortfall.initialize(300, 73_003)
	var capacity_created: Array[Dictionary] = capacity_shortfall.generate_requests(1, {
		"park_count": 99,
		"hospital_count": 2,
		"operational_hospital_count": 2,
		"operational_hospital_capacity": 250,
		"school_count": 99,
		"utility_fee": 0,
	}, 4)
	_assert(capacity_created.size() == 1 and str(capacity_created[0].get("request_type", "")) == "hospital", "effective-capacity shortfall creates a hospital request even when count is sufficient")

	var legacy_healthcare = PopulationSystem.new()
	legacy_healthcare.initialize(300, 73_004)
	var legacy_created: Array[Dictionary] = legacy_healthcare.generate_requests(1, {
		"park_count": 99,
		"hospital_count": 0,
		"school_count": 99,
		"utility_fee": 0,
	}, 4)
	_assert(legacy_created.size() == 1 and str(legacy_created[0].get("request_type", "")) == "hospital", "legacy raw hospital contexts still create requests")
	var legacy_request_id := str(legacy_created[0].get("request_id", ""))
	_assert(legacy_healthcare.accept_request(legacy_request_id, 2), "legacy healthcare request can be accepted")
	_assert(legacy_healthcare.complete_request(legacy_request_id, 3, {"hospital_count": 2}), "legacy raw hospital count still completes requests without a capacity key")

	var capped = PopulationSystem.new()
	capped.initialize(900, 7)
	_assert(capped.population_count() == 500, "population hard cap")
	_assert(capped.add_resident() == "", "cannot exceed cap")
	_assert(capped.add_residents(10, 5, "test.cap").is_empty(), "bulk addition reports no residents beyond cap")

	var lifecycle = PopulationSystem.new()
	lifecycle.initialize(300, 42_4242)
	var baseline_ids: Array[String] = lifecycle.sorted_npc_ids()
	var added_ids: PackedStringArray = lifecycle.add_residents(3, 12, "test.building_completed", "building_test")
	_assert(added_ids.size() == 3 and lifecycle.population_count() == 303, "bulk addition creates the requested residents")
	_assert(added_ids[0] != added_ids[1] and added_ids[1] != added_ids[2], "bulk addition creates unique resident IDs")
	_assert(str(lifecycle.get_record(added_ids[0]).address_id) == "building_test", "new residents retain their source building address")
	var linked_request = PopulationRequest.new()
	linked_request.request_id = "request_remove_test"
	linked_request.npc_id = added_ids[0]
	linked_request.request_type = "park"
	lifecycle.requests[linked_request.request_id] = linked_request
	lifecycle.get_record(baseline_ids[0]).add_relationship(added_ids[0], "鄰居", 25)
	lifecycle.get_record(added_ids[0]).add_relationship(baseline_ids[0], "鄰居", 25)
	var removed_one: PackedStringArray = lifecycle.remove_residents_by_id(
		PackedStringArray([added_ids[0]]),
		13,
		"test.building_demolished"
	)
	_assert(removed_one == PackedStringArray([added_ids[0]]) and lifecycle.population_count() == 302, "exact removal deletes only the requested resident")
	_assert(not lifecycle.requests.has("request_remove_test"), "resident removal deletes requests that reference the resident")
	_assert(not lifecycle.get_record(baseline_ids[0]).relationships.has(added_ids[0]), "resident removal clears incoming relationships")
	var removed_rest: PackedStringArray = lifecycle.remove_residents_by_id(
		PackedStringArray([added_ids[1], added_ids[2], "npc_missing"]),
		14,
		"test.building_demolished"
	)
	_assert(removed_rest.size() == 2 and lifecycle.population_count() == 300, "exact removal ignores missing IDs without deleting a fallback resident")
	for baseline_id: String in baseline_ids:
		_assert(lifecycle.get_record(baseline_id) != null, "exact removal preserves baseline resident: %s" % baseline_id)
	var lifecycle_restored = PopulationSystem.from_json(lifecycle.to_json())
	_assert(lifecycle_restored != null and lifecycle_restored.stable_hash() == lifecycle.stable_hash(), "resident lifecycle survives a JSON round trip")

	var finance = PopulationSystem.new()
	finance.initialize(300, 42_4242)
	var finance_id: String = finance.sorted_npc_ids()[0]
	var finance_record = finance.get_record(finance_id)
	var legacy_income: int = finance_record.income
	_assert(finance_record.personality_tags.is_empty() and finance_record.appearance_tags.is_empty(), "new additive tag arrays start empty")
	_assert(finance_record.salary == null and finance_record.debt == null, "salary and debt start unknown instead of being inferred")
	_assert(finance.set_employment(finance_id, "commercial_test_job", 48_000), "employment can set an explicit salary")
	_assert(int(finance_record.salary) == 48_000 and finance_record.income == legacy_income, "salary remains distinct from current-month income")
	var capacity_matches: Array[Dictionary] = finance.match_open_jobs([
		{"job_id": "commercial_capacity_job", "slots": 2},
	], 1)
	_assert(capacity_matches.size() == 2, "job matcher consumes declared open capacity")
	_assert(finance.match_open_jobs([{"job_id": "commercial_capacity_job", "slots": 2}], 2).is_empty(), "occupied positions are not offered again next month")
	for match_result: Dictionary in capacity_matches:
		_assert(finance.get_record(str(match_result.get("npc_id", ""))).salary == null, "job matching does not invent an unknown salary")
	_assert(finance.record_income_transaction(finance_id, 0, "unknown_source", 100).is_empty(), "income ledger rejects unsupported source types")
	var salary_transaction: Dictionary = finance.record_income_transaction(finance_id, 0, "salary", 1_000, {"job_id": "commercial_test_job"})
	var investment_transaction: Dictionary = finance.record_income_transaction(finance_id, 29, "investment", 250)
	var insurance_transaction: Dictionary = finance.record_income_transaction(finance_id, 30, "insurance", 400)
	_assert(not salary_transaction.is_empty() and not investment_transaction.is_empty() and not insurance_transaction.is_empty(), "income ledger accepts explicit supported transactions")
	_assert(finance.monthly_income_total(finance_id, 1, 1) == 1_250, "month-one transaction total uses game-day boundaries")
	_assert(finance.monthly_income_total(finance_id, 1, 2) == 400, "month-two transaction total excludes prior month")
	_assert(finance.query_income_transactions(finance_id).size() == 3, "transactions can be queried by resident")
	_assert(finance_record.income == legacy_income, "transactions do not silently rewrite the compatibility income field")
	var finance_restored = PopulationSystem.from_json(finance.to_json())
	_assert(finance_restored != null and finance_restored.stable_hash() == finance.stable_hash(), "NPC finance fields and transaction ledger survive JSON round trip")
	if finance_restored != null:
		var next_transaction: Dictionary = finance_restored.record_income_transaction(finance_id, 31, "other", 25)
		_assert(str(next_transaction.get("transaction_id", "")) == "income_tx_00000004", "transaction sequence repairs and continues after load")

	var legacy_record_data: Dictionary = finance_record.to_dict()
	legacy_record_data["schema_version"] = 1
	for new_field in ["personality_tags", "appearance_tags", "salary", "debt"]:
		legacy_record_data.erase(new_field)
	var migrated_legacy_record = NpcRecord.from_dict(legacy_record_data)
	_assert(migrated_legacy_record.personality_tags.is_empty() and migrated_legacy_record.appearance_tags.is_empty(), "v1 residents receive safe empty tag defaults")
	_assert(migrated_legacy_record.salary == null and migrated_legacy_record.debt == null, "v1 residents do not fabricate salary or debt")
	_assert(migrated_legacy_record.income == legacy_income, "v1 resident income is preserved without salary inference")

	if not failed:
		print("Population subsystem self-test passed. NPCs=%d Hash=%s" % [first.population_count(), first.stable_hash()])
	quit(1 if failed else 0)


func _assert(condition: bool, label: String) -> void:
	if condition:
		return
	failed = true
	push_error("Population self-test failed: %s" % label)


func _print_first_difference(first: String, second: String) -> void:
	var limit := mini(first.length(), second.length())
	for index: int in range(limit):
		if first[index] != second[index]:
			print("Round-trip diff at %d\nA=%s\nB=%s" % [
				index,
				first.substr(maxi(0, index - 80), 160),
				second.substr(maxi(0, index - 80), 160),
			])
			return
	print("Round-trip lengths differ: %d vs %d" % [first.length(), second.length()])
