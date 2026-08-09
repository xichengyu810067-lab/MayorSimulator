class_name MayorPopulationSystem
extends RefCounted

const SaveSchemaAuthorityScript = preload("res://scripts/core/save_schema_authority.gd")

## Deterministic small-population simulation for the vertical slice.
## All 300-500 residents remain persistent; only proxy dictionaries are pooled for display.

const NpcRecordScript = preload("res://scripts/systems/population/npc_record.gd")
const PopulationRequestScript = preload("res://scripts/systems/population/population_request.gd")
const EventBookScript = preload("res://scripts/systems/population/event_book.gd")

const SCHEMA_VERSION := SaveSchemaAuthorityScript.POPULATION_CURRENT_SCHEMA_VERSION
const MIN_SUPPORTED_SCHEMA_VERSION := SaveSchemaAuthorityScript.POPULATION_MIN_SUPPORTED_SCHEMA_VERSION
const MAX_SUPPORTED_SCHEMA_VERSION := SaveSchemaAuthorityScript.POPULATION_MAX_SUPPORTED_SCHEMA_VERSION
const DEFAULT_INITIAL_POPULATION := 300
const MAX_POPULATION := 500
const DEFAULT_VISIBLE_PROXIES := 24
const MAX_VISIBLE_PROXIES := 80
const DEFAULT_SEED := 270_419
const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const INCOME_TRANSACTION_SOURCE_TYPES := [
	"salary", "investment", "insurance", "inheritance", "other",
]

const FIRST_NAMES := [
	"曉明", "雅婷", "家豪", "怡君", "志遠", "雨晴", "子涵", "柏宇",
	"佳穎", "承恩", "美玲", "建宏", "心妤", "冠廷", "婉如", "品妍",
]
const LAST_NAMES := ["王", "李", "陳", "林", "張", "黃", "吳", "劉", "蔡", "楊"]
const LATIN_FIRST_NAMES := {
	"曉明": "Xiaoming", "雅婷": "Yating", "家豪": "Jiahao", "怡君": "Yijun",
	"志遠": "Zhiyuan", "雨晴": "Yuqing", "子涵": "Zihan", "柏宇": "Boyu",
	"佳穎": "Jiaying", "承恩": "Chengen", "美玲": "Meiling", "建宏": "Jianhong",
	"心妤": "Xinyu", "冠廷": "Guanting", "婉如": "Wanru", "品妍": "Pinyan",
}
const LATIN_LAST_NAMES := {
	"王": "Wang", "李": "Li", "陳": "Chen", "林": "Lin", "張": "Zhang",
	"黃": "Huang", "吳": "Wu", "劉": "Liu", "蔡": "Tsai", "楊": "Yang",
}
const GENDERS := ["女性", "男性", "非二元"]
const PERSONALITIES := ["溫和", "務實", "熱心", "謹慎", "樂觀", "獨立", "好奇", "守序"]
const PREFERENCES := ["公園", "醫療", "教育", "治安", "低稅", "便利交通", "安靜", "就業"]
const EDUCATION_LEVELS := ["國中", "高中", "專科", "大學", "研究所"]
const JOBS := ["工業", "商業", "醫療", "教育", "公共服務", "服務業"]
const POLICY_IDS := ["parks", "healthcare", "education", "public_safety", "tax_rate", "utility_fee", "industry"]

var simulation_seed: int = DEFAULT_SEED
var next_npc_sequence: int = 1
var next_request_sequence: int = 1
var next_transaction_sequence: int = 1
var current_year: int = 1
var records: Dictionary = {}
var requests: Dictionary = {}
var income_transactions: Array[Dictionary] = []
var event_book = EventBookScript.new()
var _sorted_npc_id_cache: Array[String] = []
var _sorted_npc_id_cache_valid := false


func initialize(initial_count: int = DEFAULT_INITIAL_POPULATION, seed_value: int = DEFAULT_SEED) -> void:
	simulation_seed = absi(seed_value) if seed_value != 0 else DEFAULT_SEED
	next_npc_sequence = 1
	next_request_sequence = 1
	next_transaction_sequence = 1
	current_year = 1
	records.clear()
	_invalidate_sorted_npc_id_cache()
	requests.clear()
	income_transactions.clear()
	event_book = EventBookScript.new()
	var safe_count := clampi(initial_count, 0, MAX_POPULATION)
	for index: int in range(safe_count):
		var record = _create_record(index)
		records[record.npc_id] = record
		_append_sorted_npc_id_cache(record.npc_id)
	_build_initial_sparse_relationships()
	event_book.append(0, "population_initialized", "city", "population_seeded", {
		"population": safe_count,
		"seed": simulation_seed,
	})


func population_count() -> int:
	return records.size()


func add_resident(seed_salt: int = 0) -> String:
	var added_ids := add_residents(1, 0, "population_growth", "", seed_salt)
	return added_ids[0] if not added_ids.is_empty() else ""


func add_residents(
	count: int,
	game_day: int,
	reason_tag: String,
	address_id: String = "",
	seed_salt: int = 0
) -> PackedStringArray:
	var added_ids := PackedStringArray()
	for offset: int in range(maxi(0, count)):
		if records.size() >= MAX_POPULATION:
			break
		var index := next_npc_sequence - 1
		var original_seed := simulation_seed
		simulation_seed = _positive_mod(simulation_seed + (seed_salt + offset) * 97, 2_147_483_647)
		var record = _create_record(index)
		simulation_seed = original_seed
		if not address_id.is_empty():
			record.address_id = address_id
		records[record.npc_id] = record
		_append_sorted_npc_id_cache(record.npc_id)
		added_ids.append(record.npc_id)
		event_book.append(game_day, "resident_added", record.npc_id, reason_tag, {
			"address_id": record.address_id,
		})
	return added_ids


func remove_residents(
	count: int,
	game_day: int,
	reason_tag: String
) -> PackedStringArray:
	var candidates := _cached_sorted_npc_ids().duplicate()
	candidates.reverse()
	var requested := PackedStringArray()
	for npc_id: String in candidates:
		if requested.size() >= maxi(0, count):
			break
		requested.append(npc_id)
	return remove_residents_by_id(requested, game_day, reason_tag)


func remove_residents_by_id(
	npc_ids: PackedStringArray,
	game_day: int,
	reason_tag: String
) -> PackedStringArray:
	var removed_ids := PackedStringArray()
	var seen := {}
	for npc_id: String in npc_ids:
		if seen.has(npc_id) or not records.has(npc_id):
			continue
		seen[npc_id] = true
		for request_id: String in sorted_request_ids():
			if str(requests[request_id].npc_id) == npc_id:
				requests.erase(request_id)
		for other_id: String in _cached_sorted_npc_ids():
			if other_id != npc_id:
				records[other_id].remove_relationship(npc_id)
		var removed_record = records[npc_id]
		records.erase(npc_id)
		_invalidate_sorted_npc_id_cache()
		removed_ids.append(npc_id)
		event_book.append(game_day, "resident_removed", npc_id, reason_tag, {
			"address_id": str(removed_record.address_id),
		})
	return removed_ids


func get_record(npc_id: String):
	return records.get(npc_id)


func set_employment(npc_id: String, job_id: String, monthly_salary: int = -1) -> bool:
	var record = records.get(npc_id)
	if record == null:
		return false
	record.job_id = job_id
	# Salary is the recurring job offer. Income remains the authoritative
	# current-month total and is changed only by an explicit settlement flow.
	record.salary = maxi(0, monthly_salary) if not job_id.is_empty() and monthly_salary >= 0 else null
	record.employment_state = "在職" if not job_id.is_empty() else "待業"
	return true


func record_income_transaction(
	npc_id: String,
	game_day: int,
	source_type: String,
	amount: int,
	metadata: Dictionary = {}
) -> Dictionary:
	var normalized_source := source_type.strip_edges().to_lower()
	if not records.has(npc_id) or normalized_source not in INCOME_TRANSACTION_SOURCE_TYPES or amount <= 0 or game_day < 0:
		return {}
	var transaction := {
		"transaction_id": "income_tx_%08d" % next_transaction_sequence,
		"npc_id": npc_id,
		"game_day": game_day,
		"source_type": normalized_source,
		"amount": amount,
		"metadata": metadata.duplicate(true),
	}
	next_transaction_sequence += 1
	income_transactions.append(transaction)
	return transaction.duplicate(true)


func query_income_transactions(
	npc_id: String = "",
	from_game_day: int = -1,
	to_game_day: int = -1
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for transaction: Dictionary in income_transactions:
		if not npc_id.is_empty() and str(transaction.get("npc_id", "")) != npc_id:
			continue
		var transaction_day := int(transaction.get("game_day", -1))
		if from_game_day >= 0 and transaction_day < from_game_day:
			continue
		if to_game_day >= 0 and transaction_day > to_game_day:
			continue
		result.append(transaction.duplicate(true))
	return result


func income_transactions_for_month(npc_id: String, year: int, month: int) -> Array[Dictionary]:
	if year < 1 or month < 1 or month > MONTHS_PER_YEAR:
		return []
	var first_day := (year - 1) * MONTHS_PER_YEAR * DAYS_PER_MONTH + (month - 1) * DAYS_PER_MONTH
	return query_income_transactions(npc_id, first_day, first_day + DAYS_PER_MONTH - 1)


func monthly_income_total(npc_id: String, year: int, month: int) -> int:
	var total := 0
	for transaction: Dictionary in income_transactions_for_month(npc_id, year, month):
		total += int(transaction.get("amount", 0))
	return total


func resident_income_total() -> int:
	var total := 0
	for npc_id: String in _cached_sorted_npc_ids():
		total += maxi(0, int(records[npc_id].income))
	return total


func match_open_jobs(open_jobs: Array[Dictionary], game_day: int) -> Array[Dictionary]:
	## A simple deterministic matcher: jobs are stable-sorted, then unemployed residents by ID.
	var jobs: Array[Dictionary] = []
	for job: Dictionary in open_jobs:
		jobs.append(job.duplicate(true))
	jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("job_id", "")) < str(b.get("job_id", ""))
	)
	var unemployed := _record_ids_with_state("待業")
	var occupied_by_job := {}
	for npc_id: String in _cached_sorted_npc_ids():
		var existing_record = records[npc_id]
		if existing_record.employment_state != "在職" or existing_record.job_id.is_empty():
			continue
		occupied_by_job[existing_record.job_id] = int(occupied_by_job.get(existing_record.job_id, 0)) + 1
	var cursor := 0
	var matches: Array[Dictionary] = []
	for job: Dictionary in jobs:
		var job_id := str(job.get("job_id", ""))
		var slots := maxi(0, int(job.get("slots", 0)) - int(occupied_by_job.get(job_id, 0)))
		while slots > 0 and cursor < unemployed.size():
			var npc_id: String = unemployed[cursor]
			cursor += 1
			slots -= 1
			set_employment(npc_id, job_id, int(job.get("salary", -1)))
			var match_result := {"npc_id": npc_id, "job_id": job_id}
			matches.append(match_result)
			event_book.append(game_day, "employment_started", npc_id, "job_matched", match_result)
	return matches


func advance_year(new_year: int, game_day: int) -> int:
	if new_year <= current_year:
		return 0
	var years_elapsed := new_year - current_year
	var ids := _cached_sorted_npc_ids()
	for npc_id: String in ids:
		var record = records[npc_id]
		record.age += years_elapsed
	current_year = new_year
	event_book.append(game_day, "population_aged", "city", "annual_aging", {
		"years_elapsed": years_elapsed,
		"population": records.size(),
	})
	return years_elapsed


func calculate_policy_attitude(
	npc_id: String,
	policy_id: String,
	modifiers: Array[Dictionary]
) -> Dictionary:
	var record = records.get(npc_id)
	if record == null:
		return {"base": 0, "modifier": 0, "final": 0, "applied": []}
	var normalized: Array[Dictionary] = []
	for modifier: Dictionary in modifiers:
		normalized.append({
			"key": str(modifier.get("key", "")),
			"score": clampi(int(modifier.get("score", 0)), -10, 10),
		})
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_abs := absi(int(a.get("score", 0)))
		var b_abs := absi(int(b.get("score", 0)))
		if a_abs == b_abs:
			return str(a.get("key", "")) < str(b.get("key", ""))
		return a_abs > b_abs
	)
	var applied: Array[Dictionary] = []
	var modifier_total := 0
	for index: int in range(mini(5, normalized.size())):
		var item: Dictionary = normalized[index]
		applied.append(item.duplicate(true))
		modifier_total += int(item.get("score", 0))
	modifier_total = clampi(modifier_total, -10, 10)
	var base: int = record.get_base_attitude(policy_id)
	return {
		"base": base,
		"modifier": modifier_total,
		"final": clampi(base + modifier_total, -100, 100),
		"applied": applied,
	}


func get_visible_proxy_data(requested_ids: PackedStringArray = PackedStringArray(), limit: int = DEFAULT_VISIBLE_PROXIES) -> Array[Dictionary]:
	var safe_limit := clampi(limit, 0, MAX_VISIBLE_PROXIES)
	if requested_ids.is_empty():
		return _materialize_proxy_ids(_cached_sorted_npc_ids(), safe_limit)
	var source_ids: Array[String] = []
	var seen := {}
	for npc_id: String in requested_ids:
		if records.has(npc_id) and not seen.has(npc_id):
			seen[npc_id] = true
			source_ids.append(npc_id)
	return _materialize_proxy_ids(source_ids, safe_limit)


## Returns one deterministic, unique cohort without re-sorting the population.
## Consecutive cohort indices tile the cached ID order and wrap only after the
## complete population has been covered.
func get_bounded_deterministic_cohort(cohort_size: int, cohort_index: int) -> PackedStringArray:
	var ids := _cached_sorted_npc_ids()
	var safe_size := clampi(cohort_size, 0, ids.size())
	var cohort := PackedStringArray()
	if safe_size == 0:
		return cohort
	var start := _positive_mod(cohort_index * safe_size, ids.size())
	for offset: int in range(safe_size):
		cohort.append(ids[(start + offset) % ids.size()])
	return cohort


func _materialize_proxy_ids(source_ids: Array[String], limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(mini(limit, source_ids.size())):
		var proxy := materialize_proxy(source_ids[index])
		if not proxy.is_empty():
			result.append(proxy)
	return result


func materialize_proxy(npc_id: String) -> Dictionary:
	var record = records.get(npc_id)
	if record == null:
		return {}
	var name_parts := _generated_name_parts(record.display_name)
	return {
		"npc_id": record.npc_id,
		"display_name": record.display_name,
		"family_name": str(name_parts.get("family_name", "")),
		"given_name": str(name_parts.get("given_name", "")),
		"latin_display_name": str(name_parts.get("latin_display_name", "")),
		"age": record.age,
		"gender": record.gender,
		"personality": record.personality,
		"personality_tags": Array(record.personality_tags),
		"appearance_tags": Array(record.appearance_tags),
		"education": record.education,
		"income": record.income,
		"salary": record.salary,
		"debt": record.debt,
		"address_id": record.address_id,
		"job_id": record.job_id,
		"employment_state": record.employment_state,
		"archetype": _proxy_archetype(record),
	}


func _generated_name_parts(display_name: String) -> Dictionary:
	## Keep the persisted display name authoritative while exposing the two
	## generated name components for locale-aware presentation.  Longest-prefix
	## matching keeps this compatible if compound family names are added later.
	var family_name := ""
	for candidate_variant: Variant in LAST_NAMES:
		var candidate := str(candidate_variant)
		if (
			display_name.length() > candidate.length()
			and display_name.begins_with(candidate)
			and candidate.length() > family_name.length()
		):
			family_name = candidate
	if family_name.is_empty():
		return {
			"family_name": "",
			"given_name": "",
			"latin_display_name": "",
		}
	var given_name := display_name.substr(family_name.length())
	var latin_family := str(LATIN_LAST_NAMES.get(family_name, ""))
	var latin_given := str(LATIN_FIRST_NAMES.get(given_name, ""))
	var latin_display_name := ""
	if not latin_family.is_empty() and not latin_given.is_empty():
		latin_display_name = "%s %s" % [latin_family, latin_given]
	return {
		"family_name": family_name,
		"given_name": given_name,
		"latin_display_name": latin_display_name,
	}


func generate_requests(game_day: int, city_context: Dictionary, max_new: int = 4) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var resident_count := maxi(1, records.size())
	var required_parks := maxi(1, ceili(float(resident_count) / 150.0))
	var required_hospitals := maxi(1, ceili(float(resident_count) / 250.0))
	var required_schools := maxi(1, ceili(float(resident_count) / 200.0))
	var parks := int(city_context.get("park_count", city_context.get("parks", 0)))
	var hospitals := _effective_hospital_count(city_context)
	var has_effective_hospital_capacity := _has_effective_hospital_capacity(city_context)
	var effective_hospital_capacity := _effective_hospital_capacity(city_context)
	var schools := int(city_context.get("school_count", city_context.get("schools", 0)))
	var utility_fee := int(city_context.get("utility_fee", 0))
	if parks < required_parks:
		candidates.append(_request_template("park", {"target_min": required_parks}))
	if hospitals < required_hospitals or (has_effective_hospital_capacity and effective_hospital_capacity < resident_count):
		var hospital_payload := {"target_min": required_hospitals}
		if has_effective_hospital_capacity:
			hospital_payload["target_capacity"] = resident_count
		candidates.append(_request_template("hospital", hospital_payload))
	if schools < required_schools:
		candidates.append(_request_template("school", {"target_min": required_schools}))
	if utility_fee > 80:
		candidates.append(_request_template("lower_fee", {"target_max": 80, "fee_key": "utility_fee"}))
	var created: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if created.size() >= maxi(0, max_new):
			break
		var request_type := str(candidate.get("request_type", ""))
		if _has_active_request_type(request_type):
			continue
		var npc_id := _select_request_npc(game_day, request_type)
		if npc_id.is_empty():
			break
		var request = PopulationRequestScript.new()
		request.request_id = "request_%06d" % next_request_sequence
		next_request_sequence += 1
		request.npc_id = npc_id
		request.request_type = request_type
		request.title = str(candidate.get("title", "居民請求"))
		request.description = str(candidate.get("description", ""))
		request.created_day = game_day
		request.payload = Dictionary(candidate.get("payload", {})).duplicate(true)
		requests[request.request_id] = request
		created.append(request.to_dict())
		event_book.append(game_day, "npc_request_created", npc_id, "resident_request", {
			"request_id": request.request_id,
			"request_type": request_type,
		})
	return created


func accept_request(request_id: String, game_day: int) -> bool:
	var request = requests.get(request_id)
	if request == null or not request.accept(game_day):
		return false
	event_book.append(game_day, "npc_request_accepted", request.npc_id, "request_accepted", {
		"request_id": request_id,
		"request_type": request.request_type,
	})
	return true


func reject_request(request_id: String, game_day: int) -> bool:
	var request = requests.get(request_id)
	if request == null or not request.reject(game_day):
		return false
	event_book.append(game_day, "npc_request_rejected", request.npc_id, "request_rejected", {
		"request_id": request_id,
		"request_type": request.request_type,
	})
	return true


func can_complete_request(request_id: String, city_context: Dictionary) -> bool:
	var request = requests.get(request_id)
	if request == null or request.status != PopulationRequestScript.STATUS_ACCEPTED:
		return false
	match request.request_type:
		"park":
			return int(city_context.get("park_count", city_context.get("parks", 0))) >= int(request.payload.get("target_min", 1))
		"hospital":
			if _effective_hospital_count(city_context) < int(request.payload.get("target_min", 1)):
				return false
			if _has_effective_hospital_capacity(city_context):
				var target_capacity := maxi(
					1,
					int(request.payload.get("target_capacity", records.size()))
				)
				return _effective_hospital_capacity(city_context) >= target_capacity
			return true
		"school":
			return int(city_context.get("school_count", city_context.get("schools", 0))) >= int(request.payload.get("target_min", 1))
		"lower_fee":
			var fee_key := str(request.payload.get("fee_key", "utility_fee"))
			return int(city_context.get(fee_key, 0)) <= int(request.payload.get("target_max", 80))
		_:
			return false


func complete_request(request_id: String, game_day: int, city_context: Dictionary) -> bool:
	if not can_complete_request(request_id, city_context):
		return false
	var request = requests[request_id]
	if not request.complete(game_day):
		return false
	event_book.append(game_day, "npc_request_completed", request.npc_id, "major_person_event", {
		"request_id": request_id,
		"request_type": request.request_type,
		"title": request.title,
	})
	return true


func _effective_hospital_count(city_context: Dictionary) -> int:
	if city_context.has("operational_hospital_count"):
		return maxi(0, int(city_context.get("operational_hospital_count", 0)))
	return maxi(0, int(city_context.get("hospital_count", city_context.get("hospitals", 0))))


func _has_effective_hospital_capacity(city_context: Dictionary) -> bool:
	return (
		city_context.has("operational_hospital_capacity")
		or city_context.has("effective_hospital_capacity")
		or city_context.has("healthcare_capacity")
	)


func _effective_hospital_capacity(city_context: Dictionary) -> int:
	if city_context.has("operational_hospital_capacity"):
		return maxi(0, int(city_context.get("operational_hospital_capacity", 0)))
	if city_context.has("effective_hospital_capacity"):
		return maxi(0, int(city_context.get("effective_hospital_capacity", 0)))
	return maxi(0, int(city_context.get("healthcare_capacity", 0)))


func active_requests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for request_id: String in sorted_request_ids():
		var request = requests[request_id]
		if request.is_active():
			result.append(request.to_dict())
	return result


func public_affairs_requests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for request_id: String in sorted_request_ids():
		result.append(requests[request_id].to_dict())
	return result


func sorted_npc_ids() -> Array[String]:
	return _cached_sorted_npc_ids().duplicate()


func _cached_sorted_npc_ids() -> Array[String]:
	if not _sorted_npc_id_cache_valid:
		_sorted_npc_id_cache.clear()
		for key: Variant in records.keys():
			_sorted_npc_id_cache.append(str(key))
		_sorted_npc_id_cache.sort()
		_sorted_npc_id_cache_valid = true
	return _sorted_npc_id_cache


func _invalidate_sorted_npc_id_cache() -> void:
	_sorted_npc_id_cache.clear()
	_sorted_npc_id_cache_valid = false


func _append_sorted_npc_id_cache(npc_id: String) -> void:
	if _sorted_npc_id_cache_valid:
		_sorted_npc_id_cache.append(npc_id)


func sorted_request_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in requests.keys():
		ids.append(str(key))
	ids.sort()
	return ids


func stable_summary() -> Dictionary:
	var employed := 0
	var unemployed := 0
	var age_total := 0
	var relationship_edges := 0
	for npc_id: String in _cached_sorted_npc_ids():
		var record = records[npc_id]
		age_total += record.age
		relationship_edges += record.relationships.size()
		if record.employment_state == "在職":
			employed += 1
		else:
			unemployed += 1
	var completed_requests := 0
	for request_id: String in sorted_request_ids():
		if requests[request_id].status == PopulationRequestScript.STATUS_COMPLETED:
			completed_requests += 1
	return {
		"population": records.size(),
		"employed": employed,
		"unemployed": unemployed,
		"age_total": age_total,
		"relationship_edges": relationship_edges,
		"requests": requests.size(),
		"completed_requests": completed_requests,
		"income_transactions": income_transactions.size(),
		"event_count": event_book.events.size(),
		"current_year": current_year,
	}


func to_dict() -> Dictionary:
	var npc_data: Array[Dictionary] = []
	for npc_id: String in _cached_sorted_npc_ids():
		npc_data.append(records[npc_id].to_dict())
	var request_data: Array[Dictionary] = []
	for request_id: String in sorted_request_ids():
		request_data.append(requests[request_id].to_dict())
	return {
		"schema_version": SCHEMA_VERSION,
		"simulation_seed": simulation_seed,
		"next_npc_sequence": next_npc_sequence,
		"next_request_sequence": next_request_sequence,
		"next_transaction_sequence": next_transaction_sequence,
		"current_year": current_year,
		"records": npc_data,
		"requests": request_data,
		"income_transactions": income_transactions.duplicate(true),
		"event_book": event_book.to_dict(),
	}


func to_json() -> String:
	return JSON.stringify(_canonicalize(to_dict()))


func stable_hash() -> String:
	return to_json().sha256_text()


static func from_dict(data: Dictionary):
	var schema_value: Variant = data.get("schema_version", MIN_SUPPORTED_SCHEMA_VERSION)
	if not _is_integer_value(schema_value):
		return null
	var schema_version := int(schema_value)
	if schema_version < MIN_SUPPORTED_SCHEMA_VERSION or schema_version > MAX_SUPPORTED_SCHEMA_VERSION:
		return null
	var system = new()
	system.simulation_seed = int(data.get("simulation_seed", DEFAULT_SEED))
	system.next_npc_sequence = maxi(1, int(data.get("next_npc_sequence", 1)))
	system.next_request_sequence = maxi(1, int(data.get("next_request_sequence", 1)))
	system.next_transaction_sequence = maxi(1, int(data.get("next_transaction_sequence", 1)))
	system.current_year = maxi(1, int(data.get("current_year", 1)))
	system.records.clear()
	var record_values: Array = data.get("records", [])
	for value: Variant in record_values:
		if value is Dictionary:
			var record = NpcRecordScript.from_dict(value)
			if record != null and not record.npc_id.is_empty() and system.records.size() < MAX_POPULATION:
				system.records[record.npc_id] = record
	system._invalidate_sorted_npc_id_cache()
	system.requests.clear()
	var request_values: Array = data.get("requests", [])
	for value: Variant in request_values:
		if value is Dictionary:
			var request = PopulationRequestScript.from_dict(value)
			if not request.request_id.is_empty():
				system.requests[request.request_id] = request
	system.income_transactions.clear()
	var transaction_ids := {}
	var highest_transaction_sequence := 0
	var transaction_values: Array = data.get("income_transactions", [])
	for value: Variant in transaction_values:
		if not value is Dictionary:
			continue
		var source: Dictionary = value
		var transaction_id := str(source.get("transaction_id", "")).strip_edges()
		var npc_id := str(source.get("npc_id", "")).strip_edges()
		var source_type := str(source.get("source_type", "")).strip_edges().to_lower()
		var game_day := int(source.get("game_day", -1))
		var amount := int(source.get("amount", 0))
		if transaction_id.is_empty() or transaction_ids.has(transaction_id) or npc_id.is_empty() or source_type not in INCOME_TRANSACTION_SOURCE_TYPES or game_day < 0 or amount <= 0:
			continue
		var metadata_value: Variant = source.get("metadata", {})
		var metadata: Dictionary = Dictionary(metadata_value).duplicate(true) if metadata_value is Dictionary else {}
		system.income_transactions.append({
			"transaction_id": transaction_id,
			"npc_id": npc_id,
			"game_day": game_day,
			"source_type": source_type,
			"amount": amount,
			"metadata": metadata,
		})
		transaction_ids[transaction_id] = true
		var suffix := transaction_id.trim_prefix("income_tx_")
		if suffix.is_valid_int():
			highest_transaction_sequence = maxi(highest_transaction_sequence, int(suffix))
	system.income_transactions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("transaction_id", "")) < str(b.get("transaction_id", ""))
	)
	system.next_transaction_sequence = maxi(system.next_transaction_sequence, highest_transaction_sequence + 1)
	system.event_book = EventBookScript.from_dict(data.get("event_book", {}))
	return system


static func from_json(json_text: String):
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		return null
	return from_dict(parsed)


func _create_record(index: int):
	var record = NpcRecordScript.new()
	record.npc_id = "npc_%06d" % next_npc_sequence
	next_npc_sequence += 1
	var last_name: String = LAST_NAMES[_sample(index, 11, LAST_NAMES.size())]
	var first_name: String = FIRST_NAMES[_sample(index, 23, FIRST_NAMES.size())]
	record.display_name = "%s%s" % [last_name, first_name]
	record.age = 18 + _sample(index, 31, 57)
	record.gender = GENDERS[_sample(index, 47, GENDERS.size())]
	record.personality = PERSONALITIES[_sample(index, 59, PERSONALITIES.size())]
	var first_preference: String = PREFERENCES[_sample(index, 71, PREFERENCES.size())]
	var second_preference: String = PREFERENCES[_sample(index, 83, PREFERENCES.size())]
	if second_preference == first_preference:
		second_preference = PREFERENCES[(PREFERENCES.find(second_preference) + 1) % PREFERENCES.size()]
	record.preferences = PackedStringArray([first_preference, second_preference])
	record.education = EDUCATION_LEVELS[_sample(index, 97, EDUCATION_LEVELS.size())]
	record.address_id = "home_%03d" % (1 + index % 96)
	var is_employed := _sample(index, 109, 100) >= 12
	if is_employed:
		record.job_id = "%s_%03d" % [JOBS[_sample(index, 127, JOBS.size())], 1 + index % 40]
		record.employment_state = "在職"
		record.income = 24_000 + _sample(index, 139, 57_001)
	else:
		record.job_id = ""
		record.employment_state = "待業"
		record.income = 0
	for policy_id: String in POLICY_IDS:
		var salt := 151 + POLICY_IDS.find(policy_id) * 17
		record.set_base_attitude(policy_id, _sample(index, salt, 201) - 100)
	return record


func _build_initial_sparse_relationships() -> void:
	var ids := _cached_sorted_npc_ids()
	for index: int in range(ids.size()):
		if index > 0 and index % 2 == 0:
			_connect(ids[index], ids[index - 1], "鄰居", 20 + _sample(index, 211, 61))
		if index >= 3 and index % 5 == 0:
			_connect(ids[index], ids[index - 3], "同事", 10 + _sample(index, 223, 51))


func _connect(first_id: String, second_id: String, relationship_type: String, affinity: int) -> void:
	if not records.has(first_id) or not records.has(second_id):
		return
	records[first_id].add_relationship(second_id, relationship_type, affinity)
	records[second_id].add_relationship(first_id, relationship_type, affinity)


func _record_ids_with_state(state: String) -> Array[String]:
	var result: Array[String] = []
	for npc_id: String in _cached_sorted_npc_ids():
		if records[npc_id].employment_state == state:
			result.append(npc_id)
	return result


func _proxy_archetype(record) -> String:
	if record.age >= 65:
		return "老年居民"
	if record.employment_state == "待業":
		return "一般居民"
	if record.job_id.begins_with("工業"):
		return "工人"
	if record.job_id.begins_with("商業") or record.job_id.begins_with("服務業"):
		return "商人"
	if record.job_id.begins_with("公共服務"):
		return "公務人員"
	return "一般居民"


func _request_template(request_type: String, payload: Dictionary) -> Dictionary:
	match request_type:
		"park":
			return {"request_type": request_type, "title": "想要一座公園", "description": "居民希望城市多一處能散步與休息的綠地。", "payload": payload}
		"hospital":
			return {"request_type": request_type, "title": "醫療就在身邊", "description": "居民希望增設醫院，縮短就醫距離。", "payload": payload}
		"school":
			return {"request_type": request_type, "title": "讓孩子安心上學", "description": "居民希望城市增設學校與學習空間。", "payload": payload}
		"lower_fee":
			return {"request_type": request_type, "title": "生活費能再輕一點", "description": "居民希望降低目前過高的公共事業費。", "payload": payload}
		_:
			return {"request_type": request_type, "title": "居民請求", "description": "", "payload": payload}


func _has_active_request_type(request_type: String) -> bool:
	for request_id: String in sorted_request_ids():
		var request = requests[request_id]
		if request.request_type == request_type and request.is_active():
			return true
	return false


func _select_request_npc(game_day: int, request_type: String) -> String:
	var ids := _cached_sorted_npc_ids()
	if ids.is_empty():
		return ""
	var type_salt := 0
	for character: String in request_type:
		type_salt += character.unicode_at(0)
	var selected_index := _sample(game_day + next_request_sequence, 251 + type_salt, ids.size())
	return ids[selected_index]


func _sample(index: int, salt: int, modulo: int) -> int:
	if modulo <= 0:
		return 0
	var modulus := 2_147_483_647
	var value := _positive_mod(simulation_seed, modulus)
	value = _positive_mod(value * 48_271 + (index + 1) * 69_621 + salt * 907, modulus)
	value = _positive_mod(value * 40_692 + salt * 131 + index * 17, modulus)
	return _positive_mod(value, modulo)


static func _positive_mod(value: int, modulo: int) -> int:
	var result := value % modulo
	return result + modulo if result < 0 else result


static func _is_integer_value(value: Variant) -> bool:
	return value is int or (value is float and is_finite(float(value)) and float(value) == roundf(float(value)))


static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		var keys: Array = source.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var result := {}
		for key: Variant in keys:
			result[str(key)] = _canonicalize(source[key])
		return result
	if value is Array:
		var array_result: Array = []
		for item: Variant in value:
			array_result.append(_canonicalize(item))
		return array_result
	if value is PackedStringArray:
		return Array(value)
	# JSON has one numeric type. Normalizing integers prevents an otherwise
	# identical save from hashing differently after JSON.parse_string().
	if typeof(value) == TYPE_INT:
		return float(value)
	return value
